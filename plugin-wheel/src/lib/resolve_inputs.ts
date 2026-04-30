// FR-006: Agent input resolution with variable references
import type { WheelState, WorkflowDefinition } from '../shared/state.js';

// FR-006: resolveInputs(inputs: Record<string, string>, state: WheelState, workflow: WorkflowDefinition, registry: SessionRegistry): ResolvedInputs
export type SessionRegistry = Record<string, string>;
export type ResolvedInputs = Record<string, unknown>;

export function resolveInputs(
  inputs: Record<string, string>,
  _state: WheelState,
  _workflow: WorkflowDefinition,
  _registry: SessionRegistry
): ResolvedInputs {
  const resolved: ResolvedInputs = {};

  for (const [key, value] of Object.entries(inputs)) {
    resolved[key] = resolveValue(value);
  }

  return resolved;
}

function resolveValue(value: string): unknown {
  // $(state.path) pattern
  const stateMatch = value.match(/^\$\(state\.([^)]+)\)$/);
  if (stateMatch) {
    // For now, return placeholder - actual state resolution happens at runtime
    return `{state:${stateMatch[1]}}`;
  }

  // $(workflow.path) pattern
  const workflowMatch = value.match(/^\$\(workflow\.([^)]+)\)$/);
  if (workflowMatch) {
    return `{workflow:${workflowMatch[1]}}`;
  }

  // $plugin(<name>.path) pattern
  const pluginMatch = value.match(/^\$plugin\((\w+)\.path\)$/);
  if (pluginMatch) {
    return `{plugin:${pluginMatch[1]}}`;
  }

  // Plain string value
  return value;
}