// FR-006/FR-001: Core engine - initialization, kickstart, and hook handling
import { stateRead, stateWrite } from '../shared/state.js';
import { stateGetCursor, stateSetCursor, stateSetStepStatus, stateGetStepStatus, archiveWorkflow } from './state.js';
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
// FR-005 (wheel-wait-all-redesign): teammate_idle and subagent_stop hook
// events are wake-up nudges only. When the parent's current step is
// `team-wait`, they remap to 'post_tool_use' so dispatchTeamWait runs the
// polling backstop + re-check. For any other step type they no-op
// ({decision: 'approve'}). They MUST NOT contain team-wait-specific
// status mutation logic — that responsibility now lives entirely with
// FR-001 (archive helper) and FR-004 (polling backstop).
//
// FR-009 archive wiring (B-3 fix): after each successful dispatch + cursor
// advance, detect workflow-terminal condition and call archiveWorkflow.
// Two terminal triggers:
//   1. cursor advanced past the last step (natural completion)
//   2. a dispatcher explicitly set state.status to 'completed' or 'failed'
//      (early termination, e.g. command step with terminal: true)
// archiveWorkflow handles parent-teammate-slot update + cursor advance
// inline, then renames the child state file to .wheel/history/<bucket>/.
export async function engineHandleHook(hookType: HookType, hookInput: HookInput): Promise<HookOutput> {
  try {
    if (!STATE_FILE) {
      return { decision: 'approve' };
    }

    const state = await stateRead(STATE_FILE);
    const cursor = stateGetCursor(state);

    if (cursor >= state.steps.length) {
      // Workflow already at terminal cursor — try to archive if not yet
      // archived. This handles the case where a previous hook advanced
      // the cursor past the last step but the workflow archive was never
      // wired (B-3 path). Idempotent: if STATE_FILE is missing, the
      // archive helper is a no-op.
      await maybeArchiveTerminalWorkflow();
      return { decision: 'approve' };
    }

    const step = workflowGetStep(WORKFLOW, cursor);

    // FR-005: remap teammate_idle / subagent_stop to post_tool_use ONLY
    // when the current step is team-wait. For any other step, drop the
    // event (the legacy code paths in dispatchParallel etc. that responded
    // to teammate_idle still receive the original hookType because the
    // remap is gated on step.type === 'team-wait'.)
    let effectiveHookType: HookType = hookType;
    if (
      (hookType === 'teammate_idle' || hookType === 'subagent_stop') &&
      step.type === 'team-wait'
    ) {
      effectiveHookType = 'post_tool_use';
    }

    // Route through dispatch
    const result = await dispatchStep(step, effectiveHookType, hookInput, STATE_FILE, cursor);

    // Check if step is done and advance cursor. Re-read state because
    // dispatchers mutate step.status on disk; the `state` snapshot above
    // is from before dispatch and is stale.
    let postDispatchState;
    try {
      postDispatchState = await stateRead(STATE_FILE);
    } catch {
      // State file already gone (e.g., archived by a re-entrant call) —
      // nothing more to do.
      STATE_FILE = '';
      return result;
    }
    const postDispatchCursor = stateGetCursor(postDispatchState);
    const stepStatus = stateGetStepStatus(postDispatchState, postDispatchCursor);
    if (
      postDispatchCursor < postDispatchState.steps.length &&
      (stepStatus === 'done' || stepStatus === 'failed')
    ) {
      await stateSetCursor(STATE_FILE, postDispatchCursor + 1);
    }

    // FR-009: detect workflow-terminal and archive
    await maybeArchiveTerminalWorkflow();

    return result;
  } catch (err) {
    // Fail open - log error and approve
    console.error('Engine error:', err);
    return { decision: 'approve' };
  }
}

// FR-005 (wheel-ts-dispatcher-cascade): parameter-passed sibling of the
// engine's STATE_FILE-scoped helper below. Used by handleActivation
// post-cascade so the activation path archives terminal workflows too —
// the previous manual while-loop kickstart never invoked this logic.
//
// Idempotent: if state file is missing or workflow not terminal, no-op.
//
// Terminal conditions (any one suffices):
//   - cursor >= steps.length (natural completion at end-of-workflow)
//   - state.status === 'completed' (dispatcher set early-terminal explicitly)
//   - state.status === 'failed' (dispatcher set early-terminal explicitly)
//
// Bucket selection:
//   - state.status === 'failed' → 'failure'
//   - any step has status 'failed' → 'failure'
//   - otherwise → 'success'
export async function maybeArchiveAfterActivation(stateFile: string): Promise<void> {
  if (!stateFile) return;

  let updatedState;
  try {
    updatedState = await stateRead(stateFile);
  } catch {
    // State file already gone (archived by a re-entrant call) — nothing to do.
    return;
  }

  const newCursor = stateGetCursor(updatedState);
  const cursorTerminal = newCursor >= updatedState.steps.length;
  const explicitTerminal =
    updatedState.status === 'completed' || updatedState.status === 'failed';

  if (!cursorTerminal && !explicitTerminal) {
    return;
  }

  const anyStepFailed = updatedState.steps.some((s: any) => s.status === 'failed');
  const bucket: 'success' | 'failure' =
    updatedState.status === 'failed' || anyStepFailed ? 'failure' : 'success';

  if (!explicitTerminal) {
    const finalStatus: 'completed' | 'failed' =
      bucket === 'failure' ? 'failed' : 'completed';
    const fresh = await stateRead(stateFile);
    await stateWrite(stateFile, { ...fresh, status: finalStatus });
  }

  await archiveWorkflow(stateFile, bucket);
}

// FR-009 (wheel-wait-all-redesign B-3 fix): module-scoped wrapper that
// preserves the engine's STATE_FILE-clearing pattern (re-entrant-archive
// guard) while delegating the body to maybeArchiveAfterActivation.
async function maybeArchiveTerminalWorkflow(): Promise<void> {
  if (!STATE_FILE) return;

  // Detect-pre-archive existence so we can clear STATE_FILE before the
  // archive write (matches the original re-entrant guard).
  let probeState;
  try {
    probeState = await stateRead(STATE_FILE);
  } catch {
    STATE_FILE = '';
    return;
  }
  const newCursor = stateGetCursor(probeState);
  const cursorTerminal = newCursor >= probeState.steps.length;
  const explicitTerminal =
    probeState.status === 'completed' || probeState.status === 'failed';
  if (!cursorTerminal && !explicitTerminal) return;

  const archivedStateFile = STATE_FILE;
  STATE_FILE = '';
  try {
    await maybeArchiveAfterActivation(archivedStateFile);
  } catch (err) {
    STATE_FILE = archivedStateFile;
    throw err;
  }
}