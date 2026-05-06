// dispatchTeamWait — handles `type: "team-wait"` steps.
//
// Three branches by hook type:
//   - stop: pending → working transition + re-check; if not done, emit a
//     progress-snapshot block (with `do NOT wheel-stop` hint) so the
//     orchestrator has real activity evidence instead of silent approve.
//     Re-emits the spawn block when slots are still pending.
//   - post_tool_use: run polling backstop, then re-check.
//   - teammate_idle: find the idle teammate's child state file; either
//     advance an auto-executable step (command/loop/branch) directly OR
//     emit a SendMessage wake block for an agent step.
//
// All the heavy lifting (progress snapshot, wake block, child-step
// advancement, polling backstop) is delegated to dispatch-team.ts helpers.
//
// FR-003 / FR-004 / FR-005 (wheel-wait-all-redesign).

import type { WorkflowStep } from '../../shared/state.js';
import { stateRead, stateWrite, listLiveStateFiles } from '../../shared/state.js';
import {
  stateSetStepStatus, stateList,
} from '../state.js';
import { wheelLog } from '../log.js';
import type { HookInput, HookOutput, HookType } from '../dispatch-types.js';

export async function dispatchTeamWait(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
): Promise<HookOutput> {
  const stepId = step.id;
  const teamRef = (step as { team?: string }).team ?? stepId;

  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';

  // FR-003: stop branch.
  if (hookType === 'stop') {
    if (stepStatus === 'pending') {
      await stateSetStepStatus(stateFile, stepIndex, 'working');
    }
    const done = await _recheckAndCompleteIfDone(stateFile, stepIndex, teamRef, step as any);
    if (done) return { decision: 'approve' };
    return _stopBlock(stateFile, teamRef);
  }

  // FR-003 + FR-004: post_tool_use branch.
  if (hookType === 'post_tool_use') {
    if (stepStatus !== 'working' && stepStatus !== 'pending') {
      return { decision: 'approve' };
    }
    await runPollingBackstop(stateFile, teamRef);
    await _recheckAndCompleteIfDone(stateFile, stepIndex, teamRef, step as any);
    return { decision: 'approve' };
  }

  // teammate_idle branch.
  if (hookType === 'teammate_idle') {
    if (stepStatus !== 'working' && stepStatus !== 'pending') {
      return { decision: 'approve' };
    }
    return _teammateIdle(stateFile, teamRef, hookInput);
  }

  return { decision: 'approve' };
}

// =============================================================================
// Internal helpers — kept in this file because they're part of the dispatcher.
// =============================================================================

/**
 * If all teammate slots are terminal (completed/failed), mark the wait
 * step done and run `_teamWaitComplete` to write summary.json. Otherwise
 * no-op. parity: shell dispatch.sh:2248.
 */
async function _recheckAndCompleteIfDone(
  stateFile: string,
  stepIndex: number,
  teamRef: string,
  step?: { output?: string; collect_to?: string },
): Promise<boolean> {
  const state = await stateRead(stateFile);
  const team = state.teams?.[teamRef];
  if (!team) return false;
  const teammates = team.teammates ?? {};
  const names = Object.keys(teammates);
  // 0 teammates → mark done immediately (matches dispatchTeammate's 0-items short-circuit).
  if (names.length === 0) {
    if (state.steps[stepIndex]?.status !== 'done') {
      await stateSetStepStatus(stateFile, stepIndex, 'done');
    }
    return true;
  }
  for (const name of names) {
    const status = teammates[name]?.status ?? 'pending';
    if (status !== 'completed' && status !== 'failed') return false;
  }
  if (step && state.steps[stepIndex]?.status !== 'done') {
    try {
      const teamModule = await import('../dispatch-team.js');
      await teamModule._teamWaitComplete(step, stateFile, stepIndex, teamRef);
    } catch { /* non-fatal; archive flow proceeds */ }
  }
  if (state.steps[stepIndex]?.status !== 'done') {
    await stateSetStepStatus(stateFile, stepIndex, 'done');
  }
  return true;
}

async function _stopBlock(stateFile: string, teamRef: string): Promise<HookOutput> {
  const teamModule = await import('../dispatch-team.js');
  const { snapshot, hasPendingSlots, totalSlots } = await teamModule._teamWaitProgressSnapshot(
    stateFile, teamRef,
  );
  // Re-emit spawn instructions when slots are pending (orchestrator never
  // acted on the original spawn block). Without this, wait-all spins
  // forever waiting for slot updates that can never happen.
  if (hasPendingSlots && totalSlots > 0) {
    const freshState = await stateRead(stateFile);
    const wfDef: any = (freshState as any).workflow_definition;
    const wfStepsArr: any[] = wfDef?.steps ?? freshState.steps;
    const lastTeammateStep = [...wfStepsArr]
      .reverse()
      .find((s: any) => s.type === 'teammate' && (s.team ?? '') === teamRef);
    const subWorkflow = lastTeammateStep?.workflow ?? '';
    if (subWorkflow) {
      const flushed = await teamModule._teammateFlushFromState(stateFile, teamRef, subWorkflow);
      if (flushed.instructions) {
        return {
          decision: 'block',
          additionalContext: `${snapshot}\n\n${flushed.instructions}`,
        };
      }
    }
  }
  return {
    decision: 'block',
    additionalContext:
      `${snapshot}\n\nNot all teammates are terminal yet. End your turn so the wheel hooks can fire on the next teammate idle/stop event. Do NOT wheel-stop unless this exact progress snapshot has been unchanged for 5+ consecutive turns AND there are no live child workflow state changes — silence between turns is normal as sub-agents work.`,
  };
}

async function _teammateIdle(
  stateFile: string,
  teamRef: string,
  hookInput: HookInput,
): Promise<HookOutput> {
  const idleAgentId = String((hookInput as any).agent_id ?? '');
  const idleName = String((hookInput as any).teammate_name ?? '');
  const idleTeamName = String((hookInput as any).team_name ?? '');
  await wheelLog('dispatch_teammate_idle_enter', {
    agent_id: idleAgentId, teammate_name: idleName,
    hook_input_keys: Object.keys(hookInput ?? {}),
    state_file: stateFile,
  });
  if (!idleAgentId && !idleName) {
    await wheelLog('dispatch_teammate_idle_skip', { reason: 'no_agent_id_or_name' });
    return { decision: 'approve' };
  }
  // Find child state file: harness gives short `teammate_name` + `team_name`;
  // the child's alternate_agent_id is constructed as `name@team`.
  const expectedAltCandidates = [
    idleAgentId, `${idleName}@${idleTeamName}`, idleName,
  ].filter(s => s);
  let childStateFile: string | null = null;
  let childState: any = null;
  for (const { path: candidate } of await listLiveStateFiles()) {
    try {
      const cs = await stateRead(candidate);
      const childAlt = cs.alternate_agent_id ?? '';
      const childOwner = cs.owner_agent_id ?? '';
      if (expectedAltCandidates.some(e => childAlt === e || childOwner === e)) {
        childStateFile = candidate;
        childState = cs;
        break;
      }
    } catch { /* skip */ }
  }

  if (!childStateFile || !childState) {
    await wheelLog('dispatch_teammate_idle_skip', {
      reason: 'no_child_state', idle_agent_id: idleAgentId, idle_name: idleName,
    });
    await runPollingBackstop(stateFile, teamRef);
    return { decision: 'approve' };
  }
  const teamModule = await import('../dispatch-team.js');
  // Auto-executable steps run inline (sub-agent's session is gone).
  const advanced = await teamModule._teamWaitAdvanceChildIfAuto(childStateFile, childState, hookInput);
  if (advanced) return { decision: 'approve' };
  // Else, if the child is at an agent step, build a wake-up block.
  const wake = await teamModule._teamWaitBuildWakeBlock(
    idleAgentId, idleName, idleTeamName, childStateFile, childState,
  );
  if (wake) return { decision: 'block', additionalContext: wake };
  return { decision: 'approve' };
}

/**
 * FR-004 (wheel-wait-all-redesign): polling backstop. For each teammate
 * currently `status='running'` in `parent.teams[teamRef].teammates`,
 * reconcile against live state files → history buckets → orphan default.
 * Single parent-flock write at the end. One `.wheel/` readdir + up to
 * three history-bucket scans per invocation regardless of teammate count.
 */
export async function runPollingBackstop(
  parentStateFile: string,
  teamRef: string,
): Promise<{ reconciledCount: number; stillRunningCount: number }> {
  const { withLockBlocking } = await import('../lock.js');
  const { promises: fs } = await import('fs');
  const path = (await import('path')).default;

  let preState: Awaited<ReturnType<typeof stateRead>>;
  try {
    preState = await stateRead(parentStateFile);
  } catch {
    return { reconciledCount: 0, stillRunningCount: 0 };
  }
  const team = preState.teams?.[teamRef];
  if (!team) {
    await wheelLog('wait_all_polling', {
      parent_state_file: parentStateFile, team_id: teamRef,
      reconciled_count: 0, still_running_count: 0,
      note: 'team_not_found',
    });
    return { reconciledCount: 0, stillRunningCount: 0 };
  }
  const teammates = team.teammates ?? {};
  const runningSlots = Object.entries(teammates).filter(([, slot]) => slot?.status === 'running');
  if (runningSlots.length === 0) {
    await wheelLog('wait_all_polling', {
      parent_state_file: parentStateFile, team_id: teamRef,
      reconciled_count: 0, still_running_count: 0,
    });
    return { reconciledCount: 0, stillRunningCount: 0 };
  }

  // Live alternate_agent_id set.
  const liveAgentIds = new Set<string>();
  try {
    const liveFiles = await stateList();
    for (const sf of liveFiles) {
      try {
        const ss = await stateRead(sf);
        const aid = (ss as { alternate_agent_id?: string }).alternate_agent_id;
        if (aid) liveAgentIds.add(aid);
      } catch { /* ignore */ }
    }
  } catch { /* .wheel may not exist */ }

  // Bucket → (alternate_agent_id → resolved status) map.
  const buckets: Array<{ name: 'success' | 'failure' | 'stopped'; status: 'completed' | 'failed' }> = [
    { name: 'success', status: 'completed' },
    { name: 'failure', status: 'failed' },
    { name: 'stopped', status: 'failed' },
  ];
  const bucketArchives: Record<string, Map<string, 'completed' | 'failed'>> = {};
  for (const b of buckets) {
    const dir = path.join('.wheel', 'history', b.name);
    const map = new Map<string, 'completed' | 'failed'>();
    try {
      const entries = await fs.readdir(dir);
      for (const entry of entries) {
        if (!entry.endsWith('.json')) continue;
        try {
          const archived = JSON.parse(await fs.readFile(path.join(dir, entry), 'utf-8')) as {
            parent_workflow?: string | null;
            alternate_agent_id?: string;
          };
          if (archived.parent_workflow === parentStateFile && archived.alternate_agent_id
              && !map.has(archived.alternate_agent_id)) {
            map.set(archived.alternate_agent_id, b.status);
          }
        } catch { /* skip unreadable */ }
      }
    } catch { /* bucket may not exist yet */ }
    bucketArchives[b.name] = map;
  }

  // Resolve each running teammate. Order MUST be live → history → orphan.
  type Resolution = { name: string; newStatus: 'completed' | 'failed'; failureReason?: string };
  const resolutions: Resolution[] = [];
  let stillRunning = 0;
  for (const [name, slot] of runningSlots) {
    const aid = slot?.agent_id ?? '';
    if (aid && liveAgentIds.has(aid)) {
      stillRunning++;
      continue;
    }
    let resolved: 'completed' | 'failed' | null = null;
    if (bucketArchives.success.has(aid)) resolved = bucketArchives.success.get(aid)!;
    else if (bucketArchives.failure.has(aid)) resolved = bucketArchives.failure.get(aid)!;
    else if (bucketArchives.stopped.has(aid)) resolved = bucketArchives.stopped.get(aid)!;

    if (resolved !== null) {
      resolutions.push({ name, newStatus: resolved });
    } else {
      resolutions.push({ name, newStatus: 'failed', failureReason: 'state-file-disappeared' });
    }
  }

  let reconciled = 0;
  if (resolutions.length > 0) {
    await withLockBlocking(parentStateFile, async () => {
      const parent = await stateRead(parentStateFile);
      const team2 = parent.teams?.[teamRef];
      if (!team2) return;
      const t2 = team2.teammates ?? {};
      const now = new Date().toISOString();
      for (const r of resolutions) {
        const slot = t2[r.name];
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
  }

  await wheelLog('wait_all_polling', {
    parent_state_file: parentStateFile, team_id: teamRef,
    reconciled_count: reconciled, still_running_count: stillRunning,
  });
  return { reconciledCount: reconciled, stillRunningCount: stillRunning };
}
