// runPollingBackstop — FR-004 (wheel-wait-all-redesign).
//
// For each teammate currently `status='running'` in
// `parent.teams[teamRef].teammates`, reconcile against:
//   1. live `.wheel/state_*.json` files (alternate_agent_id set)
//   2. archived state files in `.wheel/history/{success,failure,stopped}/`
//   3. orphan default — child state file disappeared without an archive
//
// One parent-flock write at the end. Bounded I/O: one `.wheel/` readdir +
// up to three history-bucket scans per invocation regardless of teammate
// count.
//
// Extracted from `dispatchers/team-wait.ts` to keep the dispatcher under
// the 250-line target. The dispatcher imports this directly.

import { promises as fs } from 'fs';
import path from 'path';
import { stateRead, stateWrite } from '../shared/state.js';
import type { TeammateStatus } from '../shared/state.js';
import { stateList } from './state.js';
import { withLockBlocking } from './lock.js';
import { wheelLog } from './log.js';

type TerminalStatus = Extract<TeammateStatus, 'completed' | 'failed'>;

interface BucketDef {
  name: 'success' | 'failure' | 'stopped';
  status: TerminalStatus;
}

const BUCKETS: ReadonlyArray<BucketDef> = [
  { name: 'success', status: 'completed' },
  { name: 'failure', status: 'failed' },
  { name: 'stopped', status: 'failed' },
];

interface Resolution {
  name: string;
  newStatus: TerminalStatus;
  failureReason?: string;
}

export interface PollingBackstopResult {
  reconciledCount: number;
  stillRunningCount: number;
}

export async function runPollingBackstop(
  parentStateFile: string,
  teamRef: string,
): Promise<PollingBackstopResult> {
  const preState = await safeRead(parentStateFile);
  if (!preState) return { reconciledCount: 0, stillRunningCount: 0 };

  const team = preState.teams?.[teamRef];
  if (!team) {
    await wheelLog('wait_all_polling', {
      parent_state_file: parentStateFile, team_id: teamRef,
      reconciled_count: 0, still_running_count: 0,
      note: 'team_not_found',
    });
    return { reconciledCount: 0, stillRunningCount: 0 };
  }

  // Treat both 'running' and 'pending' (non-terminal) slots as candidates
  // for backstop reconciliation. Slot status never transitions through
  // 'running' in the current pipeline (archiveWorkflow's
  // maybeUpdateParentSlot writes 'completed'/'failed' directly from
  // 'pending'), so a 'running'-only filter excludes EVERY slot and
  // collectStuckAgentIds is never reached.
  //
  // Verified failure: bifrost-minimax-team-mixed-model 2026-05-08 14:24
  // — fast-worker child workflow stalled at do-work agent step
  // status=working, parent slot remained at 'pending' for 11+ minutes,
  // wait_all_polling logged still_running_count=0 every tick (because
  // the early return fired), polling backstop never marked the slot
  // failed, parent never advanced past wait-all.
  const runningSlots = Object.entries(team.teammates ?? {})
    .filter(([, slot]) => slot?.status === 'running' || slot?.status === 'pending');
  if (runningSlots.length === 0) {
    await wheelLog('wait_all_polling', {
      parent_state_file: parentStateFile, team_id: teamRef,
      reconciled_count: 0, still_running_count: 0,
    });
    return { reconciledCount: 0, stillRunningCount: 0 };
  }

  const liveAgentIds = await collectLiveAgentIds();
  const bucketArchives = await collectBucketArchives(parentStateFile);
  const stuckAgentIds = await collectStuckAgentIds(parentStateFile);

  const { resolutions, stillRunning } =
    classifyRunningSlots(runningSlots, liveAgentIds, bucketArchives, stuckAgentIds);

  const reconciledCount = resolutions.length > 0
    ? await applyResolutions(parentStateFile, teamRef, resolutions)
    : 0;

  await wheelLog('wait_all_polling', {
    parent_state_file: parentStateFile, team_id: teamRef,
    reconciled_count: reconciledCount, still_running_count: stillRunning,
  });
  return { reconciledCount, stillRunningCount: stillRunning };
}

async function safeRead(stateFile: string) {
  try { return await stateRead(stateFile); } catch { return null; }
}

async function collectLiveAgentIds(): Promise<Set<string>> {
  const live = new Set<string>();
  let files: string[];
  try { files = await stateList(); } catch { return live; }
  for (const sf of files) {
    try {
      const ss = await stateRead(sf);
      if (ss.alternate_agent_id) live.add(ss.alternate_agent_id);
    } catch { /* unreadable — ignore */ }
  }
  return live;
}

/**
 * Idea 4: scan live child state files for "stuck worker" symptoms.
 *
 * A child is stuck when:
 *   - Its current step is type=agent (worker action required)
 *   - Status is pending OR working (not yet terminal)
 *   - Its updated_at is older than STUCK_THRESHOLD_MS (no recent
 *     state mutation = worker is not making progress)
 *
 * Returns the set of alternate_agent_ids belonging to stuck children.
 * The caller fails those slots in the parent — caps the maximum
 * coordination time per fixture and prevents indefinite hangs when
 * a worker session dies without archiving.
 */
const STUCK_THRESHOLD_MS = 5 * 60 * 1000; // 5 min

async function collectStuckAgentIds(parentStateFile: string): Promise<Set<string>> {
  const stuck = new Set<string>();
  const now = Date.now();
  let files: string[];
  try { files = await stateList(); } catch { return stuck; }
  for (const sf of files) {
    if (sf === parentStateFile) continue;
    try {
      const cs = await stateRead(sf);
      if (!cs.alternate_agent_id) continue;
      const cursor = cs.cursor ?? 0;
      const step = cs.steps?.[cursor];
      if (!step) continue;
      const isAgentStep = step.type === 'agent';
      const isUnterminated = step.status === 'pending' || step.status === 'working';
      if (!(isAgentStep && isUnterminated)) continue;
      const updatedAtMs = cs.updated_at ? Date.parse(cs.updated_at) : NaN;
      if (Number.isFinite(updatedAtMs) && (now - updatedAtMs) > STUCK_THRESHOLD_MS) {
        stuck.add(cs.alternate_agent_id);
      }
    } catch { /* unreadable — ignore */ }
  }
  return stuck;
}

type BucketArchives = Record<BucketDef['name'], Map<string, TerminalStatus>>;

async function collectBucketArchives(parentStateFile: string): Promise<BucketArchives> {
  const out = {} as BucketArchives;
  for (const b of BUCKETS) {
    out[b.name] = await scanBucket(b, parentStateFile);
  }
  return out;
}

async function scanBucket(
  bucket: BucketDef,
  parentStateFile: string,
): Promise<Map<string, TerminalStatus>> {
  const map = new Map<string, TerminalStatus>();
  const dir = path.join('.wheel', 'history', bucket.name);
  let entries: string[];
  try { entries = await fs.readdir(dir); } catch { return map; }
  for (const entry of entries) {
    if (!entry.endsWith('.json')) continue;
    try {
      const archived = JSON.parse(await fs.readFile(path.join(dir, entry), 'utf-8')) as {
        parent_workflow?: string | null;
        alternate_agent_id?: string;
      };
      if (
        archived.parent_workflow === parentStateFile
        && archived.alternate_agent_id
        && !map.has(archived.alternate_agent_id)
      ) {
        map.set(archived.alternate_agent_id, bucket.status);
      }
    } catch { /* unreadable — skip */ }
  }
  return map;
}

function classifyRunningSlots(
  runningSlots: Array<[string, { agent_id?: string; status?: string } | undefined]>,
  liveAgentIds: ReadonlySet<string>,
  bucketArchives: BucketArchives,
  stuckAgentIds: ReadonlySet<string>,
): { resolutions: Resolution[]; stillRunning: number } {
  const resolutions: Resolution[] = [];
  let stillRunning = 0;
  for (const [name, slot] of runningSlots) {
    const aid = slot?.agent_id ?? '';
    const slotStatus = slot?.status ?? 'pending';
    if (aid && stuckAgentIds.has(aid)) {
      resolutions.push({ name, newStatus: 'failed', failureReason: 'stuck_worker' });
      continue;
    }
    if (aid && liveAgentIds.has(aid)) { stillRunning++; continue; }
    const resolved =
      bucketArchives.success.get(aid)
      ?? bucketArchives.failure.get(aid)
      ?? bucketArchives.stopped.get(aid)
      ?? null;
    if (resolved !== null) {
      resolutions.push({ name, newStatus: resolved });
      continue;
    }
    // Slot has no live child, no archive. Distinguish:
    //   - status='running' → child existed and disappeared; mark failed
    //   - status='pending' → child hasn't started yet; treat as still running
    //     (don't pre-emptively fail before the orchestrator's Agent call
    //     even fires). This is critical for the very first poll right
    //     after wait-all begins polling but before the orchestrator
    //     issues the spawn — pre-fix, those pending slots got marked
    //     'state-file-disappeared' on the first tick, advancing wait-all
    //     before any teammate could run.
    if (slotStatus === 'pending') {
      stillRunning++;
    } else {
      resolutions.push({ name, newStatus: 'failed', failureReason: 'state-file-disappeared' });
    }
  }
  return { resolutions, stillRunning };
}

async function applyResolutions(
  parentStateFile: string,
  teamRef: string,
  resolutions: Resolution[],
): Promise<number> {
  let reconciled = 0;
  await withLockBlocking(parentStateFile, async () => {
    const parent = await stateRead(parentStateFile);
    const team = parent.teams?.[teamRef];
    if (!team) return;
    const teammates = team.teammates ?? {};
    const now = new Date().toISOString();
    for (const r of resolutions) {
      const slot = teammates[r.name];
      if (!slot) continue;
      if (slot.status === 'completed' || slot.status === 'failed') continue;
      slot.status = r.newStatus;
      slot.completed_at = now;
      if (r.failureReason) slot.failure_reason = r.failureReason;
      reconciled++;
    }
    parent.updated_at = now;
    await stateWrite(parentStateFile, parent);
  });
  return reconciled;
}
