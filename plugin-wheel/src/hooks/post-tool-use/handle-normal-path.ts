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
import type { WorkflowStep, Step } from '../../shared/state.js';
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
  const wfDef = state.workflow_definition;
  const wfSteps: ReadonlyArray<WorkflowStep | Step> = wfDef?.steps ?? state.steps;
  const step = wfSteps[cursor] ?? state.steps[cursor];

  // Step | WorkflowStep widen to WorkflowStep at the dispatch boundary.
  // The runtime shape is identical for the dispatcher's reads — `agents`
  // (the only nominal-difference field) is consumed only by `parallel`
  // and that dispatcher narrows the field locally.
  const dispatchInput = step as unknown as WorkflowStep;
  const stepType = step?.type ?? '';
  const stepStatus = state.steps[cursor]?.status ?? 'pending';
  let result: HookOutput;
  try {
    // Hook routing for agent / teammate steps depends on stepStatus:
    //
    //   pending  → dispatch as 'post_tool_use'. The agent dispatcher's
    //              post_tool_use+pending branch transitions to working
    //              WITHOUT unlinking the declared output file. This is
    //              critical when the orchestrator's PostToolUse event is
    //              the Write that creates the output file — pre-fix, this
    //              path forced 'stop', which fired the stop+pending unlink
    //              that deleted the just-written file, leaving the
    //              workflow stuck at working with no output forever.
    //
    //   working  → dispatch as 'stop'. The agent dispatcher's stop+working
    //              branch checks for the declared output file's presence
    //              and, if present, marks the step done + advances cursor.
    //              This is what archives terminal agent steps in the same
    //              hook fire (covered by hook-deactivate.test.ts'
    //              "terminal agent step archives to history/success/" case).
    //
    // Non-agent/teammate steps continue to dispatch as 'post_tool_use'.
    let hookForDispatch: 'stop' | 'post_tool_use';
    if (stepType === 'agent' || stepType === 'teammate') {
      hookForDispatch = stepStatus === 'working' ? 'stop' : 'post_tool_use';
    } else {
      hookForDispatch = 'post_tool_use';
    }
    result = await dispatchStep(dispatchInput, hookForDispatch, hookInput, stateFile, cursor);
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
