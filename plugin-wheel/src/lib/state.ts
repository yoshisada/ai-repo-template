// FR-006: State operations on WheelState — read-modify-write via stateRead/stateWrite
//
// =============================================================================
// FR-007 (wheel-wait-all-redesign) — LOCK-ORDERING INVARIANT
// =============================================================================
// Nothing in wheel takes a child state-file lock while holding a parent
// state-file lock. The cross-process signal between a child sub-workflow and
// its parent (a `team-wait` step) is a write under the PARENT's lock — and
// the child has already RELEASED its own lock by the time it reaches the
// rename-to-history step.
//
// Concrete rules:
//   1. archiveWorkflow reads child state OUTSIDE any lock (the child workflow
//      is terminal — no concurrent writers). It then takes the parent lock
//      via stateUpdateParentTeammateSlot / maybeAdvanceParentTeamWaitCursor.
//   2. stateUpdateParentTeammateSlot acquires ONLY the parent lock.
//   3. maybeAdvanceParentTeamWaitCursor acquires ONLY the parent lock.
//   4. Two siblings archiving simultaneously contend on the parent lock and
//      serialize via withLockBlocking's jittered backoff. Each updates a
//      disjoint slot, so both writes land.
//
// If a future change requires holding both a child and parent lock at the
// same time, that is a redesign — update this comment block first.
// =============================================================================
import { stateRead, stateWrite } from '../shared/state.js';
import type { WheelState, Step, StepStatus, AgentStatus } from '../shared/state.js';
import { mkdirp } from '../shared/fs.js';
import path from 'path';

// Re-export team and archive helpers for callers that imported them
// from `state.ts` directly. New code should import from the topic
// module (state-team / state-archive) directly.
export {
  stateSetTeam, stateGetTeam, stateAddTeammate,
  stateUpdateTeammateStatus, stateGetTeammates, stateRemoveTeam,
} from './state-team.js';
export {
  archiveWorkflow,
  stateUpdateParentTeammateSlot,
  maybeAdvanceParentTeamWaitCursor,
} from './state-archive.js';

export interface StateInitParams {
  stateFile: string;
  workflow: { name: string; version: string; steps: { id: string; type: string }[] };
  sessionId: string;
  agentId: string;
  workflowFile?: string;
  parentWorkflow?: string;
  sessionRegistry?: Record<string, string>;
  alternateAgentId?: string;
}

// FR-006: Initialize a new state file from workflow definition
export async function stateInit(params: StateInitParams): Promise<void> {
  const { stateFile, workflow, sessionId, agentId, workflowFile, parentWorkflow, sessionRegistry, alternateAgentId } = params;

  await mkdirp(path.dirname(stateFile));

  const now = new Date().toISOString();
  const state: WheelState = {
    workflow_name: workflow.name,
    workflow_version: workflow.version,
    workflow_file: workflowFile ?? '',
    workflow_definition: null,
    status: 'running',
    cursor: 0,
    owner_session_id: sessionId,
    owner_agent_id: agentId,
    alternate_agent_id: alternateAgentId,
    // FR-001/FR-009 (wheel-wait-all-redesign): persist parent path so the
    // archive helper can locate the parent state file at terminal time.
    parent_workflow: parentWorkflow ?? null,
    started_at: now,
    updated_at: now,
    // parity: shell wheel — state.steps[i] is a clone of the workflow
    // step JSON (id, type, instruction, output, context_from, command,
    // branches, max_iterations, agents, team_name, …) UNION-ed with the
    // dynamic state fields (status, started_at, command_log, etc.).
    // Hook entry points read step.output / step.instruction / step.command
    // from state.steps[i]; without the spread, those fields are absent
    // and dispatchers can't find the workflow-step shape (P0 bug found
    // in /wheel:wheel-test Phase 2 agent fixtures).
    steps: workflow.steps.map((step) => ({
      // 1. Spread workflow-step shape first.
      ...(step as Record<string, unknown>),
      // 2. Then override with dynamic state fields. Note: workflow-step
      //    `output` is the expected path; we preserve it here as the
      //    initial value, NOT null, so dispatchAgent's stop-hook check
      //    can find the path. Stale-file cleanup (FR-002 A1) deletes
      //    leftover files before the step runs.
      id: step.id,
      type: step.type,
      status: 'pending' as StepStatus,
      started_at: null,
      completed_at: null,
      output: (step as { output?: unknown }).output ?? null,
      command_log: [],
      agents: {},
      loop_iteration: 0,
      awaiting_user_input: false,
      awaiting_user_input_since: null,
      awaiting_user_input_reason: null,
      resolved_inputs: null,
      contract_emitted: false,
    })),
    teams: {},
    session_registry: sessionRegistry ?? null,
  };

  if (parentWorkflow) {
    // Load parent workflow definition for child workflows
    try {
      const parentState = await stateRead(parentWorkflow);
      state.workflow_definition = parentState.workflow_definition;
    } catch {
      // Parent not available, continue without it
    }
  }

  await stateWrite(stateFile, state);
}

// FR-006: stateGetCursor(state: WheelState): number
export function stateGetCursor(state: WheelState): number {
  return state.cursor;
}

/**
 * Read-modify-write helper for step mutations. Loads the state file,
 * looks up `state.steps[stepIndex]`, no-ops if the step is missing,
 * applies `mutator(step, now)`, stamps `state.updated_at`, and writes.
 *
 * Centralises the RMW pattern that every `stateSet*` helper used to
 * inline. The `now` ISO timestamp is computed once and threaded through
 * so callers can stamp `started_at` / `completed_at` consistently.
 */
async function mutateStep(
  stateFile: string,
  stepIndex: number,
  mutator: (step: Step, now: string) => void,
): Promise<void> {
  const state = await stateRead(stateFile);
  const step = state.steps[stepIndex];
  if (!step) return;
  const now = new Date().toISOString();
  mutator(step, now);
  state.updated_at = now;
  await stateWrite(stateFile, state);
}

// FR-006: stateSetCursor(stateFile: string, cursor: number): Promise<void>
export async function stateSetCursor(stateFile: string, cursor: number): Promise<void> {
  const state = await stateRead(stateFile);
  state.cursor = cursor;
  await stateWrite(stateFile, state);
}

// FR-006: stateGetStepStatus(state: WheelState, stepIndex: number): StepStatus
export function stateGetStepStatus(state: WheelState, stepIndex: number): StepStatus {
  return state.steps[stepIndex]?.status ?? 'pending';
}

// FR-006: stateSetStepStatus(stateFile: string, stepIndex: number, status: StepStatus): Promise<void>
export async function stateSetStepStatus(stateFile: string, stepIndex: number, status: StepStatus): Promise<void> {
  await mutateStep(stateFile, stepIndex, (step, now) => {
    step.status = status;
    if (status === 'working') step.started_at = now;
    else if (status === 'done' || status === 'failed') step.completed_at = now;
  });
}

// FR-006: stateGetAgentStatus(state: WheelState, stepIndex: number, agentType: string): AgentStatus
export function stateGetAgentStatus(state: WheelState, stepIndex: number, agentType: string): AgentStatus {
  const step = state.steps[stepIndex];
  if (!step) throw new Error(`Step ${stepIndex} not found`);
  const agent = step.agents[agentType];
  if (!agent) throw new Error(`Agent ${agentType} not found in step ${stepIndex}`);
  return agent.status;
}

// FR-006: stateSetAgentStatus(stateFile: string, stepIndex: number, agentType: string, status: AgentStatus): Promise<void>
export async function stateSetAgentStatus(stateFile: string, stepIndex: number, agentType: string, status: AgentStatus): Promise<void> {
  await mutateStep(stateFile, stepIndex, (step, now) => {
    if (!step.agents[agentType]) {
      step.agents[agentType] = { status: 'pending', started_at: null, completed_at: null };
    }
    const agent = step.agents[agentType];
    agent.status = status;
    if (status === 'working') agent.started_at = now;
    else if (status === 'done' || status === 'failed') agent.completed_at = now;
  });
}

// FR-006: stateSetStepOutput(stateFile: string, stepIndex: number, output: unknown): Promise<void>
export async function stateSetStepOutput(stateFile: string, stepIndex: number, output: unknown): Promise<void> {
  await mutateStep(stateFile, stepIndex, (step) => { step.output = output; });
}

// FR-006: stateAppendCommandLog(stateFile: string, stepIndex: number, entry: { command: string; exit_code: number; timestamp: string }): Promise<void>
export async function stateAppendCommandLog(
  stateFile: string,
  stepIndex: number,
  entry: { command: string; exit_code: number; timestamp: string }
): Promise<void> {
  await mutateStep(stateFile, stepIndex, (step) => { step.command_log.push(entry); });
}

// FR-006: stateGetCommandLog(state: WheelState, stepIndex: number): { command: string; exit_code: number; timestamp: string }[]
export function stateGetCommandLog(state: WheelState, stepIndex: number): { command: string; exit_code: number; timestamp: string }[] {
  return state.steps[stepIndex]?.command_log ?? [];
}


// FR-006: stateList(pattern?: string): Promise<string[]> - list state files matching pattern
export async function stateList(pattern: string = '.wheel/state_*.json'): Promise<string[]> {
  const { readdir } = await import('fs/promises');
  const pathModule = await import('path');

  // Parse pattern - handle basic glob like .wheel/state_*.json
  const dir = pattern.includes('/')
    ? pattern.slice(0, pattern.lastIndexOf('/'))
    : '.';
  const prefix = pattern.slice(pattern.lastIndexOf('/') + 1).replace('*.json', '').replace('*', '');

  let files: string[] = [];
  try {
    const entries = await readdir(dir);
    for (const entry of entries) {
      if (entry.startsWith(prefix) && entry.endsWith('.json')) {
        files.push(pathModule.join(dir, entry));
      }
    }
  } catch {
    // Directory may not exist
  }
  return files;
}

// FR-003/004 (wheel-user-input): stateSetAwaitingUserInput
export async function stateSetAwaitingUserInput(stateFile: string, stepIndex: number, reason: string): Promise<void> {
  await mutateStep(stateFile, stepIndex, (step, now) => {
    step.awaiting_user_input = true;
    step.awaiting_user_input_since = now;
    step.awaiting_user_input_reason = reason;
  });
}

// FR-004/008 (wheel-user-input): stateClearAwaitingUserInput
export async function stateClearAwaitingUserInput(stateFile: string, stepIndex: number): Promise<void> {
  await mutateStep(stateFile, stepIndex, (step) => {
    step.awaiting_user_input = false;
    step.awaiting_user_input_since = null;
    step.awaiting_user_input_reason = null;
  });
}

// FR-§4.1 (wheel-typed-schema-locality): stateSetResolvedInputs
export async function stateSetResolvedInputs(stateFile: string, stepIndex: number, resolvedMap: unknown): Promise<void> {
  await mutateStep(stateFile, stepIndex, (step) => { step.resolved_inputs = resolvedMap; });
}

// FR-§4.2: stateSetContractEmitted
export async function stateSetContractEmitted(stateFile: string, stepIndex: number, emitted: boolean): Promise<void> {
  await mutateStep(stateFile, stepIndex, (step) => { step.contract_emitted = emitted; });
}

// FR-§4.3: stateGetContractEmitted
export async function stateGetContractEmitted(stateFile: string, stepIndex: number): Promise<boolean> {
  try {
    const state = await stateRead(stateFile);
    return state.steps[stepIndex]?.contract_emitted ?? false;
  } catch {
    return false;
  }
}

