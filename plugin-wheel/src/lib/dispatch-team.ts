// FR-006 — team-primitive helpers extracted from dispatch.ts to keep the
// dispatcher under the 500-line cap (Constitution Article VI).
// All exports here are direct ports of the matching shell functions
// (parity references inline). Module-private helpers prefix _.

import { stateRead, stateWrite } from '../shared/state.js';
import type { WheelState } from '../shared/state.js';
import { fileURLToPath } from 'url';
import { dirname, resolve as pathResolve } from 'path';

// Re-export wait-all helpers (extracted to dispatch-team-wait-helpers.ts)
// so existing dynamic-import callers keep working. New code should
// import from the topic file directly.
export {
  _teamWaitProgressSnapshot,
  _teamWaitBuildWakeBlock,
  _teamWaitAdvanceChildIfAuto,
  _teamWaitComplete,
} from './dispatch-team-wait-helpers.js';

// Derive plugin root from this module's file location. This module compiles
// to `<plugin-root>/dist/lib/dispatch-team.js`, so the plugin root is two
// levels up. Used by `_teammateFlushFromState` to emit absolute activate.sh
// paths so spawned teammates' Bash calls work from any cwd (sub-agent
// session cwd ≠ orchestrator cwd in general).
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const PLUGIN_ROOT = pathResolve(__dirname, '..', '..');

export interface TeammateSpawnInfo {
  name: string;
  agent_id: string;
  output_dir: string;
  workflow: string;
  task_id?: string;
}

/**
 * Idea 5: Resolve the sub-workflow's first agent step (if any) so the
 * spawn prompt can pre-load the worker with concrete first-action
 * instructions. Returns `null` when:
 *   - workflow file isn't on disk (e.g., consumer install path varies)
 *   - workflow has no agent step
 *   - file read / parse fails
 *
 * Best-effort: never throws. Spawn template falls back to generic
 * "follow hook signals" wording when this returns null.
 */
async function _resolveFirstAgentStep(workflowName: string): Promise<{
  id: string;
  instruction: string;
  output: string;
} | null> {
  const fs = (await import('fs')).promises;
  // Conventional path. Match the resolver's same lookup order
  // (`workflows/<name>.json`, `workflows/tests/<name>.json`, etc.) but
  // simplified — if none of these match, return null.
  const candidates = [
    `workflows/${workflowName}.json`,
    `workflows/${workflowName.replace(/^tests\//, '')}.json`,
    `${workflowName}.json`,
    workflowName,
  ];
  for (const p of candidates) {
    try {
      const content = await fs.readFile(p, 'utf-8');
      const parsed = JSON.parse(content);
      if (!Array.isArray(parsed?.steps)) continue;
      for (const step of parsed.steps) {
        if (step?.type === 'agent') {
          return {
            id: String(step.id ?? ''),
            instruction: String(step.instruction ?? ''),
            output: String(step.output ?? ''),
          };
        }
      }
      // Workflow exists but no agent step (all command/branch/loop) —
      // null out so we don't preload anything.
      return null;
    } catch { /* try next candidate */ }
  }
  return null;
}

/**
 * parity: shell dispatch.sh:1927 — _teammate_flush_from_state.
 *
 * Collect every registered teammate for `teamRef` from the state file,
 * format a single block message containing batched spawn instructions
 * (one block per teammate, name + agent_id + output_dir + sub-workflow).
 * Used by _teammateChainNext when the next step is NOT another teammate
 * (i.e. end of teammate run).
 */
export async function _teammateFlushFromState(
  stateFile: string,
  teamRef: string,
  subWorkflow: string,
): Promise<{ instructions: string; spawned: TeammateSpawnInfo[] }> {
  const state = await stateRead(stateFile);
  const team = state.teams?.[teamRef];
  const teammates = team?.teammates ?? {};
  const names = Object.keys(teammates);
  const spawned: TeammateSpawnInfo[] = [];
  if (names.length === 0) {
    return { instructions: '', spawned };
  }
  // parity: shell dispatch.sh:1989 — emit explicit `bash <PLUGIN>/bin/activate.sh
  // <wf> --as <name>@<team>` instructions. The `--as` flag is what stamps
  // alternate_agent_id on the child, which is the join key for parent-slot
  // updates in archiveWorkflow → stateUpdateParentTeammateSlot.
  const teamName = team?.team_name ?? teamRef;
  // Resolve plugin dir from the workflow definition's source path. Falls back
  // to a heuristic activation command if not available — the harness's
  // wheel:wheel-run skill will supply absolute paths.
  const wfDef = state.workflow_definition;
  const wfStepsArr: ReadonlyArray<{ id: string; type: string; workflow?: string; name?: string }> =
    wfDef?.steps ?? state.steps;
  // Find the teammate step's workflow override; fall back to subWorkflow.
  const stepFor = (name: string): string => {
    const s = wfStepsArr.find((s) => s.type === 'teammate' && (s.id === name || s.name === name));
    return s?.workflow ?? subWorkflow;
  };
  // Prefer env override (consumer-set), fall back to PLUGIN_ROOT derived at
  // module load. Repo-relative `plugin-wheel/bin/...` is the LAST resort —
  // it only works when the orchestrator runs from the repo root.
  const pluginDir = process.env.WORKFLOW_PLUGIN_DIR
    ?? process.env.WHEEL_PLUGIN_DIR
    ?? PLUGIN_ROOT;
  const lines: string[] = [];
  lines.push(`Make these ${names.length} parallel Agent tool calls VERBATIM (copy-paste each block exactly — do not modify any field, do not paraphrase the prompt). The --as flag inside each prompt is what links the child workflow to the parent's teammate slot; without it the workflow will hang at team-wait forever. The PreToolUse guard will block any Agent call whose prompt does not contain the expected --as flag.`);
  lines.push('');
  for (const key of names) {
    const slot = teammates[key];
    if (!slot) continue;
    // The teammate map's key is already in `${name}@${teamName}` form (the
    // agent_id, which `stateAddTeammate` uses as the map key — see
    // state.ts:230). Use slot.agent_id (== key) directly as the team-format
    // ID; appending @teamName again would produce `worker-1@team@team`.
    const teamFmtId = slot.agent_id ?? key;
    const shortName = teamFmtId.endsWith(`@${teamName}`)
      ? teamFmtId.slice(0, -1 - teamName.length)
      : teamFmtId;
    const wf = stepFor(shortName);
    const outdir = slot.output_dir ?? '';
    const activate = pluginDir
      ? `bash ${pluginDir}/bin/activate.sh ${wf} --as ${teamFmtId}`
      : `bash plugin-wheel/bin/activate.sh ${wf} --as ${teamFmtId}`;
    spawned.push({
      name: shortName,
      agent_id: teamFmtId,
      output_dir: outdir,
      workflow: wf,
      task_id: slot.task_id ?? '',
    });
    // Self-contained drive-loop prompt — agent-type-agnostic.
    //
    // Plugin-level wheel hooks (`hooks/hooks.json`) fire in EVERY
    // session including spawned sub-agents (verified empirically by
    // the hookinput-probe — `general-purpose` sub-agents fire the
    // wheel post-tool-use hook on Bash calls). So the wheel doesn't
    // need a dedicated agent type for hooks to work.
    //
    // What `general-purpose` lacks is the agent KNOWLEDGE of how to
    // interpret the wheel's hook signals. Previously we worked around
    // this by spawning `wheel-runner` whose system prompt taught the
    // drive loop. That's a project-local file dependency that doesn't
    // ship with the plugin. Embedding the same knowledge in the spawn
    // prompt makes the wheel agent-type-agnostic.
    //
    // Layout principles:
    //   * activate.sh literal on FIRST line — survives paraphrasing
    //     better than mid-prompt instructions.
    //   * Numbered drive-loop steps so the orchestrator copying the
    //     spawn block verbatim AND the receiving agent reading the
    //     prompt both have a clear ordered protocol.
    //   * Sentinel-file recovery clause for `--print` mode where
    //     Stop-hook additionalContext is dropped (PostToolUse
    //     additionalContext survives, so the issue is Stop only).
    //
    // Idea 5: pre-load the worker with concrete first-step instructions
    // pulled from the sub-workflow JSON's first agent step. Worker can
    // act on it immediately on first wake without waiting for hook
    // signals to interpret. Falls back gracefully when we can't resolve
    // the workflow on disk (consumer install paths vary).
    const firstAgentStep = await _resolveFirstAgentStep(wf);
    // The "drive loop" was originally trigger-based ("when you see a Stop
    // hook block, read the sentinel"). On 3rd-party / non-Anthropic models
    // (verified empirically with MiniMax-M2.7 routed via Bifrost) the
    // trigger is invisible — `claude --print` drops the Stop-hook
    // additionalContext entirely, and the sub-agent has no signal to react
    // to. Symptom: sub-agent activates the sub-workflow but never advances
    // past the first agent step; parent's team-wait polls forever; total
    // run cost spirals into 5-figure dollar territory.
    //
    // Fix: replace the trigger-based loop with an UNCONDITIONAL
    // poll-every-turn obligation. The sentinel file is the only signal;
    // every turn reads it; every turn does what it says. This is the same
    // pattern the harness fixture prompts use for the parent orchestrator
    // and is what works cross-model.
    const concreteFirstStep = firstAgentStep
      ? ` On turn 2 you'll typically need to write content to ${firstAgentStep.output ?? '<output path>'} (the wheel asks for this via the sentinel).`
      : '';
    const promptText =
      `${activate}\n\n` +
      `^^ Turn 1: run the bash command above VERBATIM in a single tool call, then end your turn.\n\n` +
      `You are spawned to drive a wheel sub-workflow. After turn 1, the wheel writes the next tool call to .wheel/.next-instruction.md after every turn.${concreteFirstStep}\n\n` +
      `Every turn after turn 1 (no exceptions, no triggers):\n` +
      `  1. Read({ file_path: ".wheel/.next-instruction.md" })\n` +
      `  2. The file's body contains an EXACT tool-call block, or an instruction like "write {content} to {path}". Issue that call (or write that file) verbatim — copy-paste, don't paraphrase.\n` +
      `  3. End your turn.\n\n` +
      `Termination: stop polling when (a) the sentinel content has the same timestamp as your previous read, AND (b) no .wheel/state_*.json file exists. Then SendMessage("team-lead", "<short status>") and end your turn.\n\n` +
      `Hard rules:\n` +
      `  - Read the sentinel EVERY turn after turn 1, unconditionally. Don't wait for a "trigger" — the sentinel IS the signal.\n` +
      `  - Do NOT call /wheel:wheel-stop or /wheel:wheel-status.\n` +
      `  - Do NOT investigate wheel internals or batch tool calls.\n` +
      `  - If two consecutive sentinel reads return the same timestamp at the top, do NOT re-issue the call — just end your turn.`;
    lines.push('```');
    lines.push('Agent({');
    // Agent-type-agnostic — the prompt above carries the drive-loop
    // knowledge that previously came from the wheel-runner agent's
    // system prompt. Plugin hooks fire regardless of subagent_type
    // (verified by hookinput-probe). general-purpose is fine.
    lines.push(`  subagent_type: "general-purpose",`);
    lines.push(`  description: "${shortName} sub-workflow spawn",`);
    lines.push(`  prompt: ${JSON.stringify(promptText)},`);
    // Architectural Fix — short-name in `name`, NOT the full agent_id.
    //
    // Claude Code mangles `name` + `team_name` → spawned `agent_id` as:
    //   name has NO `@`  →  agent_id = `<name>@<team_name>`
    //   name has `@`     →  every `@` in name becomes `-`, then `@<team>` is appended
    //
    // We register slots with `agent_id = "<short>@<team>"`. Sending the
    // short name here makes Claude Code's mangled spawn agent_id equal
    // the slot agent_id verbatim, which means the spawned sub-agent's
    // own `hookInput.agent_id` IS the linkage key — no prompt round-trip
    // needed. handleActivation falls back to hookInput.agent_id when
    // the activate.sh command has no `--as` flag, so the orchestrator
    // dropping --as via paraphrasing no longer breaks parent-child link.
    lines.push(`  name: "${shortName}",`);
    lines.push(`  team_name: "${teamName}",`);
    // Per-spawn model resolution. Priority order:
    //   1. slot.model — set explicitly via the `teammate` step's `model:`
    //      JSON field (per-step override).
    //   2. process.env.ANTHROPIC_MODEL — the parent orchestrator's model.
    //      Sub-agents (in_process_teammate task type) DO NOT
    //      automatically inherit ANTHROPIC_MODEL from the parent's env;
    //      they fall back to Claude Code's hardcoded default
    //      (`claude-opus-4-7`). When the user routes through a gateway
    //      that doesn't carry that default model — Bifrost, OpenRouter,
    //      a custom proxy — the gateway returns 400 and the sub-agent
    //      silently fails before producing any output. Empirically
    //      verified by inserting a logging proxy between Claude Code
    //      and Bifrost: parent requests went `model:"<env>"` and
    //      succeeded, sub-agent requests went `model:"claude-opus-4-7"`
    //      and got HTTP 400 from Bifrost.
    //   3. otherwise: omit — Claude Code uses its hardcoded default.
    const fallbackModel = process.env.ANTHROPIC_MODEL ?? '';
    const spawnModel = slot.model || fallbackModel;
    if (spawnModel) {
      lines.push(`  model: "${spawnModel}",`);
    }
    lines.push(`  mode: "bypassPermissions"`);
    lines.push('})');
    lines.push('```');
    lines.push('');
  }
  lines.push(`Issue all ${names.length} Agent calls in PARALLEL — single assistant message with ${names.length} tool_use blocks. Do NOT include run_in_background; we want each Agent to run to completion (drive its sub-workflow until archive) before returning. Parallelism comes from multi-tool-use, not from backgrounding. After the message returns ${names.length} tool_results, end your turn. The wheel hooks handle the rest; do not inspect state files.`);
  lines.push('');
  lines.push(`IMPORTANT — anti-duplicate-spawn rule: each Agent({...}) block above is for a UNIQUE registered teammate slot. After you issue these ${names.length} calls and see "Spawned successfully" tool_results for them, the slots are LIVE. Do NOT spawn the same names again on later turns even if a subsequent Stop hook re-shows this same instruction — that would create duplicate workers competing for the same slot. The wheel may re-emit this block while it waits for slot completions; recognize a repeat by the identical agent_ids, end your turn, and let the hooks coordinate.`);
  return { instructions: lines.join('\n'), spawned };
}

/**
 * parity: shell dispatch.sh:1889 — _teammate_chain_next.
 *
 * After a teammate-step marks done:
 *   - if the next step is also `teammate` AND for the same team_ref:
 *     return null (caller continues registering teammates without
 *     emitting a block).
 *   - otherwise: flush all registered teammates from state and emit
 *     a single batched block.
 */
export async function _teammateChainNext(
  workflowSteps: ReadonlyArray<{ id: string; type: string; team?: string; workflow?: string }>,
  stepIndex: number,
  stateFile: string,
  teamRef: string,
  subWorkflow: string,
): Promise<{ instructions: string; spawned: TeammateSpawnInfo[] } | null> {
  const next = workflowSteps[stepIndex + 1];
  if (next && next.type === 'teammate' && (next.team ?? '') === teamRef) {
    // Continue chaining — do not emit yet.
    return null;
  }
  return _teammateFlushFromState(stateFile, teamRef, subWorkflow);
}

/**
 * parity: shell dispatch.sh:1843–1876 — post_tool_use TaskCreate detection.
 *
 * When the orchestrator calls TaskCreate after a teammate spawn block,
 * match the `subject` field to a registered teammate name and update
 * the teammate's task_id. Returns true if a teammate was matched.
 */
export async function teammateMatchTaskCreate(
  stateFile: string,
  teamRef: string,
  toolInput: Record<string, unknown>,
): Promise<boolean> {
  const subject = String((toolInput?.subject as string | undefined) ?? '');
  if (!subject) return false;
  const taskId = String((toolInput?.task_id as string | undefined) ?? '');
  if (!taskId) return false;

  const state = await stateRead(stateFile);
  const team = state.teams?.[teamRef];
  const teammates = team?.teammates ?? {};
  const teamName = team?.team_name ?? '';
  // Match: shell parity used subject.includes(name) on short keys
  // ("worker-1"). With keys now in `name@team` form, also match by the
  // short name (key with `@team` suffix stripped) and by exact equality
  // either way. Three patterns succeed:
  //   1. subject === fullKey OR fullKey === subject
  //   2. subject.includes(shortName) OR shortName === subject
  //   3. fullKey.includes(subject) (substring of `name@team`)
  const match = Object.keys(teammates).find(name => {
    const shortName = teamName && name.endsWith(`@${teamName}`)
      ? name.slice(0, -1 - teamName.length)
      : name;
    return (
      subject === name
      || subject === shortName
      || subject.includes(name)
      || subject.includes(shortName)
      || name.includes(subject)
    );
  });
  if (!match) return false;
  const slot = teammates[match];
  if (!slot) return false;
  slot.task_id = taskId;
  await stateWrite(stateFile, state);
  return true;
}

/**
 * Round-robin assignment — given `agentCount` agents and `items` array,
 * distribute items into agentCount buckets. Used by dispatchTeammate
 * dynamic-spawn loop to populate per-agent `assign` payloads.
 *
 * parity: shell dispatch.sh:1796–1808 — agent_assign distribution.
 */
export function distributeAgentAssign(items: unknown[], agentCount: number): Record<string, unknown[]> {
  const out: Record<string, unknown[]> = {};
  for (let i = 0; i < agentCount; i++) {
    out[String(i)] = [];
  }
  for (let i = 0; i < items.length; i++) {
    const bucket = String(i % agentCount);
    out[bucket].push(items[i]);
  }
  return out;
}

// Re-export WheelState for typing convenience
export type { WheelState };
