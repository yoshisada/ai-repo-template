// FR-005: State file persistence layer
import { fileRead, atomicWrite } from './fs.js';
import { StateNotFoundError, ValidationError } from './error.js';

export type WorkflowStatus = 'running' | 'completed' | 'failed';

// Types matching contracts/interfaces.md §17
export interface WheelState {
  workflow_name: string;
  workflow_version: string;
  workflow_file: string;
  workflow_definition: WorkflowDefinition | null;
  status: WorkflowStatus;
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

// Runtime step shape: at init time, stateInit spreads the workflow-step
// JSON into state.steps[i] (FR-006), then overlays the dynamic state
// fields. So at runtime a Step ALSO carries WorkflowStep fields like
// `workflow`, `max_iterations`, `condition`, `team`, `loop_from`, etc.
// The index signature [k: string]: unknown lets dispatchers read those
// fields without `as any` casts at the cost of needing narrowing at the
// read site. (Modeling Step `extends WorkflowStep` collides on the
// `agents` field — runtime stores Record<string, Agent>, workflow JSON
// declares string[].)
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
  // Workflow-step JSON fields spread in at stateInit. Read-site narrowing
  // is the dispatcher author's responsibility.
  [key: string]: unknown;
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
  // Per-slot model override. Templated into the emitted Agent call's
  // `model:` field so the spawned sub-agent runs on the requested model
  // instead of inheriting the parent's. Resolved from the `teammate`
  // step's `model` JSON field at slot-registration time.
  model?: TeammateModel;
}

export type TeammateStatus = 'pending' | 'running' | 'completed' | 'failed';

// Model shapes accepted by Claude Code's Agent tool. Mirrors the runtime's
// model parameter on `Agent({...})`.
export type TeammateModel = 'sonnet' | 'opus' | 'haiku';

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

/**
 * List live wheel state files in `.wheel/` (the directory layer above
 * `.wheel/history/`). Returns `{ name, path }` pairs — `name` is the
 * basename (`state_<sid>_<ts>_<pid>.json`), `path` is `.wheel/<name>`.
 *
 * Replaces the duplicated `readdir + filter('state_'/'.json')` pattern
 * across hooks, dispatchers, guard, and team-wait helpers. Dir-missing
 * is treated as "no files" (empty array), matching every callsite's
 * behaviour pre-helper.
 */
export async function listLiveStateFiles(
  wheelDir: string = '.wheel',
): Promise<Array<{ name: string; path: string }>> {
  const { readdir } = await import('fs/promises');
  let entries: string[];
  try {
    entries = await readdir(wheelDir);
  } catch {
    return [];
  }
  const out: Array<{ name: string; path: string }> = [];
  for (const entry of entries) {
    if (!entry.startsWith('state_') || !entry.endsWith('.json')) continue;
    out.push({ name: entry, path: `${wheelDir}/${entry}` });
  }
  return out;
}