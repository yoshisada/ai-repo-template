// FR-006: Variable substitution for ${WHEEL_PLUGIN_*} and ${WORKFLOW_PLUGIN_DIR}
import type { WorkflowDefinition } from '../shared/state.js';

// FR-006: preprocess(workflow: WorkflowDefinition, registry: SessionRegistry): WorkflowDefinition
export type SessionRegistry = Record<string, string>;

export function preprocess(workflow: WorkflowDefinition, registry: SessionRegistry): WorkflowDefinition {
  // Deep clone to avoid mutation
  const result = JSON.parse(JSON.stringify(workflow)) as WorkflowDefinition;

  // Substitute in all string fields
  substituteInObject(result, registry);

  return result;
}

function substituteInObject(obj: unknown, registry: SessionRegistry): void {
  if (obj === null || obj === undefined) return;

  if (typeof obj === 'string') {
    // Substitute patterns
    let result = obj;

    // ${WHEEL_PLUGIN_<name>} pattern
    const wheelPluginMatch = result.match(/\$\{WHEEL_PLUGIN_(\w+)\}/);
    if (wheelPluginMatch) {
      const pluginName = wheelPluginMatch[1];
      const pluginPath = registry[pluginName];
      if (pluginPath) {
        result = result.replace(wheelPluginMatch[0], pluginPath);
      }
    }

    // ${WORKFLOW_PLUGIN_DIR} pattern
    if (result.includes('${WORKFLOW_PLUGIN_DIR}')) {
      // WORKFLOW_PLUGIN_DIR is set by wheel at runtime for agent steps
      // We leave this as-is for preprocess - it gets replaced at runtime
    }

    return;
  }

  if (Array.isArray(obj)) {
    for (const item of obj) {
      substituteInObject(item, registry);
    }
    return;
  }

  if (typeof obj === 'object') {
    for (const [key, value] of Object.entries(obj as Record<string, unknown>)) {
      if (typeof value === 'string') {
        let result = value;

        const wheelMatch = result.match(/\$\{WHEEL_PLUGIN_(\w+)\}/);
        if (wheelMatch) {
          const pluginName = wheelMatch[1];
          const pluginPath = registry[pluginName];
          if (pluginPath) {
            result = result.replace(wheelMatch[0], pluginPath);
            (obj as Record<string, unknown>)[key] = result;
          }
        }
      } else {
        substituteInObject(value, registry);
      }
    }
  }
}