// dispatchApproval — handles `type: "approval"` steps.
//
// Stop hook: pending → working + emit "APPROVAL GATE" block, set awaiting_user_input.
// teammate_idle hook: if .approval === 'approved' → done + cursor advance.
//   Otherwise re-emit "WAITING FOR APPROVAL".
// All other hooks: approve.
//
// parity: shell dispatch.sh:1300.

import type { WorkflowStep } from '../../shared/state.js';
import { stateRead } from '../../shared/state.js';
import { stateSetStepStatus, stateSetAwaitingUserInput } from '../state.js';
import type { HookInput, HookOutput, HookType } from '../dispatch-types.js';

export async function dispatchApproval(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
): Promise<HookOutput> {
  const stateModule = await import('../state.js');
  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';
  const message = (step.message as string | undefined) ?? 'Approval required to continue.';

  if (hookType === 'stop') {
    if (stepStatus === 'pending') {
      await stateSetStepStatus(stateFile, stepIndex, 'working');
    }
    await stateSetAwaitingUserInput(stateFile, stepIndex, message);
    return {
      decision: 'block',
      additionalContext: `APPROVAL GATE: ${message} — Waiting for approval via TeammateIdle.`,
    };
  }

  if (hookType === 'teammate_idle') {
    const approval = (hookInput.approval as string | undefined) ?? '';
    if (approval === 'approved') {
      await stateSetStepStatus(stateFile, stepIndex, 'done');
      // parity: shell dispatch.sh:1328 — advance cursor.
      await stateModule.stateSetCursor(stateFile, stepIndex + 1);
      return { decision: 'approve' };
    }
    return {
      decision: 'block',
      additionalContext: `WAITING FOR APPROVAL: ${message}`,
    };
  }

  return { decision: 'approve' };
}
