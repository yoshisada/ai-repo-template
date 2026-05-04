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
import { dispatchStep, isAutoExecutable, type HookInput, type HookOutput } from '../lib/dispatch.js';
import { maybeArchiveAfterActivation } from '../lib/engine.js';
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
  // Absolute path - use directly if it starts with /
  if (workflowName.startsWith('/')) {
    if (await fileExists(workflowName)) {
      return workflowName;
    }
    // Try resolving relative to cwd if it's not an absolute path
    const resolved = path.resolve(process.cwd(), workflowName);
    if (await fileExists(resolved)) return resolved;
  }

  // Local workflows/ — also try stripping leading "tests/" prefix since workflow
  // names from composition steps are like "tests/team-sub-worker"
  const localPath = path.join(process.cwd(), 'workflows', `${workflowName}.json`);
  if (await fileExists(localPath)) return localPath;

  // Try stripping "tests/" prefix: "tests/foo" → "foo"
  if (workflowName.startsWith('tests/')) {
    const strippedName = workflowName.slice(5); // remove "tests/"
    const strippedPath = path.join(process.cwd(), 'workflows', `${strippedName}.json`);
    if (await fileExists(strippedPath)) return strippedPath;
  }

  // Try direct path
  if (await fileExists(workflowName)) return workflowName;

  // Discover from plugins
  const workflows = await discoverPluginWorkflows();
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
  let workflowJson: string;
  try {
    const wf = await loadWorkflowJson(workflowFile) as Record<string, unknown>;
    workflowJson = JSON.stringify(wf);
  } catch (err) {
    console.error(`wheel post-tool-use: activate-failed workflow=${workflowName} reason=unresolved-or-invalid err=${err instanceof Error ? err.message : String(err)}`);
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

  // Persist the templated workflow definition into the state so subsequent
  // hooks (Stop, SubagentStop, TeammateIdle) can load it via stateRead's
  // workflow_definition field — engineInit's first preference. Without this,
  // those hooks fall through to workflowLoad(workflowFile) which throws
  // "No workflow definition available" because workflowLoad expects a state
  // file path, not a workflow file path. Caught during wheel-wait-all-redesign
  // live verification (B-3-followup).
  {
    const persisted = await stateRead(stateFile);
    persisted.workflow_definition = workflow;
    await stateWrite(stateFile, persisted);
  }

  // Add alternate_agent_id if present
  if (alternateAgentId) {
    const state = await stateRead(stateFile);
    (state as unknown as Record<string, unknown>).alternate_agent_id = alternateAgentId;
    await stateWrite(stateFile, state);
  }

  console.error(`wheel post-tool-use: activate workflow=${workflowName} file=${workflowFile}`);

  // FR-005 — post-init cascade. Single dispatchStep call; the cascade tails
  // in dispatchCommand/Loop/Branch (FR-002/003/004) drive the rest. The
  // previous manual while-loop kickstart was inlining the cascade in the
  // hook, duplicating responsibility and missing FR-009 cascade-event logs.
  if (workflow.steps.length > 0 && isAutoExecutable(workflow.steps[0])) {
    try {
      await dispatchStep(workflow.steps[0] as any, 'post_tool_use', hookInput, stateFile, 0, 0);
    } catch (err) {
      // non-fatal: cascade error during activation swallowed (parity hygiene).
    }
  }
  // FR-005 — terminal-cursor archive after cascade. cascadeNext can drive
  // the workflow to terminal in a single hook fire; without this, activation
  // would leave an orphaned state_*.json (SC-003 regression).
  await maybeArchiveAfterActivation(stateFile);

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
// Exported for regression testing (Round-3 P1 archive flow).
export async function handleNormalPath(
  hookInput: HookInput,
  stateFile: string
): Promise<HookOutput> {
  const state = await stateRead(stateFile);
  const cursor = state.cursor;

  if (cursor >= state.steps.length) {
    // P1 round-2 fix: cursor already past last step — try to archive
    // the workflow if it's terminal. This is the orphan-recovery path
    // for state files left behind by a pre-fix run that advanced cursor
    // but didn't archive. Idempotent: no-op if state file is already
    // gone or not yet terminal.
    try {
      await maybeArchiveAfterActivation(stateFile);
    } catch {
      // non-fatal
    }
    return { decision: 'approve' };
  }

  // P0 fix: prefer workflow_definition.steps[cursor] over state.steps[cursor]
  // for the dispatcher input. workflow_definition.steps[cursor] carries the
  // full workflow-step JSON (output path, instruction, context_from,
  // command, branches, …). state.steps[cursor] is the dynamic projection;
  // pre-fix it was missing the workflow-step properties so dispatchAgent
  // could not find step.output and the agent step never advanced. After
  // the stateInit spread fix, both sources carry the same fields, but we
  // keep this guard so the cascade tail and hook entry point use the
  // SAME source-of-truth (parity with cascadeNext at dispatch.ts:173).
  const wfDef = (state as any).workflow_definition;
  const wfSteps: any[] = wfDef?.steps ?? state.steps;
  const step = wfSteps[cursor] ?? state.steps[cursor];
  const stepType = step?.type ?? '';

  // P1 fix: after every dispatch, run the post-dispatch terminal-workflow
  // archive check. handleNormalPath was the only path that didn't trigger
  // archive — engineHandleHook does it via maybeArchiveTerminalWorkflow,
  // and the activation path does it via maybeArchiveAfterActivation. The
  // hook-based agent/teammate flow advances cursor past the last step
  // (or marks state.status='completed' for terminal:true), but without
  // an archive trigger here the workflow sits at cursor>=steps.length
  // until an unrelated hook event happens to fire engineHandleHook.
  // (Found in Phase 2 agent-chain fixture: cursor=4 of 4, terminal step
  // done, status=running, never archived.)
  let result: HookOutput;
  try {
    if (stepType === 'agent' || stepType === 'teammate') {
      // For agent and teammate steps: dispatch with 'stop' hook (these handlers only respond to stop)
      result = await dispatchStep(step as any, 'stop', hookInput, stateFile, cursor);
    } else {
      // For all other step types, use 'post_tool_use' hook so commands actually execute
      result = await dispatchStep(step as any, 'post_tool_use', hookInput, stateFile, cursor);
    }
  } catch (err) {
    console.error('Engine error:', err);
    return { decision: 'approve' };
  }

  // parity: shell wheel — handle_terminal_step is invoked from inside each
  // dispatcher, so cursor>=steps.length OR state.status==completed/failed
  // always triggers archive in the same hook fire. We mirror that via the
  // existing maybeArchiveAfterActivation helper (idempotent — no-op if
  // not terminal).
  try {
    await maybeArchiveAfterActivation(stateFile);
  } catch {
    // non-fatal: archive errors don't block the hook response
  }

  return result;
}

/**
 * parity: shell post-tool-use.sh:81–176 — handle a deactivate.sh
 * invocation. Modes:
 *   --all          → archive every state file in .wheel/state_*.json
 *   <substring>    → archive state files whose basename contains arg
 *   <empty>        → archive only the caller's own state file
 *                    (matched by owner_session_id + owner_agent_id)
 *
 * After primary archive: cascade-stop child workflows (parent_workflow
 * points to a now-missing file) and team sub-workflows (teammate
 * agent_ids found in archived state). Always returns
 * {hookEventName: 'PostToolUse'}.
 */
export async function handleDeactivate(
  command: string,
  hookInput: HookInput,
): Promise<HookOutput> {
  // Extract argument from the deactivate line.
  const lines = command.split('\n').filter(l => l.includes('deactivate.sh'));
  const lastLine = lines[lines.length - 1] ?? '';
  const afterCmd = lastLine.replace(/.*deactivate\.sh\s*/, '');
  const arg = (afterCmd.split(/\s+/)[0] ?? '').replace(/['"]/g, '');

  const sessionId = String((hookInput as any).session_id ?? '');
  const agentId = String((hookInput as any).agent_id ?? '');

  const stoppedDir = path.join('.wheel', 'history', 'stopped');
  await fs.mkdir(stoppedDir, { recursive: true });

  const stateDir = '.wheel';
  let stateFiles: string[] = [];
  try {
    const all = await fs.readdir(stateDir);
    stateFiles = all
      .filter(f => f.startsWith('state_') && f.endsWith('.json'))
      .map(f => path.join(stateDir, f));
  } catch {
    stateFiles = [];
  }

  const archiveOne = async (sf: string): Promise<void> => {
    const ts = new Date().toISOString().replace(/[-:]/g, '').replace(/\..*Z$/, '').replace('T', '-');
    const fname = path.basename(sf, '.json');
    const target = path.join(stoppedDir, `${fname}-${ts}.json`);
    try {
      await fs.copyFile(sf, target);
      await fs.unlink(sf);
    } catch {
      // non-fatal — log via wheelLog if needed
    }
  };

  if (arg === '--all') {
    for (const sf of stateFiles) await archiveOne(sf);
  } else if (arg) {
    for (const sf of stateFiles) {
      if (path.basename(sf).includes(arg)) await archiveOne(sf);
    }
  } else {
    for (const sf of stateFiles) {
      try {
        const s = JSON.parse(await fs.readFile(sf, 'utf-8'));
        if (s.owner_session_id === sessionId && s.owner_agent_id === agentId) {
          await archiveOne(sf);
          break;
        }
      } catch {
        // skip unreadable
      }
    }
  }

  // FR-018: cascade-stop child workflows whose parent_workflow points to
  // a now-missing file.
  try {
    const remaining = await fs.readdir(stateDir);
    for (const f of remaining) {
      if (!f.startsWith('state_') || !f.endsWith('.json')) continue;
      const sf = path.join(stateDir, f);
      try {
        const s = JSON.parse(await fs.readFile(sf, 'utf-8'));
        const parent = s.parent_workflow as string | null | undefined;
        if (parent) {
          try {
            await fs.access(parent);
          } catch {
            // parent gone — stop child
            await archiveOne(sf);
          }
        }
      } catch {
        // skip
      }
    }
  } catch {
    // .wheel may not exist
  }

  // FR-028: cascade-stop team agent sub-workflows. Walk archived state
  // files in stopped/ to find teammate agent_ids, then archive any live
  // state file with matching owner_agent_id.
  try {
    const stoppedFiles = await fs.readdir(stoppedDir);
    const teammateAgentIds = new Set<string>();
    for (const f of stoppedFiles) {
      try {
        const s = JSON.parse(await fs.readFile(path.join(stoppedDir, f), 'utf-8'));
        const teams = s.teams as Record<string, any> | undefined;
        if (!teams) continue;
        for (const team of Object.values(teams)) {
          const teammates = (team as any)?.teammates ?? {};
          for (const tm of Object.values(teammates)) {
            const status = (tm as any)?.status ?? '';
            const aid = (tm as any)?.agent_id ?? '';
            if ((status === 'pending' || status === 'running') && aid) {
              teammateAgentIds.add(String(aid));
            }
          }
        }
      } catch {
        // skip
      }
    }
    if (teammateAgentIds.size > 0) {
      const live = await fs.readdir(stateDir).catch(() => [] as string[]);
      for (const f of live) {
        if (!f.startsWith('state_') || !f.endsWith('.json')) continue;
        const sf = path.join(stateDir, f);
        try {
          const s = JSON.parse(await fs.readFile(sf, 'utf-8'));
          if (teammateAgentIds.has(String(s.owner_agent_id ?? ''))) {
            await archiveOne(sf);
          }
        } catch {
          // skip
        }
      }
    }
  } catch {
    // ignore
  }

  return { hookEventName: 'PostToolUse' };
}

// Main entry point
async function main(): Promise<void> {
  try {
    const rawInput = await readStdin();
    const command = await extractCommandWithFallback(rawInput);
    const hookInput = JSON.parse(rawInput) as HookInput;

    // parity: shell post-tool-use.sh:83 — handle deactivate.sh BEFORE
    // activate.sh (substring overlap).
    if (command.includes('deactivate.sh')) {
      const output = await handleDeactivate(command, hookInput);
      console.log(JSON.stringify(output));
      return;
    }

    // Check for activate.sh
    const activateLine = detectActivateLine(command);
    if (activateLine) {
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

// Only invoke main() when this module is the entry point (allows testing
// individual exports without triggering hook execution).
const mainScript = process.argv[1] ?? '';
if (mainScript.endsWith('post-tool-use.js') || mainScript.endsWith('post-tool-use.ts')) {
  main();
}