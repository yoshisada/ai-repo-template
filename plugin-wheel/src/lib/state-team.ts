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

/**
 * Read-modify-write helper for state mutations that don't fit the
 * step-scoped `mutateStep` shape (whole-state-graph reads/writes,
 * teams[*] mutations, etc.). Stamps `updated_at` automatically.
 */
async function mutateState(
  stateFile: string,
  mutator: (state: WheelState, now: string) => void,
): Promise<void> {
  const state = await stateRead(stateFile);
  const now = new Date().toISOString();
  mutator(state, now);
  state.updated_at = now;
  await stateWrite(stateFile, state);
}

/** Register a fresh team under `state.teams[stepId]` with empty teammate map. */
export async function stateSetTeam(
  stateFile: string,
  stepId: string,
  teamName: string,
): Promise<void> {
  await mutateState(stateFile, (state, now) => {
    state.teams[stepId] = { team_name: teamName, created_at: now, teammates: {} };
  });
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
  await mutateState(stateFile, (state, now) => {
    if (!state.teams[teamStepId]) {
      state.teams[teamStepId] = { team_name: '', created_at: now, teammates: {} };
    }
    state.teams[teamStepId].teammates[teammate.agent_id] = teammate;
  });
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
  await mutateState(stateFile, (state, now) => {
    const slot = state.teams[teamStepId]?.teammates[agentName];
    if (!slot) return;
    slot.status = status;
    if (status === 'running') slot.started_at = now;
    else if (status === 'completed' || status === 'failed') slot.completed_at = now;
  });
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
  await mutateState(stateFile, (state) => { delete state.teams[stepId]; });
}
