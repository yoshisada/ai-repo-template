// FR-015: Barrel export for shared utilities
export { WheelError, StateNotFoundError, ValidationError, LockError } from './error.js';
export { jqQuery, jqQueryRaw, jqUpdate } from './jq.js';
export { atomicWrite, mkdirp, fileRead, fileExists } from './fs.js';
export { stateRead, stateWrite } from './state.js';
export type {
  WheelState,
  Step,
  StepStatus,
  Agent,
  AgentStatus,
  CommandLogEntry,
  Team,
  TeammateEntry,
  TeammateStatus,
  WorkflowDefinition,
  WorkflowStep,
} from './state.js';

// Hook types for engine
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