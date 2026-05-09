// FR-006: Workflow definition loading and access
import { stateRead } from '../shared/state.js';
import { StateNotFoundError, ValidationError } from '../shared/error.js';
import type { WorkflowDefinition, WorkflowStep } from '../shared/state.js';

// FR-006: workflowLoad(path: string): Promise<WorkflowDefinition>
//
// Accepts EITHER a state-file path OR a raw workflow JSON path. P2 round-1
// fix (Phase 3 composition-mega): dispatchWorkflow calls workflowLoad with
// `workflows/tests/<name>.json` — a raw workflow file. Pre-fix the
// function read the JSON via stateRead (which loosely succeeds on any
// JSON), found no workflow_definition/workflow_file fields, threw
// ValidationError, and the inner catch rethrew it BEFORE reaching the
// direct-file-read fallback. Composition workflows therefore failed
// immediately on activation.
//
// New strategy:
//   1. Read the file once (raw bytes).
//   2. Parse JSON — bail with StateNotFoundError on any IO/parse error.
//   3. If it shape-matches a workflow JSON (has `name` + `steps[]` array),
//      return it directly. This is the common case for dispatchWorkflow.
//   4. Else treat as a state file: prefer workflow_definition, fall back
//      to workflow_file (which IS a workflow JSON path → recurse).
export async function workflowLoad(path: string): Promise<WorkflowDefinition> {
  const fs = (await import('fs')).promises;

  let content: string;
  try {
    content = await fs.readFile(path, 'utf-8');
  } catch {
    throw new StateNotFoundError(path);
  }

  let parsed: any;
  try {
    parsed = JSON.parse(content);
  } catch {
    throw new StateNotFoundError(path);
  }

  // Shape-detect: workflow JSON has top-level `name` + `steps[]`. State
  // file has `workflow_name`, `cursor`, etc. — distinct enough to tell apart.
  const looksLikeWorkflow =
    parsed && typeof parsed === 'object' &&
    typeof parsed.name === 'string' &&
    Array.isArray(parsed.steps);
  if (looksLikeWorkflow) {
    validateWorkflow(parsed as WorkflowDefinition);
    return parsed as WorkflowDefinition;
  }

  // State-file path: prefer workflow_definition, fall back to workflow_file.
  if (parsed && typeof parsed === 'object') {
    if (parsed.workflow_definition) {
      return parsed.workflow_definition as WorkflowDefinition;
    }
    const filePath = parsed.workflow_file;
    if (filePath && typeof filePath === 'string') {
      // Recurse — the workflow_file points at an actual workflow JSON.
      return workflowLoad(filePath);
    }
  }

  throw new ValidationError(path, 'No workflow definition available');
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