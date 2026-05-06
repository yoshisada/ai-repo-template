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
      // Fix A: dual-source contract for slot identity.
      //
      // SOURCE 1 (preferred — structured): the Agent call's `name`
      // parameter. Claude Code passes this through verbatim and it
      // shows up in the spawned sub-agent's identity. Orchestrators
      // (sonnet especially) paraphrase the prompt FAR more often than
      // they rewrite the structured `name` field, so trust it first.
      //
      // SOURCE 2 (fallback — text scan): the prompt contains
      // `--as <agent_id>` for one of the registered slots. This is
      // the legacy contract that the spawn template still emits, but
      // it's fragile — orchestrators routinely drop the activate.sh
      // line entirely when they paraphrase the multi-stage prompt
      // into a one-liner.
      //
      // EITHER source matching is sufficient — both encode the same
      // intent (link this child to a parent slot). Requiring both was
      // the bug: when only the structured field was preserved, we'd
      // block valid calls and burn the budget on retry loops.
      const teammates = state.teams?.[teamRef]?.teammates ?? {};
      const calledPrompt = String((toolInput as { prompt?: string }).prompt ?? '');
      const calledName = String((toolInput as { name?: string }).name ?? '');
      const slotAgentIds = Object.values(teammates)
        .map((s) => (s && typeof s.agent_id === 'string') ? s.agent_id : null)
        .filter((s): s is string => !!s);
      if (slotAgentIds.length === 0) {
        // No teammates registered yet — pass through; orchestrator may be
        // running an Agent for a non-teammate purpose.
        console.log(JSON.stringify({}));
        return;
      }
      // Source 1 — `name` field matches a slot's agent_id (or its
      // short-name part with `@<team>` stripped). Tolerate the common
      // re-shaping where orchestrators send `worker-1` for a slot
      // registered as `worker-1@test-team`.
      const teamSuffix = `@${calledTeamName}`;
      const calledNameShort = calledName.endsWith(teamSuffix)
        ? calledName.slice(0, -teamSuffix.length)
        : calledName;
      const nameMatches = slotAgentIds.some(aid => {
        const aidShort = aid.endsWith(teamSuffix)
          ? aid.slice(0, -teamSuffix.length)
          : aid;
        return calledName === aid || calledNameShort === aidShort;
      });
      // Source 2 — prompt scan for `--as <agent_id>`.
      const hasValidAs = slotAgentIds.some(aid => calledPrompt.includes(`--as ${aid}`));
      if (!nameMatches && !hasValidAs) {
        // Neither the structured `name` field nor the prompt's `--as`
        // flag identifies a registered slot. Surface both repair paths
        // so the orchestrator can pick whichever survives its own
        // paraphrasing better.
        const pendingAgentIds = Object.values(teammates)
          .filter((s) => s && s.status === 'pending')
          .map((s) => s.agent_id)
          .filter((s): s is string => !!s);
        const candidates = pendingAgentIds.length > 0 ? pendingAgentIds : slotAgentIds;
        const recoveryLines: string[] = [
          `Wheel Agent guard: this Agent call has no slot identity. Fix it ONE of two ways:`,
          ``,
          `Option 1 (preferred — structured): set the Agent call's \`name\` parameter to one of the registered teammate agent_ids. That field is the canonical slot link; the wheel guard accepts on \`name\` match alone.`,
          ``,
          `Option 2 (fallback — prompt-embedded): include \`--as <agent_id>\` in the prompt's activate.sh command. Use this if Option 1 is for some reason unavailable.`,
          ``,
          `Registered teammate agent_ids (one per Agent call, no duplicates):`,
        ];
        for (const aid of candidates) recoveryLines.push(`  - ${aid}`);
        recoveryLines.push(``);
        recoveryLines.push(`Re-issue the Agent call. The cleanest spawn block looks like:`);
        recoveryLines.push('```');
        recoveryLines.push(`Agent({`);
        recoveryLines.push(`  subagent_type: "general-purpose",`);
        recoveryLines.push(`  name: "<one-of-the-agent-ids-above>",`);
        recoveryLines.push(`  team_name: "${calledTeamName}",`);
        recoveryLines.push(`  prompt: "bash <plugin>/bin/activate.sh <sub-workflow> --as <one-of-the-agent-ids-above>\\n\\n^^ Run that command verbatim then end the turn; subsequent turns follow Stop-hook additionalContext instructions one tool call at a time."`);
        recoveryLines.push(`})`);
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
