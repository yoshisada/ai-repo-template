// dispatchParallel — handles `type: "parallel"` steps.
//
// Stop hook: pending → working, init agent slots, emit "Spawn parallel" block.
// teammate_idle: per-agent state-machine — pending/idle agent → working +
//   emit per-agent instruction.
// subagent_stop: mark agent done; if all agents done → step done + advance.

import type { WorkflowStep } from '../../shared/state.js';
import { stateRead } from '../../shared/state.js';
import { stateSetStepStatus } from '../state.js';
import type { HookInput, HookOutput, HookType } from '../dispatch-types.js';

export async function dispatchParallel(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
): Promise<HookOutput> {
  const stateModule = await import('../state.js');
  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';

  if (hookType === 'stop') {
    if (stepStatus === 'pending') {
      await stateSetStepStatus(stateFile, stepIndex, 'working');
      const agents = (step as any).agents ?? [];
      for (const agent of agents) {
        await stateModule.stateSetAgentStatus(stateFile, stepIndex, agent, 'pending');
      }
    }
    const instruction = (step as any).instruction ?? 'Spawn parallel agents for this step.';
    const agentList = ((step as any).agents ?? []).join(', ');
    return {
      decision: 'block',
      additionalContext: `Spawn these agents in parallel: ${agentList}. ${instruction}`,
    };
  } else if (hookType === 'teammate_idle') {
    const agentType = hookInput.agent_type;
    if (!agentType) return { decision: 'approve' };

    const agentStatus = state.steps[stepIndex]?.agents?.[agentType]?.status;
    if (agentStatus === 'pending' || agentStatus === 'idle') {
      await stateModule.stateSetAgentStatus(stateFile, stepIndex, agentType, 'working');
      const agentInstructions = (step as any).agent_instructions ?? {};
      const agentInstruction = agentInstructions[agentType] ?? (step as any).instruction ?? '';
      return { decision: 'block', additionalContext: agentInstruction };
    }
    return { decision: 'approve' };
  } else if (hookType === 'subagent_stop') {
    const agentType = hookInput.agent_type;
    if (agentType) {
      await stateModule.stateSetAgentStatus(stateFile, stepIndex, agentType, 'done');
    }
    const updatedState = await stateRead(stateFile);
    const agents = updatedState.steps[stepIndex]?.agents ?? {};
    const allDone = Object.values(agents).every((a: any) => a.status === 'done');
    if (allDone) {
      await stateSetStepStatus(stateFile, stepIndex, 'done');
      await stateModule.stateSetCursor(stateFile, stepIndex + 1);
    }
    return { decision: 'approve' };
  }

  return { decision: 'approve' };
}
