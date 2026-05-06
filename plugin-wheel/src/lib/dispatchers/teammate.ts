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

import type { WorkflowStep, TeammateEntry } from '../../shared/state.js';
import { stateRead } from '../../shared/state.js';
import { stateSetStepStatus } from '../state.js';
import type { HookInput, HookOutput, HookType } from '../dispatch-types.js';

export async function dispatchTeammate(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
): Promise<HookOutput> {
  // PostToolUse: TaskCreate detection (parity: shell dispatch.sh:1843–1876).
  if (hookType === 'post_tool_use') {
    if (hookInput.tool_name === 'TaskCreate') {
      const teamRef = (step as any).team;
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

  const teamRef = (step as any).team;
  const subWorkflow = (step as any).workflow;
  const loopFrom = (step as any).loop_from;
  const maxAgents = (step as any).max_agents ?? 5;
  const agentName = (step as any).name ?? step.id;

  const teamName = state.teams?.[teamRef]?.team_name;
  if (!teamName) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    return { decision: 'approve' };
  }

  if (loopFrom) {
    return spawnDynamic(step, stateFile, stepIndex, teamRef, teamName, agentName, loopFrom, maxAgents, subWorkflow, state);
  }
  return spawnStatic(step, stateFile, stepIndex, teamRef, teamName, agentName, subWorkflow, state);
}

async function spawnDynamic(
  step: WorkflowStep,
  stateFile: string,
  stepIndex: number,
  teamRef: string,
  teamName: string,
  agentName: string,
  loopFrom: string,
  maxAgents: number,
  subWorkflow: string,
  state: any,
): Promise<HookOutput> {
  const stateModule = await import('../state.js');
  const loopStepIndex = state.steps.findIndex((s: any) => s.id === loopFrom);
  if (loopStepIndex === -1) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    return { decision: 'approve' };
  }

  // Output file path comes from the workflow DEFINITION's `output` field
  // for the referenced step — not state.steps[i].output (captured stdout).
  // Fall back to state.output only when workflow_definition is absent.
  const wfDefForLoop: any = state.workflow_definition;
  const wfStepsForLoop: any[] = wfDefForLoop?.steps ?? [];
  const loopStepDef = wfStepsForLoop.find((s: any) => s.id === loopFrom);
  const loopOutput = (loopStepDef?.output as string | null)
    ?? (state.steps[loopStepIndex]?.output as string | null);
  if (!loopOutput) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    return { decision: 'approve' };
  }

  let items: any[] = [];
  try {
    const { readFile } = await import('fs/promises');
    items = JSON.parse(await readFile(loopOutput, 'utf-8'));
  } catch {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    return { decision: 'approve' };
  }
  if (!Array.isArray(items)) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    return { decision: 'approve' };
  }
  if (items.length === 0) {
    await stateSetStepStatus(stateFile, stepIndex, 'done');
    return { decision: 'approve' };
  }

  const agentCount = Math.min(items.length, maxAgents);
  const teamModule = await import('../dispatch-team.js');
  // parity: shell dispatch.sh:1796–1808 — round-robin agent_assign distribution.
  const distribution = teamModule.distributeAgentAssign(items, agentCount);
  const contextModule = await import('../context.js');
  const wfDef: any = state.workflow_definition
    ?? { name: state.workflow_name, version: state.workflow_version, steps: state.steps };
  const contextFromJson: unknown[] = (step as any).context_from ?? [];

  for (let i = 0; i < agentCount; i++) {
    const name = `${agentName}-${i}`;
    const outputDir = `.wheel/outputs/team-${teamName}/${name}`;
    const assignJson = { items: distribution[String(i)] ?? [] };
    // parity: shell dispatch.sh:2082 — agent_id is team-format `name@team`.
    const teammate: TeammateEntry = {
      task_id: '', status: 'pending',
      agent_id: `${name}@${teamName}`,
      output_dir: outputDir,
      assign: assignJson,
      started_at: null, completed_at: null,
    };
    await stateModule.stateAddTeammate(stateFile, teamRef, teammate);
    try {
      await contextModule.contextWriteTeammateFiles(outputDir, state, wfDef, contextFromJson, assignJson);
    } catch { /* FS errors non-fatal */ }
  }

  await stateSetStepStatus(stateFile, stepIndex, 'done');
  const wfStepsArr = wfDef?.steps ?? state.steps;
  const chainResult = await teamModule._teammateChainNext(wfStepsArr, stepIndex, stateFile, teamRef, subWorkflow);
  if (chainResult === null) return { decision: 'approve' };
  return {
    decision: 'block',
    additionalContext: chainResult.instructions || `Spawned ${agentCount} agents for ${subWorkflow}`,
  };
}

async function spawnStatic(
  step: WorkflowStep,
  stateFile: string,
  stepIndex: number,
  teamRef: string,
  teamName: string,
  agentName: string,
  subWorkflow: string,
  state: any,
): Promise<HookOutput> {
  const stateModule = await import('../state.js');
  const outputDir = `.wheel/outputs/team-${teamName}/${agentName}`;
  const assignJson = (step as any).assign ?? {};
  // parity: shell dispatch.sh:2082 — agent_id is team-format `name@team`.
  const teammate: TeammateEntry = {
    task_id: '', status: 'pending',
    agent_id: `${agentName}@${teamName}`,
    output_dir: outputDir,
    assign: assignJson,
    started_at: null, completed_at: null,
  };
  await stateModule.stateAddTeammate(stateFile, teamRef, teammate);

  const contextModule = await import('../context.js');
  const wfDef: any = state.workflow_definition
    ?? { name: state.workflow_name, version: state.workflow_version, steps: state.steps };
  const contextFromJson: unknown[] = (step as any).context_from ?? [];
  try {
    await contextModule.contextWriteTeammateFiles(outputDir, state, wfDef, contextFromJson, assignJson);
  } catch { /* non-fatal */ }

  await stateSetStepStatus(stateFile, stepIndex, 'done');
  const teamModule = await import('../dispatch-team.js');
  const wfStepsArr = wfDef?.steps ?? state.steps;
  const chainResult = await teamModule._teammateChainNext(wfStepsArr, stepIndex, stateFile, teamRef, subWorkflow);
  if (chainResult === null) return { decision: 'approve' };
  return {
    decision: 'block',
    additionalContext: chainResult.instructions || `Spawned agent: ${agentName} for ${subWorkflow}`,
  };
}
