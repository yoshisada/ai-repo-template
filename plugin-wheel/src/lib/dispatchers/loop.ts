// dispatchLoop — handles `type: "loop"` steps.
//
// Per-iteration semantics:
//   1. If iteration >= max_iterations: exhausted →
//      - on_exhaustion='continue' → done + cascade
//      - else → failed + halt cascade
//   2. If `step.condition` evaluates to 0 (success): done + cascade.
//   3. Else: increment iteration, run substep:
//      - command substep → exec, then self-cascade for next iteration
//        (within the same hook fire — closes #199 Bug A).
//      - agent substep → block w/ instruction.
//
// FR-025 / #199 fixes (loop self-cascade, max_iterations source-of-truth).

import type { WorkflowStep } from '../../shared/state.js';
import { stateRead, stateWrite } from '../../shared/state.js';
import { stateSetStepStatus, stateAppendCommandLog } from '../state.js';
import { wheelLog } from '../log.js';
import { exec } from 'child_process';
import { promisify } from 'util';
import type { HookInput, HookOutput, HookType } from '../dispatch-types.js';

// Step-type-specific fields read from a `loop` step's JSON.
interface LoopStepFields {
  max_iterations?: number;
  on_exhaustion?: 'fail' | 'continue';
  condition?: string;
  substep?: { type: string; command?: string; instruction?: string };
}

const execAsync = promisify(exec);

export async function dispatchLoop(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
  depth: number = 0,
): Promise<HookOutput> {

  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';
  const dispatchModule = await import('../dispatch.js');
  const cascadeNext = dispatchModule.cascadeNext;

  if (stepStatus === 'pending') {
    await stateSetStepStatus(stateFile, stepIndex, 'working');
  }

  const lf = step as WorkflowStep & LoopStepFields;
  const maxIterations = lf.max_iterations ?? 10;
  const onExhaustion = lf.on_exhaustion ?? 'fail';
  const condition = lf.condition;
  const currentIteration = state.steps[stepIndex]?.loop_iteration ?? 0;

  if (currentIteration >= maxIterations) {
    await stateAppendCommandLog(stateFile, stepIndex, {
      command: `loop: exhausted after ${currentIteration} iterations`,
      exit_code: 1, timestamp: new Date().toISOString(),
    });
    if (onExhaustion === 'continue') {
      await stateSetStepStatus(stateFile, stepIndex, 'done');
      return cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, depth);
    }
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    const fresh = await stateRead(stateFile);
    await stateWrite(stateFile, { ...fresh, status: 'failed' as const });
    await wheelLog('dispatch_cascade_halt', {
      step_id: step.id, step_type: step.type,
      reason: 'failed', state_file: stateFile,
    });
    return { decision: 'approve' };
  }

  if (condition) {
    let condExit = 0;
    try {
      await execAsync(`eval "${condition}"`);
    } catch (e: any) {
      condExit = e.code ?? 1;
    }
    if (condExit === 0) {
      await stateAppendCommandLog(stateFile, stepIndex, {
        command: `loop: condition met at iteration ${currentIteration}`,
        exit_code: 0, timestamp: new Date().toISOString(),
      });
      await stateSetStepStatus(stateFile, stepIndex, 'done');
      return cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, depth);
    }
  }

  // Increment iteration counter
  const newState = { ...state };
  if (!newState.steps[stepIndex]) {
    newState.steps[stepIndex] = {
      id: '', type: '', status: 'pending',
      started_at: null, completed_at: null, output: null,
      command_log: [], agents: {}, loop_iteration: 0,
      awaiting_user_input: false,
      awaiting_user_input_since: null,
      awaiting_user_input_reason: null,
      resolved_inputs: null, contract_emitted: false,
    };
  }
  newState.steps[stepIndex].loop_iteration = currentIteration + 1;
  await stateWrite(stateFile, newState);

  const substep = lf.substep;
  if (!substep) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    return { decision: 'approve' };
  }

  if (substep.type === 'command') {
    const wfModule = await import('../workflow.js');
    const wfPluginDir = await wfModule.deriveWorkflowPluginDir(stateFile);
    const cmdEnv = wfPluginDir
      ? { ...process.env, WORKFLOW_PLUGIN_DIR: wfPluginDir }
      : { ...process.env };
    if (substep.command) {
      try {
        await execAsync(substep.command, { timeout: 300000, env: cmdEnv });
      } catch {
        // Continue loop even on command failure
      }
    }

    const reState = await stateRead(stateFile);
    const reIteration = reState.steps[stepIndex]?.loop_iteration ?? 0;
    // parity: shell dispatch.sh:1440 — max_iterations is per-workflow-def.
    // Bug B fix (#199): read from step (workflow def), NOT state.steps[i].
    const reMaxIter = lf.max_iterations ?? 10;
    if (reIteration >= reMaxIter) {
      await stateSetStepStatus(stateFile, stepIndex, 'done');
      return cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, depth);
    }
    // parity: shell dispatch.sh:1555 — self-cascade between iterations
    // within one hook fire (closes #199 Bug A).
    return dispatchLoop(step, hookType, hookInput, stateFile, stepIndex, depth);
  }
  if (substep.type === 'agent') {
    const instruction = substep.instruction ?? '';
    return {
      decision: 'block',
      additionalContext: `Loop iteration ${currentIteration + 1}/${maxIterations}: ${instruction}`,
    };
  }

  return { decision: 'approve' };
}
