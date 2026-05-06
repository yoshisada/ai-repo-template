// Team + teammate state mutation helpers.
//
// Split out from `state.ts` so the team primitives live next to each
// other and the core state file (init/cursor/step status/awaiting-input)
// stays compact.
//
// FR-006.

import { stateRead, stateWrite } from '../shared/state.js';
import type {
  WheelState, TeammateEntry, TeammateStatus,
} from '../shared/state.js';

/** Register a fresh team under `state.teams[stepId]` with empty teammate map. */
export async function stateSetTeam(
  stateFile: string,
  stepId: string,
  teamName: string,
): Promise<void> {
  const state = await stateRead(stateFile);
  state.teams[stepId] = {
    team_name: teamName,
    created_at: new Date().toISOString(),
    teammates: {},
  };
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

/** Read team registration; null if missing. */
export function stateGetTeam(state: WheelState, stepId: string) {
  return state.teams[stepId] ?? null;
}

/**
 * Add a teammate slot under team `teamStepId`. Map is keyed by
 * `teammate.agent_id` (e.g., `worker-1@team-name` post-bug-#1) — the
 * join key for parent-slot lookups.
 */
export async function stateAddTeammate(
  stateFile: string,
  teamStepId: string,
  teammate: TeammateEntry,
): Promise<void> {
  const state = await stateRead(stateFile);
  if (!state.teams[teamStepId]) {
    state.teams[teamStepId] = {
      team_name: '',
      created_at: new Date().toISOString(),
      teammates: {},
    };
  }
  state.teams[teamStepId].teammates[teammate.agent_id] = teammate;
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

/**
 * Update a teammate's status. Sets `started_at` on running, `completed_at`
 * on completed/failed. No-op if team or teammate slot missing.
 */
export async function stateUpdateTeammateStatus(
  stateFile: string,
  teamStepId: string,
  agentName: string,
  status: TeammateStatus,
): Promise<void> {
  const state = await stateRead(stateFile);
  const team = state.teams[teamStepId];
  if (!team || !team.teammates[agentName]) return;

  const now = new Date().toISOString();
  team.teammates[agentName].status = status;
  if (status === 'running') {
    team.teammates[agentName].started_at = now;
  } else if (status === 'completed' || status === 'failed') {
    team.teammates[agentName].completed_at = now;
  }
  state.updated_at = now;
  await stateWrite(stateFile, state);
}

/** Return the teammate map for team `teamStepId`. Empty object if missing. */
export function stateGetTeammates(
  state: WheelState,
  teamStepId: string,
): Record<string, TeammateEntry> {
  return state.teams[teamStepId]?.teammates ?? {};
}

/** Remove a team registration entirely (used by team-delete). */
export async function stateRemoveTeam(
  stateFile: string,
  stepId: string,
): Promise<void> {
  const state = await stateRead(stateFile);
  delete state.teams[stepId];
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}
