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
import { stateRead, listLiveStateFiles } from '../../shared/state.js';
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
      `${snapshot}\n\nNot all teammates are terminal yet. End your turn so the wheel hooks can fire on the next teammate idle/stop event. Do NOT wheel-stop unless this exact progress snapshot has been unchanged for 5+ consecutive turns AND there are no live child workflow state changes — silence between turns is normal as sub-agents work.`,
  };
}

async function _teammateIdle(
  stateFile: string,
  teamRef: string,
  hookInput: HookInput,
): Promise<HookOutput> {
  const idleAgentId = String(hookInput.agent_id ?? '');
  const idleName = String(hookInput.teammate_name ?? '');
  const idleTeamName = String(hookInput.team_name ?? '');
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
  let childState: WheelState | null = null;
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
