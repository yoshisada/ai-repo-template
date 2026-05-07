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

import type { WorkflowStep, WheelState } from '../../shared/state.js';
import { stateRead, stateWrite, listLiveStateFiles } from '../../shared/state.js';
import { stateSetStepStatus } from '../state.js';
import { wheelLog } from '../log.js';
import { runPollingBackstop } from '../dispatch-team-polling.js';
import type { HookInput, HookOutput, HookType } from '../dispatch-types.js';

// Re-export polling backstop so callers (callers using the dispatcher
// module path) keep working after the extraction. New code should import
// from `../dispatch-team-polling.js` directly.
export { runPollingBackstop };

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
    const done = await _recheckAndCompleteIfDone(stateFile, stepIndex, teamRef, step as { output?: string; collect_to?: string });
    if (done) return { decision: 'approve' };
    return _stopBlock(stateFile, teamRef);
  }

  // FR-003 + FR-004: post_tool_use branch.
  if (hookType === 'post_tool_use') {
    if (stepStatus !== 'working' && stepStatus !== 'pending') {
      return { decision: 'approve' };
    }
    await runPollingBackstop(stateFile, teamRef);
    await _recheckAndCompleteIfDone(stateFile, stepIndex, teamRef, step as { output?: string; collect_to?: string });
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
  // Fix B: 0 teammates is only a legitimate "done" state when
  // dispatchTeammate stamped `spawn_finalized` (i.e. the spawn step
  // ran and either dispatched N≥1 slots or legitimately resolved
  // loop_from to []). Without that flag, 0 teammates means the team
  // step was bypassed by the orchestrator — team-wait MUST hang so
  // the wheel-stop / polling backstop / failure paths can take over
  // instead of producing a false PASS archive.
  if (names.length === 0) {
    if (team.spawn_finalized !== true) return false;
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
    const wfDef = freshState.workflow_definition;
    const wfStepsArr: ReadonlyArray<{ type: string; team?: string; workflow?: string }> =
      wfDef?.steps ?? freshState.steps;
    const lastTeammateStep = [...wfStepsArr]
      .reverse()
      .find((s) => s.type === 'teammate' && (s.team ?? '') === teamRef);
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
      `${snapshot}\n\nNot all teammates are terminal yet. **End your turn now** so the wheel hooks can fire on the next teammate idle/stop event. Do NOT take any action this turn — no tool calls, no investigation, no \`cat .wheel/.next-instruction.md\` re-reads, no re-spawning workers. Silence between turns is normal while sub-agents work; the wheel coordinates progress on hook events, NOT on orchestrator turns. If you re-read or retry, you waste budget without advancing the workflow. Only take action when the progress snapshot above CHANGES on a future turn. (Wheel-stop is reserved for the snapshot remaining unchanged for 5+ consecutive turns AND zero live child workflow state changes — that's the genuine stuck signal.)`,
  };
}

async function _teammateIdle(
  stateFile: string,
  teamRef: string,
  hookInput: HookInput,
): Promise<HookOutput> {
  // Empirical hookInput shape from a real spawned-teammate's TeammateIdle
  // (probe-team / 2026-05-06):
  //   session_id     "<sub-agent's-own-session-id>"
  //   agent_id       null   ← Claude Code never populates this
  //   teammate_name  "<short>"
  //   team_name      "<team-name>"
  //   agent_type     "general-purpose"
  //
  // The sub-agent's child workflow state file has `owner_session_id`
  // equal to that same session_id (it was created by the spawn's
  // activate.sh under the sub-agent's session). So `session_id` is the
  // ONLY canonical link from parent to child; agent_id-based matching
  // is moot because agent_id is always null.
  const idleSessionId = String(hookInput.session_id ?? '');
  const idleAgentId = String(hookInput.agent_id ?? '');
  const idleName = String(hookInput.teammate_name ?? '');
  const idleTeamName = String(hookInput.team_name ?? '');
  await wheelLog('dispatch_teammate_idle_enter', {
    session_id: idleSessionId, agent_id: idleAgentId, teammate_name: idleName,
    hook_input_keys: Object.keys(hookInput ?? {}),
    state_file: stateFile,
  });
  if (!idleSessionId && !idleAgentId && !idleName) {
    await wheelLog('dispatch_teammate_idle_skip', { reason: 'no_session_or_agent_or_name' });
    return { decision: 'approve' };
  }
  // Slot identity computed from teammate_name + team_name (parent owns
  // both via the Agent call's structured fields). This is what
  // dispatchTeammate stamps on slot.agent_id at registration.
  const slotAgentId = idleName && idleTeamName ? `${idleName}@${idleTeamName}` : '';

  // Locate the child state file. Match priority:
  //   1. owner_session_id === hookInput.session_id  ← canonical bridge
  //   2. alternate_agent_id matches a known candidate (legacy --as path)
  //   3. owner_agent_id matches (legacy)
  const fallbackCandidates = [idleAgentId, slotAgentId, idleName].filter(s => s);
  let childStateFile: string | null = null;
  let childState: WheelState | null = null;
  for (const { path: candidate } of await listLiveStateFiles()) {
    if (candidate === stateFile) continue; // skip parent
    try {
      const cs = await stateRead(candidate);
      const childOwnerSession = cs.owner_session_id ?? '';
      const childAlt = cs.alternate_agent_id ?? '';
      const childOwnerAgent = cs.owner_agent_id ?? '';
      const sessionMatch = idleSessionId && childOwnerSession === idleSessionId;
      const altMatch = fallbackCandidates.some(e => childAlt === e);
      const agentMatch = fallbackCandidates.some(e => childOwnerAgent === e);
      if (sessionMatch || altMatch || agentMatch) {
        childStateFile = candidate;
        childState = cs;
        break;
      }
    } catch { /* skip */ }
  }

  if (!childStateFile || !childState) {
    await wheelLog('dispatch_teammate_idle_skip', {
      reason: 'no_child_state', idle_session: idleSessionId, idle_name: idleName,
    });
    await runPollingBackstop(stateFile, teamRef);
    return { decision: 'approve' };
  }

  // Backfill parent linkage on the child if it's missing (the orchestrator
  // dropped --as; activate.sh saw no alt_id; child was created without
  // parent_workflow / alternate_agent_id). At this point we know:
  //   - slotAgentId is the canonical alt id (from teammate_name + team_name)
  //   - stateFile is the parent's path
  // Stamping these unblocks archiveWorkflow's parent-update path on
  // child terminal, AND the polling backstop's bucket-archive lookup.
  if (slotAgentId) {
    const needsLink =
      !childState.alternate_agent_id || !childState.parent_workflow;
    if (needsLink) {
      try {
        const fresh = await stateRead(childStateFile);
        if (!fresh.alternate_agent_id) fresh.alternate_agent_id = slotAgentId;
        if (!fresh.parent_workflow) fresh.parent_workflow = stateFile;
        await stateWrite(childStateFile, fresh);
        childState = fresh;
        await wheelLog('dispatch_teammate_idle_backfill_link', {
          child_state_file: childStateFile,
          alternate_agent_id: slotAgentId,
          parent_state_file: stateFile,
        });
      } catch { /* race with archive — ignore */ }
    }
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
