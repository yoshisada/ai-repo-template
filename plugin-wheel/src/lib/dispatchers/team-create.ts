// dispatchTeamCreate — handles `type: "team-create"` steps.
//
// Stop hook (pending): if team already registered → done + approve.
//   else → working, emit literal `TeamCreate({...})` block (verbatim).
// Stop hook (working): re-emit the same TeamCreate JSON (idempotent).
// PostToolUse (TeamCreate tool): register team in state.teams[stepId],
//   mark step done, cascade into next auto-executable step.
//
// Note: post_tool_use accepts both `pending` AND `working` because in
// --print and other harnesses the orchestrator can call TeamCreate in
// the same turn as activation — before any Stop fires the transition.
//
// FR-025.

import type { WorkflowStep } from '../../shared/state.js';
import { stateRead } from '../../shared/state.js';
import { stateSetStepStatus } from '../state.js';
import type { HookInput, HookOutput, HookType } from '../dispatch-types.js';

export async function dispatchTeamCreate(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
): Promise<HookOutput> {
  const stateModule = await import('../state.js');
  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';
  const stepId = step.id;
  const teamName = (step.team_name as string | undefined) ?? `${state.workflow_name}-${stepId}`;

  if (hookType === 'stop') {
    if (stepStatus === 'pending') {
      const existingTeam = state.teams?.[stepId]?.team_name;
      if (existingTeam) {
        await stateSetStepStatus(stateFile, stepIndex, 'done');
        return { decision: 'approve' };
      }
      await stateSetStepStatus(stateFile, stepIndex, 'working');
      return {
        decision: 'block',
        additionalContext: `Make this exact TeamCreate tool call (copy-paste verbatim — do not change team_name):\n\n\`\`\`\nTeamCreate({\n  team_name: ${JSON.stringify(teamName)},\n  description: ${JSON.stringify(`Team for workflow ${state.workflow_name ?? stepId}`)}\n})\n\`\`\`\n\nThe PreToolUse guard will block any TeamCreate call whose team_name does not match. After issuing the call, end your turn.`,
      };
    } else if (stepStatus === 'working') {
      return {
        decision: 'block',
        additionalContext: `Still waiting for TeamCreate. Re-issue this exact call:\n\n\`\`\`\nTeamCreate({\n  team_name: ${JSON.stringify(teamName)},\n  description: ${JSON.stringify(`Team for workflow ${state.workflow_name ?? stepId}`)}\n})\n\`\`\``,
      };
    }
    return { decision: 'approve' };
  } else if (hookType === 'post_tool_use') {
    if (stepStatus === 'pending' || stepStatus === 'working') {
      if (hookInput.tool_name === 'TeamCreate') {
        await stateModule.stateSetTeam(stateFile, stepId, teamName);
        await stateSetStepStatus(stateFile, stepIndex, 'done');
        // parity: shell dispatch.sh:1669–1673 — cascade into next auto-executable step.
        const dispatchModule = await import('../dispatch.js');
        return dispatchModule.cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, 0);
      }
    }
    return { decision: 'approve' };
  }

  return { decision: 'approve' };
}
