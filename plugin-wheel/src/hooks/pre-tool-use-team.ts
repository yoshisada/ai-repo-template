// PreToolUse hook for TeamCreate / Agent — guards against the agent
// inventing wrong identifiers when the wheel state machine is mid-flight.
//
// Why this exists: in subprocess / `--print` driven sessions where the agent
// loosely interprets the workflow JSON, it sometimes calls TeamCreate with
// the workflow's `name` field (e.g. "team-static-test") instead of the
// create-team step's `team_name` field (e.g. "test-static-team"). The
// dispatchTeamCreate post_tool_use detection records the EXPECTED team_name
// regardless of what the tool was called with — so the wheel state diverges
// from harness reality (no actual team is created with the recorded name).
// Workers spawned into the wrong team never run; the workflow stalls.
//
// This hook denies (returns decision: 'block') TeamCreate calls whose
// team_name doesn't match the wheel's current create-team step. Same shape
// for Agent calls whose team_name doesn't match. The block message tells
// the agent the correct name to retry with.

import { readFileSync } from 'fs';
import { stateRead } from '../shared/state.js';
import { resolveStateFile } from '../lib/guard.js';
import type { HookInput } from '../lib/dispatch.js';

function readStdin(): string {
  return readFileSync('/dev/stdin', 'utf-8');
}

interface ToolInput {
  team_name?: string;
  [key: string]: unknown;
}

async function main(): Promise<void> {
  try {
    const rawInput = readStdin();
    const hookInput: HookInput = JSON.parse(rawInput);
    const toolName = (hookInput.tool_name as string) ?? '';
    const toolInput = (hookInput.tool_input as ToolInput) ?? {};

    // Only guard TeamCreate and Agent.
    if (toolName !== 'TeamCreate' && toolName !== 'Agent') {
      console.log(JSON.stringify({}));
      return;
    }

    const stateFile = await resolveStateFile('.wheel', hookInput);
    if (!stateFile) {
      // No active wheel workflow — pass through; user is doing something else.
      console.log(JSON.stringify({}));
      return;
    }

    let state;
    try {
      state = await stateRead(stateFile);
    } catch {
      console.log(JSON.stringify({}));
      return;
    }

    const cursor = state.cursor ?? 0;
    const stepDef = state.workflow_definition?.steps?.[cursor]
      ?? state.steps?.[cursor];
    if (!stepDef) {
      console.log(JSON.stringify({}));
      return;
    }

    const calledTeamName = toolInput.team_name ?? '';

    if (toolName === 'TeamCreate') {
      // Only guard during a team-create step. Other steps may call
      // TeamCreate for unrelated reasons; pass through.
      if (stepDef.type !== 'team-create') {
        console.log(JSON.stringify({}));
        return;
      }
      const expected = (stepDef as { team_name?: string }).team_name ?? `${state.workflow_name}-${stepDef.id}`;
      if (calledTeamName === expected) {
        console.log(JSON.stringify({}));
        return;
      }
      // Mismatch — deny.
      console.log(JSON.stringify({
        decision: 'block',
        reason: `Wheel team-name guard: TeamCreate must use team_name="${expected}" (the create-team step's declared name). Got "${calledTeamName}". Retry the call with team_name="${expected}".`,
      }));
      return;
    }

    if (toolName === 'Agent') {
      // Guard during teammate steps OR while team-wait is working. The
      // team-wait window matters because the spawn block re-emits during
      // wait-all when teammate slots are still pending — the orchestrator
      // can issue Agent calls at that point.
      const isTeammateStep = stepDef.type === 'teammate';
      const isTeamWaitWorking =
        stepDef.type === 'team-wait' &&
        state.steps[cursor]?.status === 'working';
      if (!isTeammateStep && !isTeamWaitWorking) {
        console.log(JSON.stringify({}));
        return;
      }
      const teamRef = (stepDef as { team?: string }).team;
      if (!teamRef) {
        console.log(JSON.stringify({}));
        return;
      }
      const recordedTeamName = state.teams?.[teamRef]?.team_name;
      if (!recordedTeamName) {
        // Team not yet registered — pass through.
        console.log(JSON.stringify({}));
        return;
      }
      // Verify team_name matches.
      if (calledTeamName !== recordedTeamName) {
        console.log(JSON.stringify({
          decision: 'block',
          reason: `Wheel Agent guard: team_name must be "${recordedTeamName}" for this workflow. Got "${calledTeamName}". Re-issue the Agent call with team_name="${recordedTeamName}".`,
        }));
        return;
      }
      // Verify the prompt contains `--as <some-team-agent-id>` for one of
      // the registered teammate slots. This is stricter than name-field
      // matching because orchestrators (sonnet especially) routinely
      // rename teammates in Agent calls — e.g., `spawn-workers-0` becomes
      // `worker-0` — which makes name-based identification unreliable.
      // What we ACTUALLY care about is that the prompt has SOME valid
      // `--as <team-agent-id>` so the child gets linked to a parent slot.
      const teammates = state.teams?.[teamRef]?.teammates ?? {};
      const calledPrompt = String((toolInput as { prompt?: string }).prompt ?? '');
      const slotAgentIds = Object.values(teammates)
        .map((s) => (s && typeof s.agent_id === 'string') ? s.agent_id : null)
        .filter((s): s is string => !!s);
      if (slotAgentIds.length === 0) {
        // No teammates registered yet — pass through; orchestrator may be
        // running an Agent for a non-teammate purpose.
        console.log(JSON.stringify({}));
        return;
      }
      const hasValidAs = slotAgentIds.some(aid => calledPrompt.includes(`--as ${aid}`));
      if (!hasValidAs) {
        // Build a corrective recovery prompt that lists ALL valid
        // agent_ids the orchestrator could use. The orchestrator picks one
        // (the next un-spawned slot) and re-issues the Agent call with the
        // full 2-stage drive prompt.
        const pendingAgentIds = Object.values(teammates)
          .filter((s) => s && s.status === 'pending')
          .map((s) => s.agent_id)
          .filter((s): s is string => !!s);
        const candidates = pendingAgentIds.length > 0 ? pendingAgentIds : slotAgentIds;
        const recoveryLines: string[] = [
          `Wheel Agent guard: this Agent call's prompt does not contain a required \`--as <agent_id>\` flag for any registered teammate slot. The child workflow will not be linked to the parent's teammate slot, and team-wait will hang forever.`,
          ``,
          `Valid teammate agent_ids you can use (one per Agent call, no duplicates):`,
        ];
        for (const aid of candidates) recoveryLines.push(`  - ${aid}`);
        recoveryLines.push(``);
        recoveryLines.push(`Re-issue this Agent call with the FULL 2-stage drive prompt. Pick the next un-spawned agent_id from the list and use it in BOTH the activate.sh --as flag and the prompt's stage-1 instruction:`);
        recoveryLines.push(``);
        recoveryLines.push('```');
        recoveryLines.push(`prompt: "You are spawned to run a sub-workflow. Two stages:\\n\\nSTAGE 1 — Activate (single tool call): run this exact bash command, then end your turn:\\n\\nbash <plugin-dir>/bin/activate.sh <sub-workflow> --as <one-of-the-agent-ids-above>\\n\\nSTAGE 2 — Drive the workflow to completion. End your turn after each tool call so the wheel hooks can fire and instruct the next step. Loop until your sub-workflow's state file is archived."`);
        recoveryLines.push('```');
        console.log(JSON.stringify({
          decision: 'block',
          reason: recoveryLines.join('\n'),
        }));
        return;
      }
      console.log(JSON.stringify({}));
      return;
    }

    console.log(JSON.stringify({}));
  } catch (err) {
    // Fail open — the guard MUST NOT break the harness if it errors.
    console.error(err instanceof Error ? err.message : String(err));
    console.log(JSON.stringify({}));
  }
}

main();
