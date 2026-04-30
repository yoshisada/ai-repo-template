// FR-006/FR-003: Step dispatcher - routes to appropriate handler
import type { WorkflowStep, WheelState } from '../shared/state.js';
import { stateSetStepStatus, stateSetStepOutput, stateSetAwaitingUserInput } from './state.js';
import { contextBuild } from './context.js';
import { resolveInputs } from './resolve_inputs.js';
import { guardCheck } from './guard.js';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

export type HookType = 'post_tool_use' | 'stop' | 'teammate_idle' | 'subagent_start' | 'subagent_stop' | 'session_start';

export interface HookInput {
  tool_name?: string;
  tool_input?: Record<string, unknown>;
  tool_output?: Record<string, unknown>;
  teammate_id?: string;
  session_id?: string;
  agent_id?: string;
  [key: string]: unknown;
}

export interface HookOutput {
  decision?: 'approve' | 'block';
  additionalContext?: string;
  hookEventName?: string;
  [key: string]: unknown;
}

// FR-007: dispatchStep(step: WorkflowStep, hookType: HookType, hookInput: HookInput, stateFile: string, stepIndex: number): Promise<HookOutput>
export async function dispatchStep(
  step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  stateFile: string,
  stepIndex: number
): Promise<HookOutput> {
  switch (step.type) {
    case 'agent':
      return dispatchAgent(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'command':
      return dispatchCommand(step, _hookType, _hookInput, stateFile, stepIndex);
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
      return dispatchBranch(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'loop':
      return dispatchLoop(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'parallel':
      return dispatchParallel(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'approval':
      return dispatchApproval(step, _hookType, _hookInput, stateFile, stepIndex);
    default:
      return { decision: 'approve' };
  }
}

// FR-003: dispatchAgent - handles type: "agent" steps
async function dispatchAgent(
  step: WorkflowStep,
  hookType: HookType,
  _hookInput: HookInput,
  stateFile: string,
  stepIndex: number
): Promise<HookOutput> {
  if (hookType !== 'post_tool_use') {
    return { decision: 'approve' };
  }

  await stateSetStepStatus(stateFile, stepIndex, 'working');

  // Build context for agent
  const resolvedInputs = step.inputs ? resolveInputs(step.inputs, {} as WheelState, {} as any, {}) : {};
  const context = await contextBuild(step, {} as WheelState, resolvedInputs);

  return {
    decision: 'approve',
    additionalContext: context,
  };
}

// FR-019: dispatchCommand - executes command steps inline
async function dispatchCommand(
  step: WorkflowStep,
  hookType: HookType,
  _hookInput: HookInput,
  stateFile: string,
  stepIndex: number
): Promise<HookOutput> {
  if (hookType !== 'post_tool_use' || !step.command) {
    return { decision: 'approve' };
  }

  await stateSetStepStatus(stateFile, stepIndex, 'working');

  try {
    const { stdout, stderr } = await execAsync(step.command, { timeout: 300000 });
    const exitCode = 0; // If execAsync resolved, exit code is 0
    const timestamp = new Date().toISOString();

    // Append to command log
    const { stateAppendCommandLog } = await import('./state.js');
    await stateAppendCommandLog(stateFile, stepIndex, {
      command: step.command,
      exit_code: exitCode,
      timestamp,
    });

    await stateSetStepOutput(stateFile, stepIndex, stdout || stderr);
    await stateSetStepStatus(stateFile, stepIndex, 'done');

    return { decision: 'approve' };
  } catch (err) {
    const exitCode = (err as NodeJS.ErrnoException).code ?? 1;
    const timestamp = new Date().toISOString();
    const { stateAppendCommandLog } = await import('./state.js');
    await stateAppendCommandLog(stateFile, stepIndex, {
      command: step.command ?? '',
      exit_code: exitCode as number,
      timestamp,
    });
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    return { decision: 'approve' };
  }
}

// FR-014: dispatchWorkflow - handles type: "workflow" steps
async function dispatchWorkflow(
  _step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  _stateFile: string,
  _stepIndex: number
): Promise<HookOutput> {
  // Child workflow handling - returns instruction to create sub-workflow
  return { decision: 'approve' };
}

// FR-025: dispatchTeamCreate
async function dispatchTeamCreate(
  _step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  _stateFile: string,
  _stepIndex: number
): Promise<HookOutput> {
  return { decision: 'approve' };
}

// FR-025: dispatchTeammate
async function dispatchTeammate(
  _step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  _stateFile: string,
  _stepIndex: number
): Promise<HookOutput> {
  return { decision: 'approve' };
}

// FR-026: dispatchTeamWait
async function dispatchTeamWait(
  _step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  stateFile: string,
  stepIndex: number
): Promise<HookOutput> {
  const guardResult = await guardCheck(stateFile, stepIndex);
  if (guardResult.decision === 'block') {
    return {
      decision: 'block',
      additionalContext: guardResult.instruction,
    };
  }
  return { decision: 'approve' };
}

// FR-025: dispatchTeamDelete
async function dispatchTeamDelete(
  _step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  _stateFile: string,
  _stepIndex: number
): Promise<HookOutput> {
  return { decision: 'approve' };
}

// FR-024: dispatchBranch
async function dispatchBranch(
  _step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  _stateFile: string,
  _stepIndex: number
): Promise<HookOutput> {
  return { decision: 'approve' };
}

// FR-025: dispatchLoop
async function dispatchLoop(
  _step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  _stateFile: string,
  _stepIndex: number
): Promise<HookOutput> {
  return { decision: 'approve' };
}

// FR-009: dispatchParallel
async function dispatchParallel(
  _step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  _stateFile: string,
  _stepIndex: number
): Promise<HookOutput> {
  return { decision: 'approve' };
}

// FR-013: dispatchApproval - blocks orchestrator
async function dispatchApproval(
  _step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  stateFile: string,
  stepIndex: number
): Promise<HookOutput> {
  await stateSetAwaitingUserInput(stateFile, stepIndex, 'Approval required');
  return {
    decision: 'block',
    additionalContext: 'Approval required for this step. Please review and approve.',
  };
}

// FR-G3-1/FR-G3-4: _hydrateAgentStep - resolves step inputs against state + workflow + registry
export async function _hydrateAgentStep(
  step: WorkflowStep,
  _state: WheelState,
  _workflow: any,
  _stateFile: string,
  _stepIndex: number
): Promise<string> {
  if (!step.inputs) return '{}';

  try {
    const resolved = resolveInputs(step.inputs, _state, _workflow, {});
    return JSON.stringify(resolved);
  } catch (err) {
    return JSON.stringify({ error: String(err) });
  }
}