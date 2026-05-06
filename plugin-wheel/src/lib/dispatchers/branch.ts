// dispatchBranch — handles `type: "branch"` steps.
//
// Evaluates `step.condition` via `eval`; routes to `if_zero` or
// `if_nonzero` target step. Marks the off-branch step as 'skipped' so
// cascadeNext walks past it. Falls through to next step if target is
// END or absent.
//
// FR-024.

import type { WorkflowStep } from '../../shared/state.js';
import { stateRead, stateWrite } from '../../shared/state.js';
import { stateSetStepStatus } from '../state.js';
import { wheelLog } from '../log.js';
import { exec } from 'child_process';
import { promisify } from 'util';
import type { HookInput, HookOutput, HookType } from '../dispatch-types.js';

interface BranchStepFields {
  condition?: string;
  if_zero?: string;
  if_nonzero?: string;
}

const execAsync = promisify(exec);

export async function dispatchBranch(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
  depth: number = 0,
): Promise<HookOutput> {
  const stateModule = await import('../state.js');
  const state = await stateRead(stateFile);
  const dispatchModule = await import('../dispatch.js');
  const cascadeNext = dispatchModule.cascadeNext;

  await stateSetStepStatus(stateFile, stepIndex, 'working');

  const bf = step as WorkflowStep & BranchStepFields;
  const condition = bf.condition;
  if (!condition) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    const fresh = await stateRead(stateFile);
    await stateWrite(stateFile, { ...fresh, status: 'failed' as const });
    await wheelLog('dispatch_cascade_halt', {
      step_id: step.id, step_type: step.type,
      reason: 'failed', state_file: stateFile,
    });
    return { decision: 'approve' };
  }

  let condExit = 0;
  try {
    await execAsync(`eval "${condition}"`);
  } catch (e: any) {
    condExit = e.code ?? 1;
  }

  const targetId = condExit === 0 ? bf.if_zero : bf.if_nonzero;

  if (!targetId || targetId === 'END') {
    await stateSetStepStatus(stateFile, stepIndex, 'done');
    // parity: shell dispatch.sh — branch fall-through respects skipped + next field.
    const wfMod = await import('../workflow.js');
    const wfDef = state.workflow_definition;
    let fallNext = stepIndex + 1;
    if (wfDef) {
      const rawNext = wfMod.resolveNextIndex(step, stepIndex, wfDef);
      fallNext = await wfMod.advancePastSkipped(stateFile, rawNext, wfDef);
    }
    return cascadeNext(hookType, hookInput, stateFile, fallNext, depth);
  }

  const targetIndex = state.steps.findIndex((s: any) => s.id === targetId);
  if (targetIndex === -1) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    const fresh = await stateRead(stateFile);
    await stateWrite(stateFile, { ...fresh, status: 'failed' as const });
    await wheelLog('dispatch_cascade_halt', {
      step_id: step.id, step_type: step.type,
      reason: 'failed', state_file: stateFile,
    });
    return { decision: 'approve' };
  }

  await stateSetStepStatus(stateFile, stepIndex, 'done');

  // Mark the off-branch step as 'skipped' so cascadeNext walks past it.
  const otherTargetId = condExit === 0 ? bf.if_nonzero : bf.if_zero;
  if (otherTargetId) {
    const otherIndex = state.steps.findIndex((s: any) => s.id === otherTargetId);
    if (otherIndex !== -1) {
      await stateSetStepStatus(stateFile, otherIndex, 'skipped');
    }
  }

  await stateModule.stateAppendCommandLog(stateFile, stepIndex, {
    command: `branch: condition='${condition}' exit=${condExit} target=${targetId}`,
    exit_code: condExit,
    timestamp: new Date().toISOString(),
  });

  // FR-004 — cascade to branch target. cascadeNext sets cursor to targetIndex.
  return cascadeNext(hookType, hookInput, stateFile, targetIndex, depth);
}
