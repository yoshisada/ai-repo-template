// FR-005: State file persistence layer
import { fileRead, atomicWrite } from './fs.js';
import { StateNotFoundError, ValidationError } from './error.js';

// Types matching contracts/interfaces.md §17
export interface WheelState {
  workflow_name: string;
  workflow_version: string;
  workflow_file: string;
  workflow_definition: WorkflowDefinition | null;
  status: 'running' | 'completed' | 'failed';
  cursor: number;
  owner_session_id: string;
  owner_agent_id: string;
  alternate_agent_id?: string;
  // FR-010 (wheel-wait-all-redesign): absolute path to parent state file when
  // this state belongs to a teammate sub-workflow; null/undefined for top-level.
  parent_workflow?: string | null;
  started_at: string;
  updated_at: string;
  steps: Step[];
  teams: Record<string, Team>;
  session_registry: Record<string, string> | null;
}

export interface Step {
  id: string;
  type: string;
  status: StepStatus;
  started_at: string | null;
  completed_at: string | null;
  output: unknown;
  command_log: CommandLogEntry[];
  agents: Record<string, Agent>;
  loop_iteration: number;
  awaiting_user_input: boolean;
  awaiting_user_input_since: string | null;
  awaiting_user_input_reason: string | null;
  resolved_inputs: unknown | null;
  contract_emitted: boolean;
}

export type StepStatus = 'pending' | 'working' | 'done' | 'failed' | 'skipped';

export interface Agent {
  status: AgentStatus;
  started_at: string | null;
  completed_at: string | null;
}

export type AgentStatus = 'pending' | 'working' | 'idle' | 'done' | 'failed';

export interface CommandLogEntry {
  command: string;
  exit_code: number;
  timestamp: string;
}

export interface Team {
  team_name: string;
  created_at: string;
  teammates: Record<string, TeammateEntry>;
}

export interface TeammateEntry {
  task_id: string;
  status: TeammateStatus;
  agent_id: string;
  output_dir: string;
  assign: unknown;
  started_at: string | null;
  completed_at: string | null;
  // FR-010 (wheel-wait-all-redesign): set only by FR-004 polling backstop on
  // the orphan path. Distinguishes "archive evidence said failed" from
  // "child state file disappeared without an archive".
  failure_reason?: string;
}

export type TeammateStatus = 'pending' | 'running' | 'completed' | 'failed';

export interface WorkflowDefinition {
  name: string;
  version: string;
  requires_plugins?: string[];
  steps: WorkflowStep[];
  [key: string]: unknown;
}

export interface WorkflowStep {
  id: string;
  type: string;
  instruction?: string;
  command?: string;
  condition?: string;
  if_zero?: string;
  if_nonzero?: string;
  max_iterations?: number;
  on_exhaustion?: 'fail' | 'continue';
  agents?: string[];
  inputs?: Record<string, string>;
  [key: string]: unknown;
}

/**
 * Read and parse a wheel state file.
 * FR-005: stateRead(path: string): Promise<WheelState>
 */
export async function stateRead(statePath: string): Promise<WheelState> {
  try {
    const content = await fileRead(statePath);
    const state = JSON.parse(content) as WheelState;
    return state;
  } catch (err) {
    if (err instanceof StateNotFoundError) {
      throw err;
    }
    throw new ValidationError(statePath, `Invalid JSON: ${String(err)}`);
  }
}

/**
 * Write state to file atomically. Sets updated_at before writing.
 * FR-005: stateWrite(path: string, state: WheelState): Promise<void>
 */
export async function stateWrite(statePath: string, state: WheelState): Promise<void> {
  const updated = { ...state, updated_at: new Date().toISOString() };
  const json = JSON.stringify(updated);
  await atomicWrite(statePath, json);
}