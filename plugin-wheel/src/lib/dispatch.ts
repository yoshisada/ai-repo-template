// dispatch.ts — thin router for step dispatchers.
//
// Each step type has its own implementation file under `dispatchers/`.
// dispatch.ts owns:
//   - `dispatchStep` — the public router that maps step.type → dispatcher
//   - `cascadeNext` — the shared cascade-walker (used by command/loop/branch/team-create/team-delete)
//   - `_chainParentAfterArchive` — parent-resume helper (called from agent terminal)
//
// FR-001/FR-002/FR-003/FR-004/FR-006/FR-007/FR-008/FR-009 (step dispatch + cascade).

import type { WorkflowStep } from '../shared/state.js';
import { stateRead } from '../shared/state.js';
import { wheelLog } from './log.js';
import {
  isAutoExecutable,
  CASCADE_DEPTH_CAP,
  type HookType,
  type HookInput,
  type HookOutput,
} from './dispatch-types.js';

// Per-step-type dispatchers (extracted into dispatchers/* for SRP +
// line-cap hygiene per constitution Article VI).
import { dispatchApproval } from './dispatchers/approval.js';
import { dispatchParallel } from './dispatchers/parallel.js';
import { dispatchCommand } from './dispatchers/command.js';
import { dispatchTeamCreate } from './dispatchers/team-create.js';
import { dispatchTeamDelete } from './dispatchers/team-delete.js';
import { dispatchBranch } from './dispatchers/branch.js';
import { dispatchLoop } from './dispatchers/loop.js';
import { dispatchAgent, _hydrateAgentStep as hydratedExport } from './dispatchers/agent.js';
import { dispatchWorkflow } from './dispatchers/workflow.js';
import { dispatchTeammate } from './dispatchers/teammate.js';
import { dispatchTeamWait } from './dispatchers/team-wait.js';

// Re-export for callers that imported types or helpers from dispatch.ts
// directly (engine.ts, post-tool-use.ts, tests).
export const _hydrateAgentStep = hydratedExport;
export type { HookType, HookInput, HookOutput } from './dispatch-types.js';
export { isAutoExecutable, CASCADE_DEPTH_CAP } from './dispatch-types.js';

/**
 * parity: shell dispatch.sh:144 — _chain_parent_after_archive.
 *
 * When a child workflow's terminal step triggers archive, the parent's
 * cursor must advance and the parent's next step must be dispatched in
 * the SAME hook fire (otherwise the parent stalls until an unrelated
 * hook event fires).
 *
 * parentStateFile MUST be a snapshot captured BEFORE archive — once the
 * child archives, its state file is gone and we can no longer read its
 * parent_workflow field.
 *
 * Always dispatches with hook_type='stop' so an agent step transitions
 * pending→working and emits its instruction block. Other hook types
 * (post_tool_use, teammate_idle) skip that transition and orphan the
 * parent.
 */
export async function _chainParentAfterArchive(
  parentStateFile: string | null,
  _origHookType: HookType,
  hookInput: HookInput,
): Promise<HookOutput> {
  if (!parentStateFile) return { decision: 'approve' };
  try {
    const { promises: fs } = await import('fs');
    await fs.access(parentStateFile);
  } catch {
    return { decision: 'approve' };
  }

  let parentState;
  try {
    parentState = await stateRead(parentStateFile);
  } catch {
    return { decision: 'approve' };
  }

  const parentWfFile = parentState.workflow_file;
  if (!parentWfFile) return { decision: 'approve' };

  let parentWf: any = (parentState as any).workflow_definition;
  if (!parentWf) {
    try {
      const wfMod = await import('./workflow.js');
      parentWf = await wfMod.workflowLoad(parentWfFile);
    } catch {
      return { decision: 'approve' };
    }
  }

  const parentCursor = parentState.cursor ?? 0;
  const parentTotal = parentWf?.steps?.length ?? 0;
  if (parentCursor >= parentTotal) return { decision: 'approve' };

  const parentStepJson = parentWf.steps[parentCursor];
  // Always dispatch with 'stop' hook semantics so agent steps emit their block.
  return dispatchStep(parentStepJson as WorkflowStep, 'stop', hookInput, parentStateFile, parentCursor, 0);
}

// FR-007: dispatchStep(step, hookType, hookInput, stateFile, stepIndex, depth?)
// FR-006: depth tracks cascade recursion; external callers omit (defaults 0).
export async function dispatchStep(
  step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
  depth: number = 0
): Promise<HookOutput> {
  switch (step.type) {
    case 'agent':
      return dispatchAgent(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'command':
      // FR-002 — cascade-emitting dispatcher; depth threaded.
      return dispatchCommand(step, _hookType, _hookInput, stateFile, stepIndex, depth);
    case 'workflow':
      return dispatchWorkflow(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'team-create':
      return dispatchTeamCreate(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'teammate':
      return dispatchTeammate(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'team-wait':
      return dispatchTeamWait(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'team-delete':
      return dispatchTeamDelete(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'branch':
      // FR-004 — cascade-emitting dispatcher; depth threaded.
      return dispatchBranch(step, _hookType, _hookInput, stateFile, stepIndex, depth);
    case 'loop':
      // FR-003 — cascade-emitting dispatcher; depth threaded.
      return dispatchLoop(step, _hookType, _hookInput, stateFile, stepIndex, depth);
    case 'parallel':
      return dispatchParallel(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'approval':
      return dispatchApproval(step, _hookType, _hookInput, stateFile, stepIndex);
    default:
      return { decision: 'approve' };
  }
}

/**
 * FR-002/FR-003/FR-004/FR-006/FR-008/FR-009 — shared cascade tail.
 * Module-private; reachable only from cascade-emitting dispatchers.
 *
 * Contract:
 *   1. Read fresh state.
 *   2. nextIndex >= steps.length → advance cursor, log end_of_workflow halt.
 *   3. Advance cursor to nextIndex FIRST (idempotency: a mid-dispatch crash
 *      leaves state at the right cursor, next hook fire retries the right step).
 *   4. depth >= cap → log depth_cap halt, return.
 *   5. !isAutoExecutable(nextStep) → log blocking_step halt, return.
 *   6. Log dispatch_cascade hop, recurse with depth+1.
 */
export async function cascadeNext(
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  nextIndex: number,
  depth: number
): Promise<HookOutput> {
  const stateModule = await import('./state.js');
  let state;
  try {
    state = await stateRead(stateFile);
  } catch {
    // State file gone (race with archive) — bail.
    return { decision: 'approve' };
  }

  const fromCursor = state.cursor;
  const fromStep: any = state.steps[fromCursor] ?? {};
  const fromStepId = fromStep.id ?? '';
  const fromStepType = fromStep.type ?? '';

  // FR-009 — end-of-workflow halt.
  if (nextIndex >= state.steps.length) {
    await stateModule.stateSetCursor(stateFile, nextIndex);
    await wheelLog('cursor_advance', {
      from_cursor: fromCursor,
      to_cursor: nextIndex,
      state_file: stateFile,
    });
    await wheelLog('dispatch_cascade_halt', {
      step_id: fromStepId,
      step_type: fromStepType,
      reason: 'end_of_workflow',
      state_file: stateFile,
    });
    return { decision: 'approve' };
  }

  // FR-004 — walk past 'skipped' steps (e.g., off-target branch arms)
  // so cascade doesn't re-execute them. Mirrors maybeAdvanceParentTeamWaitCursor.
  let resolvedIndex = nextIndex;
  while (
    resolvedIndex < state.steps.length &&
    state.steps[resolvedIndex]?.status === 'skipped'
  ) {
    resolvedIndex++;
  }
  if (resolvedIndex >= state.steps.length) {
    await stateModule.stateSetCursor(stateFile, resolvedIndex);
    await wheelLog('cursor_advance', {
      from_cursor: fromCursor, to_cursor: resolvedIndex, state_file: stateFile,
    });
    await wheelLog('dispatch_cascade_halt', {
      step_id: fromStepId, step_type: fromStepType,
      reason: 'end_of_workflow', state_file: stateFile,
    });
    return { decision: 'approve' };
  }

  // Prefer workflow_definition.steps (full WorkflowStep with command,
  // condition, substep, etc.) over state.steps (projection that strips
  // command/condition fields). dispatchCommand short-circuits when
  // step.command is missing — without this, cascade silently no-ops on
  // every hop.
  const wfDef = state.workflow_definition;
  const wfSteps: any[] = wfDef?.steps ?? state.steps;
  const nextStep: any = wfSteps[resolvedIndex] ?? state.steps[resolvedIndex];

  // FR-008 — advance cursor BEFORE recursing (idempotency contract).
  await stateModule.stateSetCursor(stateFile, resolvedIndex);
  await wheelLog('cursor_advance', {
    from_cursor: fromCursor,
    to_cursor: resolvedIndex,
    state_file: stateFile,
  });

  // FR-006 — depth cap halt.
  if (depth >= CASCADE_DEPTH_CAP) {
    await wheelLog('dispatch_cascade_halt', {
      step_id: nextStep.id ?? '',
      step_type: nextStep.type ?? '',
      reason: 'depth_cap',
      state_file: stateFile,
    });
    return { decision: 'approve' };
  }

  // FR-001 — single classifier; FR-009 — blocking-step halt log.
  if (!isAutoExecutable(nextStep)) {
    await wheelLog('dispatch_cascade_halt', {
      step_id: nextStep.id ?? '',
      step_type: nextStep.type ?? '',
      reason: 'blocking_step',
      state_file: stateFile,
    });
    return { decision: 'approve' };
  }

  // FR-009 — cascade hop log.
  await wheelLog('dispatch_cascade', {
    from_step_id: fromStepId,
    from_step_type: fromStepType,
    to_step_id: nextStep.id ?? '',
    to_step_type: nextStep.type ?? '',
    hook_type: hookType,
    state_file: stateFile,
  });

  // FR-007 — pass hookType through unchanged. FR-006 — depth + 1.
  return dispatchStep(nextStep as WorkflowStep, hookType, hookInput, stateFile, resolvedIndex, depth + 1);
}


