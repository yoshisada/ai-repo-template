// dispatchParallel — handles `type: "parallel"` steps.
//
// Stop hook: pending → working, init agent slots, emit "Spawn parallel" block.
// teammate_idle: per-agent state-machine — pending/idle agent → working +
//   emit per-agent instruction.
// subagent_stop: mark agent done; if all agents done → step done + advance.

import type { WorkflowStep } from '../../shared/state.js';
import { stateRead } from '../../shared/state.js';
import { stateSetStepStatus, stateSetAgentStatus, stateSetCursor } from '../state.js';
import type { HookInput, HookOutput, HookType } from '../dispatch-types.js';

interface ParallelStepFields {
  agents?: string[];
  instruction?: string;
  agent_instructions?: Record<string, string>;
}

export async function dispatchParallel(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
): Promise<HookOutput> {

  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';
  const pf = step as WorkflowStep & ParallelStepFields;

  if (hookType === 'stop') {
    if (stepStatus === 'pending') {
      await stateSetStepStatus(stateFile, stepIndex, 'working');
      const agents = pf.agents ?? [];
      for (const agent of agents) {
        await stateSetAgentStatus(stateFile, stepIndex, agent, 'pending');
      }
    }
    const instruction = pf.instruction ?? 'Spawn parallel agents for this step.';
    const agentList = (pf.agents ?? []).join(', ');
    return {
      decision: 'block',
      additionalContext: `Spawn these agents in parallel: ${agentList}. ${instruction}`,
    };
  } else if (hookType === 'teammate_idle') {
    const agentType = hookInput.agent_type;
    if (!agentType) return { decision: 'approve' };

    const agentStatus = state.steps[stepIndex]?.agents?.[agentType]?.status;
    if (agentStatus === 'pending' || agentStatus === 'idle') {
      await stateSetAgentStatus(stateFile, stepIndex, agentType, 'working');
      const agentInstructions = pf.agent_instructions ?? {};
      const agentInstruction = agentInstructions[agentType] ?? pf.instruction ?? '';
      return { decision: 'block', additionalContext: agentInstruction };
    }
    return { decision: 'approve' };
  } else if (hookType === 'subagent_stop') {
    const agentType = hookInput.agent_type;
    if (agentType) {
      await stateSetAgentStatus(stateFile, stepIndex, agentType, 'done');
    }
    const updatedState = await stateRead(stateFile);
    const agents = updatedState.steps[stepIndex]?.agents ?? {};
    const allDone = Object.values(agents).every((a) => a.status === 'done');
    if (allDone) {
      await stateSetStepStatus(stateFile, stepIndex, 'done');
      await stateSetCursor(stateFile, stepIndex + 1);
    }
    return { decision: 'approve' };
  }

  return { decision: 'approve' };
}
