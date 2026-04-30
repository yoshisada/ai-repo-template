// FR-006/FR-001: Core engine - initialization, kickstart, and hook handling
import { stateRead } from '../shared/state.js';
import { stateGetCursor, stateSetCursor, stateSetStepStatus, stateGetStepStatus } from './state.js';
import { workflowLoad, workflowGetStep } from './workflow.js';
import { dispatchStep } from './dispatch.js';
import type { HookType, HookInput, HookOutput } from './dispatch.js';
import type { WorkflowStep } from '../shared/state.js';

// Module-level globals (per Invariant I-1)
let WORKFLOW: any = null;
let STATE_FILE: string = '';

// FR-006: engineInit(workflowFile: string, stateFile: string): Promise<void>
export async function engineInit(workflowFile: string, stateFile: string): Promise<void> {
  STATE_FILE = stateFile;

  try {
    const state = await stateRead(stateFile);
    if (state.workflow_definition) {
      WORKFLOW = state.workflow_definition;
      return;
    }
  } catch {
    // State file doesn't exist yet
  }

  // Load from workflow file
  WORKFLOW = await workflowLoad(workflowFile);
}

// FR-006: engineKickstart(stateFile: string): Promise<string | void>
export async function engineKickstart(stateFile: string): Promise<string | void> {
  const state = await stateRead(stateFile);
  const cursor = stateGetCursor(state);

  if (cursor >= state.steps.length) {
    // Workflow complete
    return;
  }

  const step = workflowGetStep(WORKFLOW, cursor);

  // Execute inline steps (command, loop, branch) immediately
  if (step.type === 'command' || step.type === 'loop' || step.type === 'branch') {
    await stateSetStepStatus(stateFile, cursor, 'working');
    // These are handled in dispatchStep
    return;
  }

  // For agent steps, return instruction string
  if (step.type === 'agent' && step.instruction) {
    return step.instruction;
  }

  return;
}

// FR-006: engineCurrentStep(): Promise<WorkflowStep | null>
export async function engineCurrentStep(): Promise<WorkflowStep | null> {
  if (!WORKFLOW || !STATE_FILE) return null;

  try {
    const state = await stateRead(STATE_FILE);
    const cursor = stateGetCursor(state);
    if (cursor >= state.steps.length) return null;
    return workflowGetStep(WORKFLOW, cursor);
  } catch {
    return null;
  }
}

// FR-006: engineHandleHook(hookType: HookType, hookInput: HookInput): Promise<HookOutput>
export async function engineHandleHook(hookType: HookType, hookInput: HookInput): Promise<HookOutput> {
  try {
    if (!STATE_FILE) {
      return { decision: 'approve' };
    }

    const state = await stateRead(STATE_FILE);
    const cursor = stateGetCursor(state);

    if (cursor >= state.steps.length) {
      // Workflow complete
      return { decision: 'approve' };
    }

    const step = workflowGetStep(WORKFLOW, cursor);

    // Route through dispatch
    const result = await dispatchStep(step, hookType, hookInput, STATE_FILE, cursor);

    // Check if step is done and advance cursor
    const stepStatus = stateGetStepStatus(state, cursor);
    if (stepStatus === 'done' || stepStatus === 'failed') {
      await stateSetCursor(STATE_FILE, cursor + 1);
    }

    return result;
  } catch (err) {
    // Fail open - log error and approve
    console.error('Engine error:', err);
    return { decision: 'approve' };
  }
}