// Wait-all helpers used by `dispatchers/team-wait.ts`.
//
// These functions are pure read-then-act helpers: they look at child
// state files + parent teammate slots and either build instruction
// strings (progress snapshot, wake-up block) or advance auto-executable
// child steps in place.
//
// FR-001 / FR-003 / FR-009 (wheel-wait-all-redesign).

import { stateRead, listLiveStateFiles } from '../shared/state.js';
import type { TeammateEntry, WheelState, WorkflowStep } from '../shared/state.js';
import type { HookInput } from './dispatch-types.js';
import { wheelLog } from './log.js';

export async function _teamWaitProgressSnapshot(
  parentStateFile: string,
  teamRef: string,
): Promise<{ snapshot: string; hasPendingSlots: boolean; totalSlots: number }> {
  const parentState = await stateRead(parentStateFile);
  const teammates = parentState.teams?.[teamRef]?.teammates ?? {};
  const totalSlots = Object.keys(teammates).length;
  const hasPendingSlots = Object.values(teammates).some(
    (slot) => slot && slot.status === 'pending'
  );

  // Index live child state files once by alternate_agent_id / owner_agent_id.
  const childByAgent: Record<string, any> = {};
  for (const { path: candidate } of await listLiveStateFiles()) {
    if (candidate === parentStateFile) continue;
    try {
      const cs = await stateRead(candidate);
      const alt = cs.alternate_agent_id ?? '';
      const own = cs.owner_agent_id ?? '';
      if (alt) childByAgent[alt] = { state: cs, file: candidate };
      if (own && own !== alt) childByAgent[own] = { state: cs, file: candidate };
    } catch { /* skip */ }
  }

  let completed = 0, failed = 0, running = 0;
  const lines: string[] = [];
  for (const [name, slot] of Object.entries(teammates)) {
    const s = slot as TeammateEntry;
    if (s.status === 'completed') completed++;
    else if (s.status === 'failed') failed++;
    else if (s.status === 'running') running++;
    const child = childByAgent[s.agent_id ?? name];
    let detail = '';
    if (child) {
      const csCursor = child.state.cursor ?? 0;
      const csSteps = child.state.steps ?? [];
      const csStep = csSteps[csCursor];
      detail = ` — child workflow live: cursor=${csCursor} step=${csStep?.id ?? '?'} type=${csStep?.type ?? '?'} status=${csStep?.status ?? '?'}`;
    } else if (s.status === 'pending') {
      detail = ' — child workflow not yet activated';
    } else if (s.status === 'completed' || s.status === 'failed') {
      detail = ' — child workflow archived';
    }
    lines.push(`  - slot "${name}" (agent_id=${s.agent_id ?? name}, slot_status=${s.status})${detail}`);
  }
  const header = `Progress: ${completed}/${totalSlots} completed, ${failed} failed, ${running} running, ${totalSlots - completed - failed - running} other.`;
  return { snapshot: [header, ...lines].join('\n'), hasPendingSlots, totalSlots };
}

/**
 * Compute the wake-up block for an idle teammate whose child workflow is
 * blocked at an agent step (waiting for them to produce output). Returns
 * the block's additionalContext text, or null if no wake is needed (child
 * is at a different step type, archived, or never linked back to parent).
 *
 * The orchestrator gets a literal `SendMessage({to, message})` to copy-
 * paste, eliminating interpretation room.
 */
export async function _teamWaitBuildWakeBlock(
  idleAgentId: string,
  idleName: string,
  idleTeamName: string,
  childStateFile: string,
  childState: WheelState,
): Promise<string | null> {
  const childCursor = childState.cursor ?? 0;
  const childWfDef = childState.workflow_definition;
  const childWfSteps: WorkflowStep[] = childWfDef?.steps ?? [];
  const childStateSteps = childState.steps ?? [];
  const childStepDef = childWfSteps[childCursor];
  const childStepState = childStateSteps[childCursor];
  if (!childStepDef && !childStepState) return null;
  const childStep = { ...(childStepDef ?? {}), ...(childStepState ?? {}) };
  const childStepType = childStepDef?.type ?? childStepState?.type ?? '';
  const childStepStatus = childStateSteps[childCursor]?.status ?? 'pending';
  const childStepInstr = childStepDef?.instruction ?? childStep.instruction;
  const childStepOutput = childStepDef?.output ?? childStep.output;

  if (!(childStepType === 'agent' && (childStepStatus === 'pending' || childStepStatus === 'working'))) {
    return null;
  }
  const instruction = childStepInstr ?? `Execute step "${childStep.id}" of your sub-workflow.`;
  const outputPath = childStepOutput ?? '';
  const wakeMessage =
    `Continue your sub-workflow. Current step: ${childStep.id} (agent, status: ${childStepStatus}). ` +
    `${instruction} ` +
    (outputPath
      ? `Write your output to: ${outputPath}. After writing, end your turn so the wheel hooks can advance the workflow.`
      : `End your turn after producing the output so the wheel hooks can advance.`);
  const recipient = idleAgentId || idleName;
  void idleTeamName; // currently unused but reserved for richer messaging
  void childStateFile;
  return (
    `Teammate "${recipient}" is idle but their sub-workflow is blocked at an agent step (${childStep.id}). Wake them by issuing this exact tool call:\n\n` +
    '```\n' +
    `SendMessage({\n` +
    `  to: ${JSON.stringify(recipient)},\n` +
    `  message: ${JSON.stringify(wakeMessage)}\n` +
    `})\n` +
    '```\n\n' +
    `After the teammate processes the message, they'll write their output file and end their turn. The team-wait step will then detect the archive and advance.`
  );
}

/**
 * Given a child state file at a pending command/loop/branch step, drive
 * it forward by calling dispatchStep('stop'). Returns true if a step was
 * advanced, false if the child wasn't at an auto-executable pending step.
 *
 * Used by the parent's TeammateIdle dispatcher when a teammate's child
 * workflow needs its terminal command step run but the sub-agent's
 * session is gone (Agent tool call returned).
 */
export async function _teamWaitAdvanceChildIfAuto(
  childStateFile: string,
  childState: WheelState,
  hookInput: HookInput,
): Promise<boolean> {
  const childCursor = childState.cursor ?? 0;
  const childWfDef = childState.workflow_definition;
  const childWfSteps: WorkflowStep[] = childWfDef?.steps ?? [];
  const childStateSteps = childState.steps ?? [];
  const childStepDef = childWfSteps[childCursor];
  const childStepState = childStateSteps[childCursor];
  if (!childStepDef && !childStepState) return false;
  const childStep = { ...(childStepDef ?? {}), ...(childStepState ?? {}) };
  const childStepType = childStepDef?.type ?? childStepState?.type ?? '';
  const childStepStatus = childStateSteps[childCursor]?.status ?? 'pending';
  if (!(childStepType === 'command' || childStepType === 'loop' || childStepType === 'branch')) {
    return false;
  }
  if (childStepStatus !== 'pending') return false;
  await wheelLog('dispatch_teammate_idle_advance_child', {
    child_state_file: childStateFile,
    child_step_id: childStep.id,
    child_step_type: childStepType,
  });
  const dispatchModule = await import('./dispatch.js');
  await dispatchModule.dispatchStep(childStep as unknown as WorkflowStep, 'stop', hookInput, childStateFile, childCursor, 0);
  const engineModule = await import('./engine.js');
  await engineModule.maybeArchiveAfterActivation(childStateFile);
  return true;
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
      started_at: tm.started_at ?? null,
      completed_at: tm.completed_at ?? null,
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
