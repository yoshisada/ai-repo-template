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
import type { WheelState } from '../shared/state.js';
import { resolveStateFile } from '../lib/guard.js';
import type { HookInput } from '../lib/dispatch.js';

function readStdin(): string {
  return readFileSync('/dev/stdin', 'utf-8');
}

interface ToolInput {
  team_name?: string;
  [key: string]: unknown;
}

interface HookDecision {
  decision?: 'block';
  reason?: string;
}

const PASS: HookDecision = {};

export async function decideTeamHookOutput(
  hookInput: HookInput,
  wheelDir: string = '.wheel',
): Promise<HookDecision> {
  const toolName = (hookInput.tool_name as string) ?? '';
  const toolInput = (hookInput.tool_input as ToolInput) ?? {};

  if (toolName !== 'TeamCreate' && toolName !== 'Agent') return PASS;

  const stateFile = await resolveStateFile(wheelDir, hookInput);
  if (!stateFile) return PASS;

  let state;
  try {
    state = await stateRead(stateFile);
  } catch {
    return PASS;
  }
  return decideFromState(toolName, toolInput, state);
}

async function main(): Promise<void> {
  try {
    const rawInput = readStdin();
    const hookInput: HookInput = JSON.parse(rawInput);
    const decision = await decideTeamHookOutput(hookInput);
    console.log(JSON.stringify(decision));
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    console.log(JSON.stringify({}));
  }
}

function decideFromState(toolName: string, toolInput: ToolInput, state: WheelState): HookDecision {
  try {

    const cursor = state.cursor ?? 0;
    const stepDef = state.workflow_definition?.steps?.[cursor]
      ?? state.steps?.[cursor];
    if (!stepDef) {
      return PASS;
    }

    const calledTeamName = toolInput.team_name ?? '';

    if (toolName === 'TeamCreate') {
      // Only guard during a team-create step. Other steps may call
      // TeamCreate for unrelated reasons; pass through.
      if (stepDef.type !== 'team-create') {
        return PASS;
      }
      const expected = (stepDef as { team_name?: string }).team_name ?? `${state.workflow_name}-${stepDef.id}`;
      if (calledTeamName === expected) {
        return PASS;
      }
      // Mismatch — deny.
      return {
        decision: 'block',
        reason: `Wheel team-name guard: TeamCreate must use team_name="${expected}" (the create-team step's declared name). Got "${calledTeamName}". Retry the call with team_name="${expected}".`,
      };
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
        return PASS;
      }
      const teamRef = (stepDef as { team?: string }).team;
      if (!teamRef) {
        return PASS;
      }
      const recordedTeamName = state.teams?.[teamRef]?.team_name;
      if (!recordedTeamName) {
        // Team not yet registered — pass through.
        return PASS;
      }
      // Verify team_name matches.
      if (calledTeamName !== recordedTeamName) {
        return {
          decision: 'block',
          reason: `Wheel Agent guard: team_name must be "${recordedTeamName}" for this workflow. Got "${calledTeamName}". Re-issue the Agent call with team_name="${recordedTeamName}".`,
        };
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
        return PASS;
      }
      // Source 1 — `name` field matches a slot's SHORT name only.
      //
      // Critical: we must NOT accept the FULL agent_id (`<short>@<team>`)
      // as the `name` value, even though it identifies the same slot.
      // Reason: Claude Code mangles the Agent call's `name + team_name`
      // into the spawned sub-agent's intrinsic agent_id like so:
      //
      //   name = "<short>"            → agent_id = `<short>@<team>`        ✓ matches slot
      //   name = "<short>@<team>"     → agent_id = `<short>-<team>@<team>` ✗ does NOT match
      //
      // The `@` in name gets sanitized to `-` and `@<team>` is appended
      // anyway, producing a different agent_id that won't match the
      // parent slot. Accepting the full-agent_id form here would let
      // the call through but leave the parent-child link broken
      // downstream — the exact false-PASS / hang failure we just fixed.
      //
      // Reject full-agent_id and steer the orchestrator to short-name.
      const teamSuffix = `@${calledTeamName}`;
      const calledNameLooksLikeFullAgentId = calledName.endsWith(teamSuffix);
      const nameMatches = !calledNameLooksLikeFullAgentId
        && slotAgentIds.some(aid => {
          const aidShort = aid.endsWith(teamSuffix)
            ? aid.slice(0, -teamSuffix.length)
            : aid;
          return calledName === aidShort;
        });
      // Source 2 — prompt scan for `--as <agent_id>`.
      const hasValidAs = slotAgentIds.some(aid => calledPrompt.includes(`--as ${aid}`));
      // Issue F (duplicate-spawn guard): if the call DOES identify a slot,
      // confirm that slot is still `pending`. Re-spawning a slot that's
      // already running/completed/failed produces a duplicate worker that
      // can't be linked back to the parent (slot's agent_id is taken) and
      // wastes orchestrator budget. Block with the slot's current status
      // so the orchestrator stops paranoia-spawning.
      if (nameMatches || hasValidAs) {
        // Determine which slot this call identifies.
        const teamSfxF = `@${calledTeamName}`;
        const matchedSlot = Object.values(teammates).find((s) => {
          if (!s || typeof s.agent_id !== 'string') return false;
          const aid = s.agent_id;
          const short = aid.endsWith(teamSfxF) ? aid.slice(0, -teamSfxF.length) : aid;
          if (calledName && (calledName === short || calledName === aid)) return true;
          if (calledPrompt.includes(`--as ${aid}`)) return true;
          return false;
        });
        if (matchedSlot && matchedSlot.status && matchedSlot.status !== 'pending') {
          return {
            decision: 'block',
            reason: [
              `Wheel duplicate-spawn guard: slot "${matchedSlot.agent_id}" is already in status "${matchedSlot.status}". Do NOT re-spawn it.`,
              ``,
              matchedSlot.status === 'running'
                ? `The teammate is mid-flight. Wait for hook signals (teammate_idle / spawn re-emit) instead of issuing another Agent call. The wheel will tell you what to do next.`
                : `The teammate has terminated (${matchedSlot.status}). Move on — don't try to revive it. The polling backstop already reconciled this slot.`,
            ].join('\n'),
          };
        }
      }
      if (!nameMatches && !hasValidAs) {
        // Neither the structured `name` field nor the prompt's `--as`
        // flag identifies a registered slot.
        //
        // Build the SHORT-name candidate list — what the orchestrator
        // should put in the Agent call's `name` parameter. Sending the
        // full agent_id (`<short>@<team>`) is a trap: Claude Code
        // mangles `@` in the name to `-` and the spawned sub-agent's
        // intrinsic agent_id will NOT match the parent slot's
        // registration. Always recommend short-name.
        const pendingAgentIds = Object.values(teammates)
          .filter((s) => s && s.status === 'pending')
          .map((s) => s.agent_id)
          .filter((s): s is string => !!s);
        const fullCandidates = pendingAgentIds.length > 0 ? pendingAgentIds : slotAgentIds;
        const teamSfx = `@${calledTeamName}`;
        const shortCandidates = fullCandidates.map(aid =>
          aid.endsWith(teamSfx) ? aid.slice(0, -teamSfx.length) : aid,
        );
        const recoveryLines: string[] = [
          `Wheel Agent guard: this Agent call has no slot identity. Re-issue it with the structured \`name\` field set to one of the registered teammate SHORT names below.`,
          ``,
          `Why short name (not full agent_id): Claude Code rewrites \`name + team_name\` into the spawned sub-agent's canonical agent_id. With \`name="<short>"\`, the spawned agent_id becomes \`<short>@<team>\` — verbatim equal to the slot. Send the full \`<short>@<team>\` and the \`@\` gets sanitized to \`-\`, breaking the linkage.`,
          ``,
          `Registered teammate short-names (one per Agent call, no duplicates):`,
        ];
        for (const sn of shortCandidates) recoveryLines.push(`  - ${sn}`);
        recoveryLines.push(``);
        recoveryLines.push(`Cleanest spawn block:`);
        recoveryLines.push('```');
        recoveryLines.push(`Agent({`);
        recoveryLines.push(`  subagent_type: "general-purpose",`);
        recoveryLines.push(`  name: "<one-of-the-short-names-above>",`);
        recoveryLines.push(`  team_name: "${calledTeamName}",`);
        recoveryLines.push(`  prompt: "bash <plugin>/bin/activate.sh <sub-workflow>\\n\\n^^ Run that command verbatim, then end the turn. The wheel auto-links the child to the parent slot via the sub-agent's intrinsic agent_id — no --as needed."`);
        recoveryLines.push(`})`);
        recoveryLines.push('```');
        return {
          decision: 'block',
          reason: recoveryLines.join('\n'),
        };
      }
      return PASS;
    }

    return PASS;
  } catch (err) {
    // Fail open — the guard MUST NOT break the harness if it errors.
    console.error(err instanceof Error ? err.message : String(err));
    return PASS;
  }
}

// Only run as a script (not when imported by tests). When imported, the
// vitest worker has no stdin payload to parse and the side-effect would
// emit a noisy "Unexpected end of JSON input" line.
if (process.argv[1] && process.argv[1].endsWith('pre-tool-use-team.js')) {
  main();
}
