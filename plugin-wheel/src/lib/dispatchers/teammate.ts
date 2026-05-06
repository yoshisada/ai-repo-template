// dispatchTeammate — handles `type: "teammate"` steps (spawn one agent
// per teammate slot to run a sub-workflow).
//
// Two paths:
//   - `loop_from`: dynamic distribution. Read JSON array from referenced
//     step's output, round-robin distribute across `max_agents` slots.
//   - static: single teammate slot, `step.assign` is its payload.
//
// Each teammate slot's `agent_id` is in `${name}@${team_name}` format —
// the join key for parent slot updates in `stateUpdateParentTeammateSlot`
// (matched against the child workflow's `alternate_agent_id` stamped by
// the child's `--as` flag).
//
// Stop hook: pending → working, register all slots, mark done immediately
// (fire-and-forget), call `_teammateChainNext` to either chain to next
// teammate step (return null → continue) or flush + emit batched spawn
// block (return instructions → block).
//
// PostToolUse (TaskCreate tool): match `subject` to a teammate name and
// update its `task_id`.
//
// FR-025 / FR-026.

import type {
  WorkflowStep, TeammateEntry, TeammateModel, WheelState, WorkflowDefinition,
} from '../../shared/state.js';
import { stateRead } from '../../shared/state.js';
import { stateSetStepStatus, stateAddTeammate } from '../state.js';
import type { HookInput, HookOutput, HookType } from '../dispatch-types.js';

// Step-type-specific fields read from the `teammate` step JSON. Modeled
// once here so dispatchers cast the step shape at the boundary instead
// of reaching for `(step as any).<field>` at every read site.
interface TeammateStepFields {
  team?: string;
  workflow?: string;
  loop_from?: string;
  max_agents?: number;
  name?: string;
  context_from?: unknown[];
  assign?: unknown;
  // Per-slot model override (sonnet | opus | haiku). When set, every
  // teammate slot registered by this step inherits this model and the
  // emitted Agent call carries `model: "<value>"`. Omitted → spawned
  // sub-agent inherits the parent orchestrator's model (Claude Code's
  // default Agent-tool behaviour).
  model?: TeammateModel;
}

export async function dispatchTeammate(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
): Promise<HookOutput> {
  const sf = step as WorkflowStep & TeammateStepFields;

  // PostToolUse: TaskCreate detection (parity: shell dispatch.sh:1843–1876).
  if (hookType === 'post_tool_use') {
    if (hookInput.tool_name === 'TaskCreate') {
      const teamRef = sf.team;
      if (teamRef) {
        const teamModule = await import('../dispatch-team.js');
        await teamModule.teammateMatchTaskCreate(
          stateFile, teamRef,
          (hookInput.tool_input ?? {}) as Record<string, unknown>,
        );
      }
    }
    return { decision: 'approve' };
  }

  if (hookType !== 'stop') return { decision: 'approve' };

  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';
  if (stepStatus !== 'pending') return { decision: 'approve' };

  await stateSetStepStatus(stateFile, stepIndex, 'working');

  const teamRef = sf.team;
  const subWorkflow = sf.workflow ?? '';
  const loopFrom = sf.loop_from;
  const maxAgents = sf.max_agents ?? 5;
  const agentName = sf.name ?? step.id;

  if (!teamRef) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    return { decision: 'approve' };
  }
  const teamName = state.teams?.[teamRef]?.team_name;
  if (!teamName) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    return { decision: 'approve' };
  }

  const slotPayloads = loopFrom
    ? await buildDynamicSlots(stateFile, stepIndex, state, agentName, loopFrom, maxAgents)
    : [{ name: agentName, assign: ((sf.assign ?? {}) as Record<string, unknown>) }];

  // buildDynamicSlots returns null on early-fail/empty paths it has
  // already resolved (it sets step status itself). Plain return.
  if (slotPayloads === null) return { decision: 'approve' };
  if (slotPayloads.length === 0) {
    await stateSetStepStatus(stateFile, stepIndex, 'done');
    return { decision: 'approve' };
  }

  return spawnTeammates(step, stateFile, stepIndex, teamRef, teamName, subWorkflow, state, slotPayloads, sf.model);
}

interface SlotPayload {
  name: string;
  assign: Record<string, unknown>;
}

/**
 * Resolve a `loop_from` reference into N round-robin slot payloads.
 * Returns null when the loop step / output is unresolvable (status set
 * to 'failed'), or [] when items are present but empty (caller marks
 * the step done).
 */
async function buildDynamicSlots(
  stateFile: string,
  stepIndex: number,
  state: WheelState,
  agentName: string,
  loopFrom: string,
  maxAgents: number,
): Promise<SlotPayload[] | null> {
  const loopStepIndex = state.steps.findIndex((s) => s.id === loopFrom);
  if (loopStepIndex === -1) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    return null;
  }

  // Output file path comes from the workflow DEFINITION's `output` field
  // for the referenced step — not state.steps[i].output (captured stdout).
  // Fall back to state.output only when workflow_definition is absent.
  const wfStepsForLoop = state.workflow_definition?.steps ?? [];
  const loopStepDef = wfStepsForLoop.find((s) => s.id === loopFrom);
  const loopOutput = (loopStepDef?.output as string | null)
    ?? (state.steps[loopStepIndex]?.output as string | null);
  if (!loopOutput) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    return null;
  }

  const items = await readJsonArray(loopOutput);
  if (items === null) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    return null;
  }
  if (items.length === 0) return [];

  const agentCount = Math.min(items.length, maxAgents);
  const teamModule = await import('../dispatch-team.js');
  // parity: shell dispatch.sh:1796–1808 — round-robin agent_assign distribution.
  const distribution = teamModule.distributeAgentAssign(items, agentCount);
  const slots: SlotPayload[] = [];
  for (let i = 0; i < agentCount; i++) {
    slots.push({
      name: `${agentName}-${i}`,
      assign: { items: distribution[String(i)] ?? [] },
    });
  }
  return slots;
}

async function readJsonArray(filePath: string): Promise<unknown[] | null> {
  try {
    const { readFile } = await import('fs/promises');
    const parsed = JSON.parse(await readFile(filePath, 'utf-8'));
    return Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

/**
 * Register N teammate slots, write per-slot context files, mark step
 * done, and chain to the next teammate step (or flush + emit batched
 * spawn block). Shared between static (1 slot) and dynamic (N slots)
 * paths.
 */
async function spawnTeammates(
  step: WorkflowStep,
  stateFile: string,
  stepIndex: number,
  teamRef: string,
  teamName: string,
  subWorkflow: string,
  state: WheelState,
  slots: SlotPayload[],
  model: TeammateModel | undefined,
): Promise<HookOutput> {
  const contextModule = await import('../context.js');
  const teamModule = await import('../dispatch-team.js');
  // Fallback when workflow_definition isn't loaded: synthesize one from
  // state.steps. The cast is safe — Step extends the workflow-step shape
  // at runtime via stateInit's spread, so the only nominal mismatch
  // (`agents`) is unused by the consumer.
  const wfDef: WorkflowDefinition = state.workflow_definition
    ?? ({ name: state.workflow_name, version: state.workflow_version, steps: state.steps } as unknown as WorkflowDefinition);
  const contextFromJson: unknown[] = (step as WorkflowStep & TeammateStepFields).context_from ?? [];

  for (const slot of slots) {
    const outputDir = `.wheel/outputs/team-${teamName}/${slot.name}`;
    // parity: shell dispatch.sh:2082 — agent_id is team-format `name@team`.
    const teammate: TeammateEntry = {
      task_id: '', status: 'pending',
      agent_id: `${slot.name}@${teamName}`,
      output_dir: outputDir,
      assign: slot.assign,
      started_at: null, completed_at: null,
      ...(model ? { model } : {}),
    };
    await stateAddTeammate(stateFile, teamRef, teammate);
    try {
      await contextModule.contextWriteTeammateFiles(outputDir, state, wfDef, contextFromJson, slot.assign);
    } catch { /* FS errors non-fatal */ }
  }

  await stateSetStepStatus(stateFile, stepIndex, 'done');
  const wfStepsArr = wfDef?.steps ?? state.steps;
  const chainResult = await teamModule._teammateChainNext(wfStepsArr, stepIndex, stateFile, teamRef, subWorkflow);
  if (chainResult === null) return { decision: 'approve' };

  const fallback = slots.length === 1
    ? `Spawned agent: ${slots[0].name} for ${subWorkflow}`
    : `Spawned ${slots.length} agents for ${subWorkflow}`;
  return {
    decision: 'block',
    additionalContext: chainResult.instructions || fallback,
  };
}
