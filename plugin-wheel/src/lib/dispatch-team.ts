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
  const wfDef: any = state.workflow_definition ?? {};
  const wfStepsArr: any[] = wfDef.steps ?? state.steps ?? [];
  // Find the teammate step's workflow override; fall back to subWorkflow.
  const stepFor = (name: string): string => {
    const s = wfStepsArr.find((s: any) => s.type === 'teammate' && (s.id === name || s.name === name));
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
    // Build the prompt: (1) activate the sub-workflow, then (2) drive it.
    // The activate-only prompt was a hang trap — sub-agents ran the Bash
    // command, considered their task complete, and went idle. Their child
    // workflow's `do-work` step then never advanced past `pending` because
    // the Stop hook needs *that sub-agent's own turn* to fire, and they
    // never took another turn. JSON.stringify-encoded so the orchestrator
    // sees a literal JS string literal (no newline-escape ambiguity).
    const promptText =
      `You are spawned to run a sub-workflow. Two stages:\n\n` +
      `STAGE 1 — Activate (single tool call): run this exact bash command, then end your turn:\n\n` +
      `${activate}\n\n` +
      `STAGE 2 — Drive the workflow to completion. After activation, the wheel hooks will tell you what to do via Stop-hook block messages with \`additionalContext\` instructions. Loop:\n` +
      `  - End your turn so the Stop hook fires\n` +
      `  - Read the hook's \`additionalContext\` instructions in the next turn\n` +
      `  - Make exactly one tool call per turn following those instructions (Write a file, Bash, etc.)\n` +
      `  - End your turn again\n` +
      `  - Repeat until your sub-workflow's state file is archived (no more wheel state for your agent)\n\n` +
      `Rules:\n` +
      `  - Do NOT paraphrase the activation command in stage 1. Run it verbatim.\n` +
      `  - Do NOT run /wheel:wheel-run; the activation above is the correct entry point.\n` +
      `  - Do NOT investigate wheel internals. The hooks are authoritative.\n` +
      `  - When asked to write an output file, write it with whatever stub content fits (content quality is not checked, only existence).\n` +
      `  - When the hooks stop emitting block instructions and your state file is gone, your work is done. Send a SendMessage to "team-lead" reporting completion, then end your turn.`;
    lines.push('```');
    lines.push('Agent({');
    lines.push(`  subagent_type: "general-purpose",`);
    lines.push(`  description: "${shortName} sub-workflow spawn",`);
    lines.push(`  prompt: ${JSON.stringify(promptText)},`);
    lines.push(`  name: "${shortName}",`);
    lines.push(`  team_name: "${teamName}",`);
    lines.push(`  mode: "bypassPermissions"`);
    lines.push('})');
    lines.push('```');
    lines.push('');
  }
  lines.push(`Issue all ${names.length} Agent calls in PARALLEL — single assistant message with ${names.length} tool_use blocks. Do NOT include run_in_background; we want each Agent to run to completion (drive its sub-workflow until archive) before returning. Parallelism comes from multi-tool-use, not from backgrounding. After the message returns ${names.length} tool_results, end your turn. The wheel hooks handle the rest; do not inspect state files.`);
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
