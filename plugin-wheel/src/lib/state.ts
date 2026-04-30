// FR-006: State operations on WheelState — read-modify-write via stateRead/stateWrite
import { stateRead, stateWrite } from '../shared/state.js';
import type { WheelState, StepStatus, AgentStatus, TeammateStatus, TeammateEntry } from '../shared/state.js';
import { mkdirp } from '../shared/fs.js';
import path from 'path';

export interface StateInitParams {
  stateFile: string;
  workflow: { name: string; version: string; steps: { id: string; type: string }[] };
  sessionId: string;
  agentId: string;
  workflowFile?: string;
  parentWorkflow?: string;
  sessionRegistry?: Record<string, string>;
}

// FR-006: Initialize a new state file from workflow definition
export async function stateInit(params: StateInitParams): Promise<void> {
  const { stateFile, workflow, sessionId, agentId, workflowFile, parentWorkflow, sessionRegistry } = params;

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
    started_at: now,
    updated_at: now,
    steps: workflow.steps.map((step) => ({
      id: step.id,
      type: step.type,
      status: 'pending' as StepStatus,
      started_at: null,
      completed_at: null,
      output: null,
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
  const state = await stateRead(stateFile);
  const now = new Date().toISOString();
  const step = state.steps[stepIndex];
  if (!step) return;

  step.status = status;
  if (status === 'working') {
    step.started_at = now;
  } else if (status === 'done' || status === 'failed') {
    step.completed_at = now;
  }
  state.updated_at = now;
  await stateWrite(stateFile, state);
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
  const state = await stateRead(stateFile);
  const now = new Date().toISOString();
  const step = state.steps[stepIndex];
  if (!step) return;

  if (!step.agents[agentType]) {
    step.agents[agentType] = { status: 'pending', started_at: null, completed_at: null };
  }
  const agent = step.agents[agentType];
  agent.status = status;
  if (status === 'working') {
    agent.started_at = now;
  } else if (status === 'done' || status === 'failed') {
    agent.completed_at = now;
  }
  state.updated_at = now;
  await stateWrite(stateFile, state);
}

// FR-006: stateSetStepOutput(stateFile: string, stepIndex: number, output: unknown): Promise<void>
export async function stateSetStepOutput(stateFile: string, stepIndex: number, output: unknown): Promise<void> {
  const state = await stateRead(stateFile);
  const step = state.steps[stepIndex];
  if (!step) return;
  step.output = output;
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-006: stateAppendCommandLog(stateFile: string, stepIndex: number, entry: { command: string; exit_code: number; timestamp: string }): Promise<void>
export async function stateAppendCommandLog(
  stateFile: string,
  stepIndex: number,
  entry: { command: string; exit_code: number; timestamp: string }
): Promise<void> {
  const state = await stateRead(stateFile);
  const step = state.steps[stepIndex];
  if (!step) return;
  step.command_log.push(entry);
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-006: stateGetCommandLog(state: WheelState, stepIndex: number): { command: string; exit_code: number; timestamp: string }[]
export function stateGetCommandLog(state: WheelState, stepIndex: number): { command: string; exit_code: number; timestamp: string }[] {
  return state.steps[stepIndex]?.command_log ?? [];
}

// FR-006: stateSetTeam(stateFile: string, stepId: string, teamName: string): Promise<void>
export async function stateSetTeam(stateFile: string, stepId: string, teamName: string): Promise<void> {
  const state = await stateRead(stateFile);
  state.teams[stepId] = {
    team_name: teamName,
    created_at: new Date().toISOString(),
    teammates: {},
  };
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-006: stateGetTeam(state: WheelState, stepId: string)
export function stateGetTeam(state: WheelState, stepId: string) {
  return state.teams[stepId] ?? null;
}

// FR-006: stateAddTeammate(stateFile: string, teamStepId: string, teammate: TeammateEntry): Promise<void>
export async function stateAddTeammate(stateFile: string, teamStepId: string, teammate: TeammateEntry): Promise<void> {
  const state = await stateRead(stateFile);
  if (!state.teams[teamStepId]) {
    state.teams[teamStepId] = { team_name: '', created_at: new Date().toISOString(), teammates: {} };
  }
  state.teams[teamStepId].teammates[teammate.agent_id] = teammate;
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-006: stateUpdateTeammateStatus(stateFile: string, teamStepId: string, agentName: string, status: TeammateStatus): Promise<void>
export async function stateUpdateTeammateStatus(stateFile: string, teamStepId: string, agentName: string, status: TeammateStatus): Promise<void> {
  const state = await stateRead(stateFile);
  const team = state.teams[teamStepId];
  if (!team || !team.teammates[agentName]) return;

  const now = new Date().toISOString();
  team.teammates[agentName].status = status;
  if (status === 'running') {
    team.teammates[agentName].started_at = now;
  } else if (status === 'completed' || status === 'failed') {
    team.teammates[agentName].completed_at = now;
  }
  state.updated_at = now;
  await stateWrite(stateFile, state);
}

// FR-006: stateGetTeammates(state: WheelState, teamStepId: string): Record<string, TeammateEntry>
export function stateGetTeammates(state: WheelState, teamStepId: string): Record<string, TeammateEntry> {
  return state.teams[teamStepId]?.teammates ?? {};
}

// FR-006: stateRemoveTeam(stateFile: string, stepId: string): Promise<void>
export async function stateRemoveTeam(stateFile: string, stepId: string): Promise<void> {
  const state = await stateRead(stateFile);
  delete state.teams[stepId];
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-003/004 (wheel-user-input): stateSetAwaitingUserInput
export async function stateSetAwaitingUserInput(stateFile: string, stepIndex: number, reason: string): Promise<void> {
  const state = await stateRead(stateFile);
  const step = state.steps[stepIndex];
  if (!step) return;
  step.awaiting_user_input = true;
  step.awaiting_user_input_since = new Date().toISOString();
  step.awaiting_user_input_reason = reason;
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-004/008 (wheel-user-input): stateClearAwaitingUserInput
export async function stateClearAwaitingUserInput(stateFile: string, stepIndex: number): Promise<void> {
  const state = await stateRead(stateFile);
  const step = state.steps[stepIndex];
  if (!step) return;
  step.awaiting_user_input = false;
  step.awaiting_user_input_since = null;
  step.awaiting_user_input_reason = null;
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-§4.1 (wheel-typed-schema-locality): stateSetResolvedInputs
export async function stateSetResolvedInputs(stateFile: string, stepIndex: number, resolvedMap: unknown): Promise<void> {
  const state = await stateRead(stateFile);
  const step = state.steps[stepIndex];
  if (!step) return;
  step.resolved_inputs = resolvedMap;
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-§4.2: stateSetContractEmitted
export async function stateSetContractEmitted(stateFile: string, stepIndex: number, emitted: boolean): Promise<void> {
  const state = await stateRead(stateFile);
  const step = state.steps[stepIndex];
  if (!step) return;
  step.contract_emitted = emitted;
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
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