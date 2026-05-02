// FR-006 — team-primitive helpers extracted from dispatch.ts to keep the
// dispatcher under the 500-line cap (Constitution Article VI).
// All exports here are direct ports of the matching shell functions
// (parity references inline). Module-private helpers prefix _.

import { stateRead, stateWrite } from '../shared/state.js';
import type { WheelState, TeammateEntry } from '../shared/state.js';
import { wheelLog } from './log.js';

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
  const lines: string[] = [];
  if (names.length === 0) {
    return { instructions: '', spawned };
  }
  lines.push(`Spawn the following teammates as part of team "${team?.team_name ?? teamRef}":`);
  lines.push('');
  for (const name of names) {
    const slot = teammates[name];
    if (!slot) continue;
    spawned.push({
      name,
      agent_id: slot.agent_id ?? name,
      output_dir: slot.output_dir ?? '',
      workflow: subWorkflow,
      task_id: slot.task_id ?? '',
    });
    lines.push(`- name: ${name}`);
    lines.push(`  agent_id: ${slot.agent_id ?? name}`);
    lines.push(`  output_dir: ${slot.output_dir ?? ''}`);
    lines.push(`  workflow: ${subWorkflow}`);
  }
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
 * parity: shell dispatch.sh:2248 — _team_wait_complete.
 *
 * Finalise a `team-wait` step: collect all teammate outputs into the
 * wait step's output path as `summary.json`. If `step.collect_to` is
 * set (a directory), copy each teammate's output_dir contents into
 * <collect_to>/<teammate_name>/.
 *
 * Idempotent: if the wait step has no `output` field set, skip
 * summary.json write (matches shell behaviour where the field is
 * optional).
 */
export async function _teamWaitComplete(
  step: { output?: string; collect_to?: string },
  stateFile: string,
  _stepIndex: number,
  teamRef: string,
): Promise<void> {
  const { promises: fs } = await import('fs');
  const path = (await import('path')).default;
  const state = await stateRead(stateFile);
  const team = state.teams?.[teamRef];
  if (!team) return;
  const teammates = team.teammates ?? {};

  const summary: Record<string, unknown> = {};
  for (const [name, slot] of Object.entries(teammates)) {
    const tm = slot as TeammateEntry;
    summary[name] = {
      agent_id: tm.agent_id ?? name,
      status: tm.status,
      output_dir: tm.output_dir ?? null,
      task_id: tm.task_id ?? null,
      started_at: (tm as any).started_at ?? null,
      completed_at: (tm as any).completed_at ?? null,
    };
  }

  // FR-006 A5 — write summary.json
  const outputPath = step.output;
  if (outputPath) {
    try {
      await fs.mkdir(path.dirname(outputPath), { recursive: true });
      await fs.writeFile(outputPath, JSON.stringify(summary, null, 2) + '\n');
    } catch (err) {
      await wheelLog('team_wait_complete_summary_error', {
        state_file: stateFile,
        error: String(err instanceof Error ? err.message : err),
      });
    }
  }

  // FR-006 A6 — collect_to copy: copy each teammate's output_dir contents
  // into <collect_to>/<teammate_name>/.
  const collectTo = step.collect_to;
  if (collectTo) {
    for (const [name, slot] of Object.entries(teammates)) {
      const tm = slot as TeammateEntry;
      const src = tm.output_dir;
      if (!src) continue;
      const dest = path.join(collectTo, name);
      try {
        await fs.mkdir(dest, { recursive: true });
        const entries = await fs.readdir(src, { withFileTypes: true });
        for (const ent of entries) {
          const sp = path.join(src, ent.name);
          const dp = path.join(dest, ent.name);
          if (ent.isFile()) {
            await fs.copyFile(sp, dp);
          }
        }
      } catch (err) {
        await wheelLog('team_wait_complete_collect_error', {
          teammate: name,
          error: String(err instanceof Error ? err.message : err),
        });
      }
    }
  }
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
  // Match by exact name OR by name appearing inside subject (shell uses
  // substring match so `subject="research/baseline"` finds teammate
  // named "baseline").
  const match = Object.keys(teammates).find(name => subject === name || subject.includes(name));
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
