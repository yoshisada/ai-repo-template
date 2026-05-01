// FR-006: Workflow definition loading and access
import { stateRead } from '../shared/state.js';
import { StateNotFoundError, ValidationError } from '../shared/error.js';
import type { WorkflowDefinition, WorkflowStep } from '../shared/state.js';

// FR-006: workflowLoad(path: string): Promise<WorkflowDefinition>
export async function workflowLoad(path: string): Promise<WorkflowDefinition> {
  try {
    const state = await stateRead(path);
    if (state.workflow_definition) {
      return state.workflow_definition;
    }
    // Fall back to loading from file path stored in workflow_file
    const filePath = state.workflow_file;
    if (!filePath) {
      throw new ValidationError(path, 'No workflow definition available');
    }
    const content = await (await import('fs')).promises.readFile(filePath, 'utf-8');
    return JSON.parse(content) as WorkflowDefinition;
  } catch (err) {
    if (err instanceof StateNotFoundError || err instanceof ValidationError) {
      throw err;
    }
    // Try direct file read
    try {
      const content = await (await import('fs')).promises.readFile(path, 'utf-8');
      const wf = JSON.parse(content) as WorkflowDefinition;
      validateWorkflow(wf);
      return wf;
    } catch {
      throw new StateNotFoundError(path);
    }
  }
}

function validateWorkflow(wf: WorkflowDefinition): void {
  if (!wf.name) throw new ValidationError('workflow', 'Missing name');
  if (!Array.isArray(wf.steps) || wf.steps.length === 0) {
    throw new ValidationError('workflow', 'Missing steps');
  }
  for (const step of wf.steps) {
    if (!step.id) throw new ValidationError('workflow', `Step missing id`);
    if (!step.type) throw new ValidationError('workflow', `Step ${step.id} missing type`);
  }
}

// FR-006: workflowGetStep(workflow: WorkflowDefinition, index: number): WorkflowStep
export function workflowGetStep(workflow: WorkflowDefinition, index: number): WorkflowStep {
  if (index < 0 || index >= workflow.steps.length) {
    throw new ValidationError(`steps[${index}]`, 'Index out of range');
  }
  return workflow.steps[index];
}

// FR-006: workflowStepCount(workflow: WorkflowDefinition): number
export function workflowStepCount(workflow: WorkflowDefinition): number {
  return workflow.steps.length;
}

// FR-006: workflowGetBranchTarget(workflow: WorkflowDefinition, stepId: string, branchExitCode: number): WorkflowStep | null
export function workflowGetBranchTarget(workflow: WorkflowDefinition, stepId: string, branchExitCode: number): WorkflowStep | null {
  const step = workflow.steps.find(s => s.id === stepId);
  if (!step) return null;

  const target = branchExitCode === 0 ? step.if_zero : step.if_nonzero;
  if (!target || target === 'END') return null;

  const targetStep = workflow.steps.find(s => s.id === target);
  return targetStep ?? null;
}