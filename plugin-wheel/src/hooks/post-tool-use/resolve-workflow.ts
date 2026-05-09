// Workflow file resolution + plugin discovery + JSON templating /
// pre-flight registry validation. All exports here are pure helpers;
// the activation handler imports them in sequence.
//
// FR-F3-1 (cross-plugin-resolver-and-preflight-registry).

import { promises as fs } from 'fs';
import path from 'path';
import { fileExists } from '../../shared/fs.js';
import { buildSessionRegistry } from '../../lib/registry.js';

interface DiscoveredWorkflow {
  name: string;
  plugin: string;
  path: string;
  readonly: boolean;
}

/**
 * Resolve a workflow name to an absolute path. Resolution order:
 *   1. Absolute path → use as-is
 *   2. `workflows/<name>.json` (cwd-relative) → local override
 *   3. `workflows/<stripped>.json` for `tests/foo` → `foo` shortform
 *   4. Direct path
 *   5. Discovered plugin workflows (manifest + auto-scan)
 */
export async function resolveWorkflowFile(workflowName: string): Promise<string | null> {
  if (workflowName.startsWith('/')) {
    if (await fileExists(workflowName)) return workflowName;
    const resolved = path.resolve(process.cwd(), workflowName);
    if (await fileExists(resolved)) return resolved;
  }
  const localPath = path.join(process.cwd(), 'workflows', `${workflowName}.json`);
  if (await fileExists(localPath)) return localPath;
  if (workflowName.startsWith('tests/')) {
    const strippedPath = path.join(process.cwd(), 'workflows', `${workflowName.slice(5)}.json`);
    if (await fileExists(strippedPath)) return strippedPath;
  }
  if (await fileExists(workflowName)) return workflowName;
  const workflows = await discoverPluginWorkflows();
  if (workflowName.includes(':')) {
    const [plugin, name] = workflowName.split(':');
    const found = workflows.find(w => w.plugin === plugin && w.name === name);
    return found?.path ?? null;
  }
  const found = workflows.find(w => w.name === workflowName);
  return found?.path ?? null;
}

/**
 * Discover workflows from installed plugins via
 * `~/.claude/plugins/installed_plugins.json` + each plugin's
 * `.claude-plugin/plugin.json` manifest + `workflows/` directory scan.
 */
export async function discoverPluginWorkflows(): Promise<DiscoveredWorkflow[]> {
  const results: DiscoveredWorkflow[] = [];
  const installedPluginsPath = path.join(process.env.HOME ?? '', '.claude', 'plugins', 'installed_plugins.json');

  try {
    const content = await fs.readFile(installedPluginsPath, 'utf-8');
    const data = JSON.parse(content);
    const plugins = data?.plugins ?? {};

    for (const [, pluginList] of Object.entries(plugins)) {
      if (!Array.isArray(pluginList)) continue;
      for (const plugin of pluginList) {
        const installPath = plugin?.installPath;
        if (!installPath) continue;
        const manifestPath = path.join(installPath, '.claude-plugin', 'plugin.json');
        if (await fileExists(manifestPath)) {
          try {
            const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf-8'));
            const workflows = manifest?.workflows;
            if (Array.isArray(workflows)) {
              for (const wfRelPath of workflows) {
                const wfAbsPath = path.join(installPath, wfRelPath);
                if (await fileExists(wfAbsPath)) {
                  results.push({
                    name: path.basename(wfRelPath, '.json'),
                    plugin: manifest.name ?? 'unknown',
                    path: wfAbsPath,
                    readonly: true,
                  });
                }
              }
            }
          } catch { /* skip malformed manifest */ }
        }
        const wfDir = path.join(installPath, 'workflows');
        try {
          const entries = await fs.readdir(wfDir);
          for (const entry of entries) {
            if (!entry.endsWith('.json')) continue;
            const wfAbsPath = path.join(wfDir, entry);
            const wfName = entry.replace('.json', '');
            if (!results.some(w => w.path === wfAbsPath)) {
              results.push({ name: wfName, plugin: 'unknown', path: wfAbsPath, readonly: true });
            }
          }
        } catch { /* no workflows dir */ }
      }
    }
  } catch { /* no installed_plugins.json */ }

  return results;
}

/**
 * Substitute `${WHEEL_PLUGIN_<name>}` and `${WORKFLOW_PLUGIN_DIR}`
 * placeholders inside agent-step instruction strings. Returns the
 * templated workflow JSON as a string.
 */
export function templateWorkflowJson(
  workflowJson: string,
  registry: Record<string, string>,
  callingPluginDir: string,
): string {
  const result = JSON.parse(workflowJson);
  if (result.steps && Array.isArray(result.steps)) {
    for (const step of result.steps) {
      if (step.type === 'agent' && step.instruction) {
        let instruction: string = step.instruction;
        const pluginMatches = instruction.matchAll(/\$\{WHEEL_PLUGIN_(\w+)\}/g);
        for (const match of pluginMatches) {
          const pluginPath = registry[match[1]];
          if (pluginPath) instruction = instruction.replace(match[0], pluginPath);
        }
        if (instruction.includes('${WORKFLOW_PLUGIN_DIR}') && callingPluginDir) {
          instruction = instruction.replace(/\$\{WORKFLOW_PLUGIN_DIR\}/g, callingPluginDir);
        }
        step.instruction = instruction;
      }
    }
  }
  return JSON.stringify(result);
}

/**
 * Build the session registry and validate workflow `requires_plugins`.
 * Self-bootstraps wheel if the workflow requires it. Throws if any
 * required plugin (other than wheel) is missing.
 */
export async function preflightResolve(workflowJson: string): Promise<Record<string, string>> {
  const registry = await buildSessionRegistry();
  let requiresPlugins: string[] = [];
  try {
    requiresPlugins = JSON.parse(workflowJson).requires_plugins ?? [];
  } catch { /* invalid JSON — skip */ }
  for (const pluginName of requiresPlugins) {
    if (!registry[pluginName]) {
      if (pluginName === 'wheel') {
        registry.wheel = path.dirname(path.dirname(process.execPath));
      } else {
        throw new Error(`Workflow requires plugin '${pluginName}' which is not installed`);
      }
    }
  }
  return registry;
}
