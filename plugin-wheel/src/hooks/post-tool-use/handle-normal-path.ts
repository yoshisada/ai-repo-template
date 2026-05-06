// handleNormalPath — the hook handler for tool calls that aren't
// activate.sh / deactivate.sh. Runs the dispatcher on the workflow's
// current step, then runs the post-dispatch terminal-archive helper.
//
// listMatchingStateFiles is also here — it owns the "iterate
// .wheel/state_*.json and find owners matching the hook's
// (session_id, agent_id) tuple, plus alternate_agent_id" pattern.
//
// Round-3 P1 fix: handleNormalPath always runs maybeArchiveAfterActivation
// after dispatch — without it, agent/teammate flows that drove cursor past
// the last step would sit at cursor>=steps.length forever.

import { promises as fs } from 'fs';
import { stateRead, listLiveStateFiles } from '../../shared/state.js';
import { dispatchStep, type HookInput, type HookOutput } from '../../lib/dispatch.js';
import { maybeArchiveAfterActivation } from '../../lib/engine.js';

/**
 * P3 fix: return ALL state files whose ownership matches the hook input.
 *
 * With composition / team workflows, multiple state files can share an
 * owner_session_id (parent + children). Pre-fix the single-file lookup
 * always returned the first match (typically the parent), so the child
 * never advanced. Mirrors shell post-tool-use.sh's loop pattern.
 */
export async function listMatchingStateFiles(
  stateDir: string,
  hookInput: HookInput,
): Promise<string[]> {
  const hookSessionId = (hookInput.session_id as string) ?? '';
  const hookAgentId = (hookInput.agent_id as string) ?? '';
  const matched: string[] = [];

  for (const { path: statePath } of await listLiveStateFiles(stateDir)) {
    try {
      const state = JSON.parse(await fs.readFile(statePath, 'utf-8'));
      // Match by owner_session_id + owner_agent_id (or session-only if
      // owner_agent_id is empty).
      if (state.owner_session_id === hookSessionId) {
        if (state.owner_agent_id === hookAgentId || state.owner_agent_id === '') {
          matched.push(statePath);
          continue;
        }
      }
      // Match by alternate_agent_id (for teammate agents).
      if (state.alternate_agent_id === hookAgentId) {
        matched.push(statePath);
      }
    } catch { /* skip invalid state files */ }
  }
  return matched;
}

/**
 * Dispatch the workflow's current step + run post-dispatch archive check.
 * Exported for regression tests.
 */
export async function handleNormalPath(
  hookInput: HookInput,
  stateFile: string,
): Promise<HookOutput> {
  const state = await stateRead(stateFile);
  const cursor = state.cursor;

  if (cursor >= state.steps.length) {
    // Orphan-recovery path: cursor advanced past the last step but the
    // workflow archive was never wired. Idempotent: no-op if state file
    // is gone or workflow not yet terminal.
    try {
      await maybeArchiveAfterActivation(stateFile);
    } catch { /* non-fatal */ }
    return { decision: 'approve' };
  }

  // P0 fix: prefer workflow_definition.steps[cursor] over state.steps[cursor]
  // for the dispatcher input — definition carries full WorkflowStep shape
  // (output, instruction, command, branches, …); state.steps is a dynamic
  // projection and pre-fix stripped definition fields.
  const wfDef = (state as any).workflow_definition;
  const wfSteps: any[] = wfDef?.steps ?? state.steps;
  const step = wfSteps[cursor] ?? state.steps[cursor];
  const stepType = step?.type ?? '';

  let result: HookOutput;
  try {
    if (stepType === 'agent' || stepType === 'teammate') {
      // Agent + teammate dispatchers only respond to 'stop' hooks.
      result = await dispatchStep(step as any, 'stop', hookInput, stateFile, cursor);
    } else {
      result = await dispatchStep(step as any, 'post_tool_use', hookInput, stateFile, cursor);
    }
  } catch (err) {
    console.error('Engine error:', err);
    return { decision: 'approve' };
  }

  // P1 fix: post-dispatch terminal-workflow archive check. parity: shell
  // wheel's handle_terminal_step is called from each dispatcher, so
  // cursor>=steps.length OR state.status==completed/failed always
  // triggers archive in the same hook fire. Idempotent.
  try {
    await maybeArchiveAfterActivation(stateFile);
  } catch { /* non-fatal: archive errors don't block hook response */ }

  return result;
}
