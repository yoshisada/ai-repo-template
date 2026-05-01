// FR-006/FR-004/FR-005: Session guard for teammate idle handling
import { promises as fs } from 'fs';
import path from 'path';
import { stateRead } from '../shared/state.js';
import type { HookInput } from './dispatch.js';

export interface GuardResult {
  decision: 'approve' | 'block';
  instruction?: string;
}

// Resolve the state file owned by the current hook invocation.
// Matches by owner_session_id + owner_agent_id (or alternate_agent_id for
// teammate sub-workflows). Used by every hook entry point that needs to
// dispatch into the engine — extracted from post-tool-use's private helper
// so stop.ts / subagent-stop.ts / teammate-idle.ts share the same lookup
// logic. Returns null when no state file matches; callers MUST handle that
// case (no active workflow for this caller).
export async function resolveStateFile(
  stateDir: string,
  hookInput: HookInput
): Promise<string | null> {
  const hookSessionId = (hookInput.session_id as string) ?? '';
  const hookAgentId = (hookInput.agent_id as string) ?? '';

  let stateFiles: string[];
  try {
    stateFiles = await fs.readdir(stateDir);
  } catch {
    return null;
  }
  for (const file of stateFiles) {
    if (!file.startsWith('state_') || !file.endsWith('.json')) continue;
    const statePath = path.join(stateDir, file);
    try {
      const content = await fs.readFile(statePath, 'utf-8');
      const state = JSON.parse(content);
      if (state.owner_session_id === hookSessionId) {
        if (state.owner_agent_id === hookAgentId || state.owner_agent_id === '') {
          return statePath;
        }
      }
      if (state.alternate_agent_id === hookAgentId) {
        return statePath;
      }
    } catch {
      // Skip invalid state files
    }
  }
  return null;
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