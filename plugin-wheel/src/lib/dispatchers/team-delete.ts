// dispatchTeamDelete — handles `type: "team-delete"` steps.
//
// Stop hook (pending): emit literal `TeamDelete({...})` block; warn if
//   any teammate is still running.
// Stop hook (working): re-emit (idempotent).
// PostToolUse (TeamDelete tool): remove team, mark step done, cascade.
//   Honors `terminal: true` by setting state.status='completed'.
//
// parity: shell dispatch.sh:2375.

import type { WorkflowStep } from '../../shared/state.js';
import { stateRead, stateWrite } from '../../shared/state.js';
import { stateSetStepStatus } from '../state.js';
import type { HookInput, HookOutput, HookType } from '../dispatch-types.js';

export async function dispatchTeamDelete(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
): Promise<HookOutput> {
  const stateModule = await import('../state.js');
  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';
  const teamRef = step.team as string | undefined;
  const teamName = teamRef ? state.teams?.[teamRef]?.team_name : undefined;
  const dispatchModule = await import('../dispatch.js');
  const cascadeNext = dispatchModule.cascadeNext;

  if (hookType === 'stop') {
    if (stepStatus === 'pending') {
      // parity: shell dispatch.sh:2399 — idempotency. Team already gone → advance.
      if (!teamName) {
        await stateSetStepStatus(stateFile, stepIndex, 'done');
        return cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, 0);
      }
      await stateSetStepStatus(stateFile, stepIndex, 'working');
      // parity: shell dispatch.sh:2421–2434 — block w/ shutdown + TeamDelete.
      const teammates = state.teams?.[teamRef!]?.teammates ?? {};
      const stillRunning = Object.entries(teammates)
        .filter(([, slot]) => slot?.status === 'running' || slot?.status === 'pending')
        .map(([name]) => name);
      const forceMsg = stillRunning.length > 0
        ? `\n\nWARNING: These teammates are still active and must be force-terminated first: ${stillRunning.join(', ')}. Send shutdown requests via SendMessage before calling TeamDelete.`
        : '';
      return {
        decision: 'block',
        additionalContext: `Make this exact TeamDelete tool call:\n\n\`\`\`\nTeamDelete({\n  team_name: ${JSON.stringify(teamName)}\n})\n\`\`\`${forceMsg}\n\nThe PreToolUse guard will block any TeamDelete call whose team_name does not match. After issuing the call, end your turn.`,
      };
    } else if (stepStatus === 'working') {
      return {
        decision: 'block',
        additionalContext: `Still waiting for TeamDelete. Re-issue this exact call:\n\n\`\`\`\nTeamDelete({\n  team_name: ${JSON.stringify(teamName ?? teamRef ?? '')}\n})\n\`\`\``,
      };
    }
    return { decision: 'approve' };
  }

  if (hookType === 'post_tool_use') {
    // Accept TeamDelete in pending OR working — orchestrators may issue
    // the call before the Stop hook flips pending → working.
    if (stepStatus === 'pending' || stepStatus === 'working') {
      if (hookInput.tool_name === 'TeamDelete') {
        if (teamRef) await stateModule.stateRemoveTeam(stateFile, teamRef);
        await stateSetStepStatus(stateFile, stepIndex, 'done');
        // parity: shell dispatch.sh:2453–2458 — terminal step archive trigger.
        if (step.terminal === true) {
          const fresh = await stateRead(stateFile);
          await stateWrite(stateFile, { ...fresh, status: 'completed' as const });
          return { hookEventName: 'PostToolUse' };
        }
        // parity: shell dispatch.sh:2461–2480 — advance + cascade.
        return cascadeNext('stop', hookInput, stateFile, stepIndex + 1, 0);
      }
    }
    return { hookEventName: 'PostToolUse' };
  }

  return { decision: 'approve' };
}
