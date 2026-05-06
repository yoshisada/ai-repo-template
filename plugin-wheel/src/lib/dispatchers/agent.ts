// dispatchAgent — handles `type: "agent"` steps.
//
// Stop (pending): unlink stale output file, transition working,
//   emit context-block instructions for the agent to do its work.
// Stop (working): check `step.output` file; if present → mark done,
//   capture output, advance cursor (respecting `skipped` + `next` field),
//   honor `terminal: true` to set state.status='completed', advance parent
//   cursor on terminal-with-parent.
// Post-tool-use: working → approve. Pending → working + emit context.
//
// FR-003.

import type { WorkflowStep, WheelState, WorkflowDefinition } from '../../shared/state.js';
import { stateRead, stateWrite } from '../../shared/state.js';
import { stateSetStepStatus } from '../state.js';
import { contextBuild } from '../context.js';
import { resolveInputs } from '../resolve_inputs.js';
import type { HookInput, HookOutput, HookType } from '../dispatch-types.js';

export async function dispatchAgent(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
): Promise<HookOutput> {
  if (hookType !== 'stop' && hookType !== 'post_tool_use') {
    return { decision: 'approve' };
  }

  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';

  if (hookType === 'stop') {
    if (stepStatus === 'pending') {
      // parity: shell dispatch.sh:594–602 — delete stale output file from
      // prior run before pending→working transition. Otherwise a leftover
      // file would auto-complete the step before the agent writes anything.
      const outputKey = step.output as string | undefined;
      if (outputKey) {
        try {
          const { unlink } = await import('fs/promises');
          await unlink(outputKey);
        } catch { /* file absent — fine */ }
      }
      await stateSetStepStatus(stateFile, stepIndex, 'working');
      const resolvedInputs = step.inputs
        ? resolveInputs(step.inputs, {} as WheelState, {} as WorkflowDefinition, {})
        : {};
      const context = await contextBuild(step, {} as WheelState, resolvedInputs);
      return { decision: 'block', additionalContext: context };
    }
    if (stepStatus === 'working') {
      // Output file exists → agent completed.
      const outputKey = step.output as string | undefined;
      if (outputKey) {
        try {
          const { access } = await import('fs/promises');
          await access(outputKey);
          const stateModule = await import('../state.js');
          const wfModule = await import('../workflow.js');
          const contextModule = await import('../context.js');
          // parity: shell dispatch.sh:664 — capture output to state.steps[i].output.
          await contextModule.contextCaptureOutput(stateFile, stepIndex, outputKey);
          await stateSetStepStatus(stateFile, stepIndex, 'done');
          // parity: shell dispatch.sh:667 — clear awaiting_user_input on advance.
          await stateModule.stateClearAwaitingUserInput(stateFile, stepIndex);
          // parity: shell dispatch.sh:676–680 — cursor advance respects skipped + next.
          const stateNow = await stateRead(stateFile);
          const wfDef = stateNow.workflow_definition;
          let newCursor = stepIndex + 1;
          if (wfDef) {
            const rawNext = wfModule.resolveNextIndex(step, stepIndex, wfDef);
            newCursor = await wfModule.advancePastSkipped(stateFile, rawNext, wfDef);
          }
          await stateModule.stateSetCursor(stateFile, newCursor);
          // parity: shell dispatch.sh:226 — terminal:true → set state.status='completed'.
          if (step.terminal === true) {
            const fresh = await stateRead(stateFile);
            await stateWrite(stateFile, { ...fresh, status: 'completed' as const });
            // parity: shell dispatch.sh:144 — advance parent cursor when child terminates.
            const parentSnap = stateNow.parent_workflow ?? null;
            const dispatchModule = await import('../dispatch.js');
            await dispatchModule._chainParentAfterArchive(parentSnap, hookType, hookInput);
          }
          return { decision: 'approve' };
        } catch {
          // Output file not yet present, still waiting
        }
      }
      return {
        decision: 'block',
        additionalContext: 'Still waiting for agent step to complete...',
      };
    }
  }

  if (hookType === 'post_tool_use') {
    if (stepStatus === 'working') return { decision: 'approve' };
    await stateSetStepStatus(stateFile, stepIndex, 'working');
    const resolvedInputs = step.inputs
      ? resolveInputs(step.inputs, {} as WheelState, {} as WorkflowDefinition, {})
      : {};
    const context = await contextBuild(step, {} as WheelState, resolvedInputs);
    return { decision: 'approve', additionalContext: context };
  }

  return { decision: 'approve' };
}

// FR-G3-1/FR-G3-4: _hydrateAgentStep — resolves step inputs against state + workflow + registry
export async function _hydrateAgentStep(
  step: WorkflowStep,
  state: WheelState,
  workflow: any,
  _stateFile: string,
  _stepIndex: number,
): Promise<string> {
  if (!step.inputs) return '{}';
  try {
    const resolved = resolveInputs(step.inputs, state, workflow, {});
    return JSON.stringify(resolved);
  } catch (err) {
    return JSON.stringify({ error: String(err) });
  }
}
