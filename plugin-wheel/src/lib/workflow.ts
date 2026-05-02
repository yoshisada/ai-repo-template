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

// parity: shell dispatch.sh:98 — resolve_next_index. If step.next is set,
// look up its target index in workflow.steps; else return stepIndex+1.
// Returns -1 if step.next references a non-existent step (caller decides
// how to surface; shell returns rc=1 + stderr).
export function resolveNextIndex(
  step: { next?: string } & Record<string, unknown>,
  stepIndex: number,
  workflow: WorkflowDefinition,
): number {
  const nextId = (step as { next?: string }).next;
  if (nextId) {
    const target = workflow.steps.findIndex(s => s.id === nextId);
    if (target === -1) return -1;
    return target;
  }
  return stepIndex + 1;
}

// parity: shell dispatch.sh:71 — advance_past_skipped. Walk past any
// steps marked status='skipped' in the live state file. Returns the
// next non-skipped index (may be >= workflow.steps.length when all
// remaining are skipped).
export async function advancePastSkipped(
  stateFile: string,
  rawNext: number,
  workflow: WorkflowDefinition,
): Promise<number> {
  const total = workflow.steps.length;
  let idx = rawNext;
  if (idx < 0) return idx;
  let state;
  try {
    state = await stateRead(stateFile);
  } catch {
    return idx;
  }
  while (idx < total) {
    const stepStatus = state.steps[idx]?.status;
    if (stepStatus === 'skipped') {
      idx++;
    } else {
      break;
    }
  }
  return idx;
}

// parity: shell dispatch.sh:1535–1544 — derive plugin dir from
// state.workflow_file. The workflow_file is at
//   <plugin-dir>/workflows/<wf-name>.json
// so the plugin dir is the directory two levels up from the file.
// Returns null if state can't be read or workflow_file missing.
export async function deriveWorkflowPluginDir(stateFile: string): Promise<string | null> {
  try {
    const state = await stateRead(stateFile);
    const wfFile = state.workflow_file;
    if (!wfFile) return null;
    const path = (await import('path')).default;
    const workflowsDir = path.dirname(wfFile);    // .../workflows
    const pluginDir = path.dirname(workflowsDir); // .../<plugin>
    return pluginDir;
  } catch {
    return null;
  }
}