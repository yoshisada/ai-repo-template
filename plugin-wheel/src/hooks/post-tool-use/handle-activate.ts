// handleActivation — the activate.sh hook handler.
//
// 1. Extract workflow_name + alternate_agent_id from the activate.sh line.
// 2. Resolve workflow file → load + JSON validate → preflight registry → template.
// 3. Defensive guard: refuse double-activation of the same
//    (session_id, alternate_agent_id, workflow_name) triple.
// 4. stateInit + persist workflow_definition into the new state file.
// 5. If alternate_agent_id is present (teammate-spawned child), scan
//    active state files for the parent registering this teammate slot
//    and stamp `parent_workflow` so archiveWorkflow can link the slot.
// 6. Run post-init cascade (single dispatchStep on first auto-executable step).
// 7. Run terminal-cursor archive helper to handle workflows that drove
//    themselves to terminal in this same hook fire.
//
// Returns `{output, activated}`. The caller writes `output` to stdout.

import path from 'path';
import { stateRead, stateWrite, listLiveStateFiles } from '../../shared/state.js';
import { stateInit } from '../../lib/state.js';
import { dispatchStep, isAutoExecutable, type HookInput, type HookOutput } from '../../lib/dispatch.js';
import { maybeArchiveAfterActivation } from '../../lib/engine.js';
import {
  extractWorkflowName,
  extractAlternateAgentId,
  loadWorkflowJson,
} from './extractors.js';
import {
  resolveWorkflowFile,
  templateWorkflowJson,
  preflightResolve,
} from './resolve-workflow.js';

export async function handleActivation(
  activateLine: string,
  hookInput: HookInput,
): Promise<{ output: HookOutput; activated: boolean }> {
  const workflowName = extractWorkflowName(activateLine);
  const alternateAgentId = extractAlternateAgentId(activateLine);
  if (!workflowName) return { output: { decision: 'approve' }, activated: false };

  const workflowFile = await resolveWorkflowFile(workflowName);
  if (!workflowFile) {
    console.error(`wheel post-tool-use: activate-failed workflow=${workflowName} reason=unresolved-or-invalid`);
    return { output: { hookEventName: 'PostToolUse' }, activated: false };
  }

  // Defensive guard against double-activation of the same workflow.
  const guardResult = await checkDoubleActivation(workflowName, alternateAgentId, hookInput);
  if (guardResult) return guardResult;

  // Load + preflight + template the workflow.
  let workflowJson: string;
  try {
    const wf = await loadWorkflowJson(workflowFile) as Record<string, unknown>;
    workflowJson = JSON.stringify(wf);
  } catch (err) {
    console.error(`wheel post-tool-use: activate-failed workflow=${workflowName} reason=unresolved-or-invalid err=${err instanceof Error ? err.message : String(err)}`);
    return { output: { hookEventName: 'PostToolUse' }, activated: false };
  }
  let registry: Record<string, string>;
  try {
    registry = await preflightResolve(workflowJson);
  } catch {
    console.error(`wheel post-tool-use: activate-failed workflow=${workflowName} reason=preflight-resolver-failure`);
    return { output: { hookEventName: 'PostToolUse' }, activated: false };
  }
  let templatedWorkflow: string;
  try {
    const callingPluginDir = path.dirname(path.dirname(workflowFile));
    templatedWorkflow = templateWorkflowJson(workflowJson, registry, callingPluginDir);
  } catch {
    console.error(`wheel post-tool-use: activate-failed workflow=${workflowName} reason=preprocess-tripwire`);
    return { output: { hookEventName: 'PostToolUse' }, activated: false };
  }

  // stateInit
  const sessionId = (hookInput.session_id as string) ?? '';
  const agentId = (hookInput.agent_id as string) ?? '';
  const unique = agentId || `${sessionId}_${Date.now()}_${Math.random().toString(36).slice(2)}`;
  const stateFile = `.wheel/state_${unique}.json`;
  const workflow = JSON.parse(templatedWorkflow);
  await stateInit({
    stateFile,
    workflow: { name: workflow.name, version: workflow.version ?? '1.0.0', steps: workflow.steps },
    sessionId, agentId, workflowFile,
    sessionRegistry: registry,
  });

  // Persist workflow_definition into state so subsequent hooks can load
  // it via stateRead. Without this, engineInit falls through to
  // workflowLoad(workflowFile) which throws.
  {
    const persisted = await stateRead(stateFile);
    persisted.workflow_definition = workflow;
    await stateWrite(stateFile, persisted);
  }

  // Stamp alternate_agent_id + parent_workflow if present.
  if (alternateAgentId) {
    await linkToParent(stateFile, alternateAgentId);
  }

  console.error(`wheel post-tool-use: activate workflow=${workflowName} file=${workflowFile}`);

  // FR-005 — post-init cascade (drives the workflow until first blocking step).
  if (workflow.steps.length > 0 && isAutoExecutable(workflow.steps[0])) {
    try {
      await dispatchStep(workflow.steps[0], 'post_tool_use', hookInput, stateFile, 0, 0);
    } catch { /* non-fatal: cascade error during activation swallowed */ }
  }
  // FR-005 — terminal-cursor archive after cascade.
  await maybeArchiveAfterActivation(stateFile);
  return { output: { hookEventName: 'PostToolUse' }, activated: true };
}

/**
 * Refuse to double-activate the same workflow_name for the same
 * (session_id, alternate_agent_id) pair. Different alternate_agent_id
 * (i.e., teammate-spawned children) is fine — those are legitimate
 * concurrent state files for the same parent.
 */
async function checkDoubleActivation(
  workflowName: string,
  alternateAgentId: string | null,
  hookInput: HookInput,
): Promise<{ output: HookOutput; activated: boolean } | null> {
  const sessionId = (hookInput.session_id as string) ?? '';
  const expectedAlt = alternateAgentId ?? '';
  for (const { path: candidate } of await listLiveStateFiles()) {
    try {
      const existing = await stateRead(candidate);
      if (existing.owner_session_id !== sessionId) continue;
      const existingAlt = existing.alternate_agent_id ?? '';
      if (existingAlt !== expectedAlt) continue;
      if (existing.workflow_name !== workflowName) continue;
      console.error(`wheel post-tool-use: activate-rejected workflow=${workflowName} reason=already-active state=${candidate}`);
      return {
        output: {
          decision: 'block',
          additionalContext: `A workflow named "${workflowName}" is ALREADY active for this session (state file: ${candidate}). Do NOT re-activate it. Continue driving the existing workflow: end your turn so the wheel hooks emit instructions for the next step. To check progress, the cursor advance is logged in .wheel/wheel.log. To activate a DIFFERENT workflow, finish or stop the current one first.`,
        },
        activated: false,
      };
    } catch { /* skip unreadable */ }
  }
  return null;
}

/**
 * Stamp alternate_agent_id on the new child state. If the alt id is in
 * `name@team_name` form (teammate spawn), scan active state files for
 * the parent registering this teammate slot and also stamp
 * parent_workflow so archiveWorkflow's parent-update path fires.
 */
async function linkToParent(stateFile: string, alternateAgentId: string): Promise<void> {
  const state = await stateRead(stateFile);
  state.alternate_agent_id = alternateAgentId;
  if (alternateAgentId.includes('@')) {
    for (const { path: candidate } of await listLiveStateFiles()) {
      if (candidate === stateFile) continue;
      try {
        const parent = await stateRead(candidate);
        const teams = parent.teams ?? {};
        let matched = false;
        for (const team of Object.values(teams)) {
          const teammates = team.teammates ?? {};
          for (const slot of Object.values(teammates)) {
            if (slot.agent_id === alternateAgentId) {
              state.parent_workflow = candidate;
              matched = true;
              break;
            }
          }
          if (matched) break;
        }
        if (matched) break;
      } catch { /* skip unreadable */ }
    }
  }
  await stateWrite(stateFile, state);
}
