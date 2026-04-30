// FR-007: PostToolUse hook entry point with full activation support
// FR-C1 (specs/wheel-as-runtime): preserves newlines in tool_input.command
// FR-F3-1 (specs/cross-plugin-resolver-and-preflight-registry): pre-flight resolver
// T020: TypeScript implementation with shell shim fallback
// FR-C1 fallback: try python3 if jq fails (handles control chars)
import { promises as fs, readFileSync } from 'fs';
import path from 'path';
import { fileExists } from '../shared/fs.js';
import { stateRead, stateWrite } from '../shared/state.js';
import { stateInit } from '../lib/state.js';
import { dispatchStep, type HookInput, type HookOutput } from '../lib/dispatch.js';
import { buildSessionRegistry } from '../lib/registry.js';

// Direct workflow JSON load (bypasses stateRead which misinterprets workflow JSON as state file)
async function loadWorkflowJson(filePath: string): Promise<unknown> {
  const content = await fs.readFile(filePath, 'utf-8');
  const wf = JSON.parse(content);
  if (!wf.name) throw new Error('Invalid workflow: missing name');
  if (!Array.isArray(wf.steps) || wf.steps.length === 0) throw new Error('Invalid workflow: missing steps');
  for (const step of wf.steps) {
    if (!step.id) throw new Error('Invalid workflow: step missing id');
    if (!step.type) throw new Error(`Invalid workflow: step ${step.id} missing type`);
  }
  return wf;
}

// FR-C1: Read all stdin as string synchronously (preserves newlines)
function readStdin(): string {
  return readFileSync('/dev/stdin', 'utf-8');
}

// FR-C1 fallback: try python3 if jq fails (handles control chars)
async function extractCommandWithFallback(rawInput: string): Promise<string> {
  try {
    const parsed = JSON.parse(rawInput);
    const cmd = parsed?.tool_input?.command as string;
    if (cmd !== undefined) return cmd;
  } catch {
    // JSON parse failed, try python3
  }

  // Try python3 for strict=False parsing
  const { execSync } = await import('child_process');
  try {
    const cmd = execSync('python3 -c "import json,sys;d=json.loads(sys.stdin.read(),strict=False);print(d.get(\'tool_input\',{}).get(\'command\',\'\'))"', {
      input: rawInput,
      encoding: 'utf-8',
      timeout: 5000,
    });
    return cmd.trim();
  } catch {
    // Both failed
    console.error('wheel post-tool-use: FR-C1 command extraction failed (jq + python3 both rejected hook input)');
    return '';
  }
}

// Detect activate.sh invocation in command
function detectActivateLine(command: string): string | null {
  // Check for /wheel/ path (installed plugin path)
  if (command.includes('/wheel/') && command.includes('/bin/activate.sh')) {
    const lines = command.split('\n');
    for (let i = lines.length - 1; i >= 0; i--) {
      if (lines[i].includes('/bin/activate.sh')) {
        return lines[i];
      }
    }
  }
  // Check for local dev path
  if (command.includes('plugin-wheel/bin/activate.sh')) {
    const lines = command.split('\n');
    for (let i = lines.length - 1; i >= 0; i--) {
      if (lines[i].includes('activate.sh')) {
        return lines[i];
      }
    }
  }
  return null;
}

// Extract workflow name from activate.sh command line
function extractWorkflowName(line: string): string {
  // Remove activate.sh and everything after, then trim
  const afterActivate = line.split('activate.sh')[1]?.trim() ?? '';
  if (!afterActivate) return '';
  // Split by whitespace to get the first argument (which may be a path)
  const firstArg = afterActivate.split(/[[:space:]]+/)[0] ?? '';
  return firstArg.replace(/['"]/g, '');
}

// Extract --as flag value for teammate activation
function extractAlternateAgentId(line: string): string | null {
  if (!line.includes('--as ')) return null;
  const match = line.match(/--as\s+(\S+)/);
  return match ? match[1].replace(/['"]/g, '') : null;
}

// Resolve workflow file path from name
async function resolveWorkflowFile(workflowName: string): Promise<string | null> {
  console.error('DEBUG: resolveWorkflowFile input:', workflowName.substring(0, 100));

  // Absolute path - use directly if it starts with /
  if (workflowName.startsWith('/')) {
    console.error('DEBUG: checking absolute path:', workflowName);
    if (await fileExists(workflowName)) {
      console.error('DEBUG: absolute path exists:', workflowName);
      return workflowName;
    }
    // Try resolving relative to cwd if it's not an absolute path
    const resolved = path.resolve(process.cwd(), workflowName);
    console.error('DEBUG: resolved relative to cwd:', resolved);
    if (await fileExists(resolved)) return resolved;
  }

  // Local workflows/ — also try stripping leading "tests/" prefix since workflow
  // names from composition steps are like "tests/team-sub-worker"
  const localPath = path.join(process.cwd(), 'workflows', `${workflowName}.json`);
  console.error('DEBUG: checking localPath:', localPath);
  if (await fileExists(localPath)) return localPath;

  // Try stripping "tests/" prefix: "tests/foo" → "foo"
  if (workflowName.startsWith('tests/')) {
    const strippedName = workflowName.slice(5); // remove "tests/"
    const strippedPath = path.join(process.cwd(), 'workflows', `${strippedName}.json`);
    console.error('DEBUG: checking stripped localPath:', strippedPath);
    if (await fileExists(strippedPath)) return strippedPath;
  }

  // Try direct path
  console.error('DEBUG: checking direct path:', workflowName);
  if (await fileExists(workflowName)) return workflowName;

  // Discover from plugins
  const workflows = await discoverPluginWorkflows();
  console.error('DEBUG: discovered workflows count:', workflows.length);
  if (workflowName.includes(':')) {
    const [plugin, name] = workflowName.split(':');
    const found = workflows.find(w => w.plugin === plugin && w.name === name);
    return found?.path ?? null;
  }
  const found = workflows.find(w => w.name === workflowName);
  return found?.path ?? null;
}

// Discover workflows from installed plugins
interface DiscoveredWorkflow {
  name: string;
  plugin: string;
  path: string;
  readonly: boolean;
}

async function discoverPluginWorkflows(): Promise<DiscoveredWorkflow[]> {
  const results: DiscoveredWorkflow[] = [];
  const installedPluginsPath = path.join(process.env.HOME ?? '', '.claude', 'plugins', 'installed_plugins.json');

  try {
    const content = await fs.readFile(installedPluginsPath, 'utf-8');
    const data = JSON.parse(content);
    const plugins = data?.plugins ?? {};

    for (const [_org, pluginList] of Object.entries(plugins)) {
      if (!Array.isArray(pluginList)) continue;
      for (const plugin of pluginList) {
        const installPath = plugin?.installPath;
        if (!installPath) continue;

        // Check manifest for explicit workflows
        const manifestPath = path.join(installPath, '.claude-plugin', 'plugin.json');
        if (await fileExists(manifestPath)) {
          try {
            const manifestContent = await fs.readFile(manifestPath, 'utf-8');
            const manifest = JSON.parse(manifestContent);
            const workflows = manifest?.workflows;
            if (Array.isArray(workflows)) {
              for (const wfRelPath of workflows) {
                const wfAbsPath = path.join(installPath, wfRelPath);
                if (await fileExists(wfAbsPath)) {
                  const wfName = path.basename(wfRelPath, '.json');
                  results.push({
                    name: wfName,
                    plugin: manifest.name ?? 'unknown',
                    path: wfAbsPath,
                    readonly: true,
                  });
                }
              }
            }
          } catch {
            // Skip malformed manifest
          }
        }

        // Auto-scan workflows/ directory
        const wfDir = path.join(installPath, 'workflows');
        try {
          const entries = await fs.readdir(wfDir);
          for (const entry of entries) {
            if (!entry.endsWith('.json')) continue;
            const wfAbsPath = path.join(wfDir, entry);
            const wfName = entry.replace('.json', '');
            // Avoid duplicates
            if (!results.some(w => w.path === wfAbsPath)) {
              results.push({
                name: wfName,
                plugin: 'unknown',
                path: wfAbsPath,
                readonly: true,
              });
            }
          }
        } catch {
          // No workflows directory
        }
      }
    }
  } catch {
    // No installed_plugins.json
  }

  return results;
}

// Template workflow JSON with registry substitutions
function templateWorkflowJson(
  workflowJson: string,
  registry: Record<string, string>,
  callingPluginDir: string
): string {
  let result = JSON.parse(workflowJson);

  // Substitute in step instructions
  if (result.steps && Array.isArray(result.steps)) {
    for (const step of result.steps) {
      if (step.type === 'agent' && step.instruction) {
        let instruction = step.instruction;

        // ${WHEEL_PLUGIN_<name>} substitution
        const pluginMatches = instruction.matchAll(/\$\{WHEEL_PLUGIN_(\w+)\}/g);
        for (const match of pluginMatches) {
          const pluginName = match[1];
          const pluginPath = registry[pluginName];
          if (pluginPath) {
            instruction = instruction.replace(match[0], pluginPath);
          }
        }

        // ${WORKFLOW_PLUGIN_DIR} substitution
        if (instruction.includes('${WORKFLOW_PLUGIN_DIR}') && callingPluginDir) {
          instruction = instruction.replace(/\$\{WORKFLOW_PLUGIN_DIR\}/g, callingPluginDir);
        }

        step.instruction = instruction;
      }
    }
  }

  return JSON.stringify(result);
}

// Build session registry and validate workflow dependencies
async function preflightResolve(workflowJson: string): Promise<Record<string, string>> {
  const registry = await buildSessionRegistry();

  // Parse workflow to check requires_plugins
  let requiresPlugins: string[] = [];
  try {
    const wf = JSON.parse(workflowJson);
    requiresPlugins = wf.requires_plugins ?? [];
  } catch {
    // Invalid JSON, skip dependency check
  }

  // Validate each required plugin is in registry
  for (const pluginName of requiresPlugins) {
    if (!registry[pluginName]) {
      // Add wheel itself if missing (self-bootstrap)
      if (pluginName === 'wheel') {
        const wheelPath = path.dirname(path.dirname(process.execPath));
        registry['wheel'] = wheelPath;
      } else {
        throw new Error(`Workflow requires plugin '${pluginName}' which is not installed`);
      }
    }
  }

  return registry;
}

// Main activation handler
async function handleActivation(
  activateLine: string,
  hookInput: HookInput
): Promise<{ output: HookOutput; activated: boolean }> {
  const workflowName = extractWorkflowName(activateLine);
  const alternateAgentId = extractAlternateAgentId(activateLine);

  if (!workflowName) {
    return { output: { decision: 'approve' }, activated: false };
  }

  const workflowFile = await resolveWorkflowFile(workflowName);
  if (!workflowFile) {
    console.error(`wheel post-tool-use: activate-failed workflow=${workflowName} reason=unresolved-or-invalid`);
    return { output: { hookEventName: 'PostToolUse' }, activated: false };
  }

  // Load workflow
  console.error('DEBUG: workflowFile resolved to:', workflowFile);
  let workflowJson: string;
  try {
    const wf = await loadWorkflowJson(workflowFile) as Record<string, unknown>;
    workflowJson = JSON.stringify(wf);
    console.error('DEBUG: workflow loaded successfully, name:', wf.name);
  } catch (err) {
    console.error('DEBUG: workflowLoad failed:', err instanceof Error ? err.message : String(err));
    console.error(`wheel post-tool-use: activate-failed workflow=${workflowName} reason=unresolved-or-invalid`);
    return { output: { hookEventName: 'PostToolUse' }, activated: false };
  }

  // Run pre-flight resolver
  let registry: Record<string, string>;
  try {
    registry = await preflightResolve(workflowJson);
  } catch (err) {
    console.error(`wheel post-tool-use: activate-failed workflow=${workflowName} reason=preflight-resolver-failure`);
    return { output: { hookEventName: 'PostToolUse' }, activated: false };
  }

  // Template workflow JSON
  const callingPluginDir = path.dirname(path.dirname(workflowFile));
  let templatedWorkflow: string;
  try {
    templatedWorkflow = templateWorkflowJson(workflowJson, registry, callingPluginDir);
  } catch (err) {
    console.error(`wheel post-tool-use: activate-failed workflow=${workflowName} reason=preprocess-tripwire`);
    return { output: { hookEventName: 'PostToolUse' }, activated: false };
  }

  // Extract session/agent IDs from hook input
  const sessionId = (hookInput.session_id as string) ?? '';
  const agentId = (hookInput.agent_id as string) ?? '';

  // Generate unique state filename
  const unique = agentId || `${sessionId}_${Date.now()}_${Math.random().toString(36).slice(2)}`;
  const stateFile = `.wheel/state_${unique}.json`;

  // Initialize state
  const workflow = JSON.parse(templatedWorkflow);
  await stateInit({
    stateFile,
    workflow: { name: workflow.name, version: workflow.version ?? '1.0.0', steps: workflow.steps },
    sessionId,
    agentId,
    workflowFile,
    sessionRegistry: registry,
  });

  // Add alternate_agent_id if present
  if (alternateAgentId) {
    const state = await stateRead(stateFile);
    (state as unknown as Record<string, unknown>).alternate_agent_id = alternateAgentId;
    await stateWrite(stateFile, state);
  }

  console.error(`wheel post-tool-use: activate workflow=${workflowName} file=${workflowFile}`);

  // Run kickstart for automatic first steps
  console.error('DEBUG: running kickstart');
  const state = await stateRead(stateFile);
  let cursor = state.cursor;
  console.error('DEBUG: kickstart initial cursor=', cursor, 'steps=', workflow.steps.length);

  while (cursor < workflow.steps.length) {
    const step = workflow.steps[cursor];
    console.error('DEBUG: kickstart step', cursor, 'type=', step.type);
    if (step.type !== 'command' && step.type !== 'loop' && step.type !== 'branch') {
      console.error('DEBUG: kickstart stopping at non-inline step');
      break;
    }

    // Dispatch the step with 'post_tool_use' hook so commands actually execute
    try {
      await dispatchStep(step as any, 'post_tool_use', {}, stateFile, cursor);
    } catch (err) {
      console.error('DEBUG: kickstart dispatchStep error:', err);
      break;
    }

    // Re-read state after dispatch to get updated step status
    const newState = await stateRead(stateFile);
    const stepStatus = newState.steps[cursor]?.status;
    console.error('DEBUG: kickstart step status after dispatch:', stepStatus);

    if (stepStatus === 'done' || stepStatus === 'failed') {
      // Advance cursor manually
      cursor++;
      const updatedState = await stateRead(stateFile);
      updatedState.cursor = cursor;
      await stateWrite(stateFile, updatedState);
      console.error('DEBUG: kickstart advanced cursor to', cursor);
    } else {
      // Step not completed, stop kickstart
      console.error('DEBUG: kickstart stopping, step status:', stepStatus);
      break;
    }
  }
  console.error('DEBUG: kickstart done, final cursor=', cursor);

  return { output: { hookEventName: 'PostToolUse' }, activated: true };
}

// Resolve state file from hook input
async function resolveStateFile(
  stateDir: string,
  hookInput: HookInput
): Promise<string | null> {
  const hookSessionId = (hookInput.session_id as string) ?? '';
  const hookAgentId = (hookInput.agent_id as string) ?? '';

  const stateFiles = await fs.readdir(stateDir);
  for (const file of stateFiles) {
    if (!file.startsWith('state_') || !file.endsWith('.json')) continue;

    const statePath = path.join(stateDir, file);
    try {
      const content = await fs.readFile(statePath, 'utf-8');
      const state = JSON.parse(content);

      // Match by owner_session_id + owner_agent_id (or session-only if owner_agent_id is empty)
      if (state.owner_session_id === hookSessionId) {
        if (state.owner_agent_id === hookAgentId || state.owner_agent_id === '') {
          return statePath;
        }
      }

      // Match by alternate_agent_id (for teammate agents)
      if (state.alternate_agent_id === hookAgentId) {
        return statePath;
      }
    } catch {
      // Skip invalid state files
    }
  }

  return null;
}

// Handle normal post_tool_use for active workflow
async function handleNormalPath(
  hookInput: HookInput,
  stateFile: string
): Promise<HookOutput> {
  const state = await stateRead(stateFile);
  const cursor = state.cursor;

  if (cursor >= state.steps.length) {
    return { decision: 'approve' };
  }

  const step = state.steps[cursor];
  const stepType = step?.type ?? '';

  // For agent and teammate steps: dispatch with 'stop' hook (these handlers only respond to stop)
  if (stepType === 'agent' || stepType === 'teammate') {
    try {
      const result = await dispatchStep(step as any, 'stop', hookInput, stateFile, cursor);
      return result;
    } catch (err) {
      console.error('Engine error:', err);
      return { decision: 'approve' };
    }
  }

  // For all other step types, use 'post_tool_use' hook so commands actually execute
  try {
    const result = await dispatchStep(step as any, 'post_tool_use', hookInput, stateFile, cursor);
    return result;
  } catch (err) {
    console.error('Engine error:', err);
    return { decision: 'approve' };
  }
}

// Main entry point
async function main(): Promise<void> {
  try {
    console.error('DEBUG: starting hook');
    const rawInput = await readStdin();
    console.error('DEBUG: read stdin, len=', rawInput.length);
    const command = await extractCommandWithFallback(rawInput);
    const hookInput = JSON.parse(rawInput) as HookInput;

    // Check for deactivate.sh
    if (command.includes('deactivate.sh')) {
      console.log(JSON.stringify({ hookEventName: 'PostToolUse' }));
      return;
    }

    // Check for activate.sh
    const activateLine = detectActivateLine(command);
    console.error('DEBUG: detectActivateLine result:', activateLine ? 'found' : 'null');
    if (activateLine) {
      console.error('DEBUG: calling handleActivation with line:', activateLine.substring(0,100));
      const { output } = await handleActivation(activateLine, hookInput);
      console.log(JSON.stringify(output));
      return;
    }

    // Normal path: resolve state file
    const stateDir = '.wheel';
    const stateFile = await resolveStateFile(stateDir, hookInput);

    if (!stateFile) {
      console.log(JSON.stringify({ hookEventName: 'PostToolUse' }));
      return;
    }

    // Get workflow file from state
    const state = await stateRead(stateFile);
    const workflowFile = state.workflow_file;

    if (!workflowFile) {
      console.log(JSON.stringify({ hookEventName: 'PostToolUse' }));
      return;
    }

    const output = await handleNormalPath(hookInput, stateFile);
    console.log(JSON.stringify(output));
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}

main();