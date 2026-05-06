// Shared types for the step dispatcher subsystem. Lives in its own module
// to break the circular import between `dispatch.ts` (the router) and
// `dispatchers/*.ts` (the per-step-type implementations) — every
// dispatcher file imports HookType/HookInput/HookOutput from here, the
// router imports them too, and neither imports the other.

import type { WorkflowStep } from '../shared/state.js';

export type HookType =
  | 'post_tool_use'
  | 'stop'
  | 'teammate_idle'
  | 'subagent_start'
  | 'subagent_stop'
  | 'session_start';

export interface HookInput {
  tool_name?: string;
  tool_input?: Record<string, unknown>;
  tool_output?: Record<string, unknown>;
  teammate_id?: string;
  session_id?: string;
  agent_id?: string;
  agent_type?: string;
  [key: string]: unknown;
}

export interface HookOutput {
  decision?: 'approve' | 'block';
  additionalContext?: string;
  hookEventName?: string;
  [key: string]: unknown;
}

/**
 * Per-step-type dispatcher function shape. All dispatchers in
 * `dispatchers/*.ts` implement this signature, and `dispatchStep`
 * (the router) maps `step.type` → one of these functions.
 *
 * `depth` is the cascade-recursion guard threaded through cascadeNext;
 * dispatchers that don't cascade (agent, teammate, team-wait, etc.)
 * accept it but ignore it.
 */
export type StepDispatcher = (
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
  depth?: number,
) => Promise<HookOutput>;

// FR-001 — single source of truth for cascade-eligible step types.
// Cascade tails MUST call `isAutoExecutable` rather than inline-comparing
// step.type to one of these.
export const AUTO_EXECUTABLE_STEP_TYPES: ReadonlySet<string> = new Set([
  'command',
  'loop',
  'branch',
]);

export function isAutoExecutable(step: WorkflowStep | { type?: string }): boolean {
  return AUTO_EXECUTABLE_STEP_TYPES.has(step.type ?? '');
}

// FR-006 — hard cap on cascade recursion depth. Graceful halt at this depth.
export const CASCADE_DEPTH_CAP = 1000;
