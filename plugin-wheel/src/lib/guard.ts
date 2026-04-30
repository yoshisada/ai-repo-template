// FR-006/FR-004/FR-005: Session guard for teammate idle handling
import { stateRead } from '../shared/state.js';

export interface GuardResult {
  decision: 'approve' | 'block';
  instruction?: string;
}

// FR-006: guardCheck(stateFile: string, stepIndex: number): Promise<GuardResult>
export async function guardCheck(stateFile: string, stepIndex: number): Promise<GuardResult> {
  try {
    const state = await stateRead(stateFile);
    const step = state.steps[stepIndex];

    if (!step) {
      return { decision: 'approve' };
    }

    // Check if this is a team-wait or agent step
    const isBlocking = step.type === 'team-wait' || step.type === 'agent';

    if (!isBlocking) {
      return { decision: 'approve' };
    }

    if (step.type === 'team-wait') {
      // Check if all teammates are done
      const currentStepId = step.id;
      const team = state.teams[currentStepId];
      if (team) {
        const allDone = Object.values(team.teammates).every(
          (t) => t.status === 'completed' || t.status === 'failed'
        );
        if (allDone) {
          return { decision: 'approve' };
        }
        return {
          decision: 'block',
          instruction: `Waiting for teammates to complete: ${Object.values(team.teammates)
            .filter((t) => t.status !== 'completed' && t.status !== 'failed')
            .map((t) => t.agent_id)
            .join(', ')}`,
        };
      }
    }

    if (step.type === 'agent') {
      // Check agent status
      const agentStatuses = Object.values(step.agents);
      if (agentStatuses.length === 0) {
        return { decision: 'approve' };
      }
      const allDone = agentStatuses.every((a) => a.status === 'done' || a.status === 'failed');
      if (allDone) {
        return { decision: 'approve' };
      }
    }

    return { decision: 'approve' };
  } catch {
    return { decision: 'approve' }; // Fail open on errors
  }
}