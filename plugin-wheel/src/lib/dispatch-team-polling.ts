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

  const runningSlots = Object.entries(team.teammates ?? {})
    .filter(([, slot]) => slot?.status === 'running');
  if (runningSlots.length === 0) {
    await wheelLog('wait_all_polling', {
      parent_state_file: parentStateFile, team_id: teamRef,
      reconciled_count: 0, still_running_count: 0,
    });
    return { reconciledCount: 0, stillRunningCount: 0 };
  }

  const liveAgentIds = await collectLiveAgentIds();
  const bucketArchives = await collectBucketArchives(parentStateFile);

  const { resolutions, stillRunning } =
    classifyRunningSlots(runningSlots, liveAgentIds, bucketArchives);

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
  runningSlots: Array<[string, { agent_id?: string } | undefined]>,
  liveAgentIds: ReadonlySet<string>,
  bucketArchives: BucketArchives,
): { resolutions: Resolution[]; stillRunning: number } {
  const resolutions: Resolution[] = [];
  let stillRunning = 0;
  for (const [name, slot] of runningSlots) {
    const aid = slot?.agent_id ?? '';
    if (aid && liveAgentIds.has(aid)) { stillRunning++; continue; }
    const resolved =
      bucketArchives.success.get(aid)
      ?? bucketArchives.failure.get(aid)
      ?? bucketArchives.stopped.get(aid)
      ?? null;
    if (resolved !== null) {
      resolutions.push({ name, newStatus: resolved });
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
