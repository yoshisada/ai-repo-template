// FR-006: State operations on WheelState — read-modify-write via stateRead/stateWrite
//
// =============================================================================
// FR-007 (wheel-wait-all-redesign) — LOCK-ORDERING INVARIANT
// =============================================================================
// Nothing in wheel takes a child state-file lock while holding a parent
// state-file lock. The cross-process signal between a child sub-workflow and
// its parent (a `team-wait` step) is a write under the PARENT's lock — and
// the child has already RELEASED its own lock by the time it reaches the
// rename-to-history step.
//
// Concrete rules:
//   1. archiveWorkflow reads child state OUTSIDE any lock (the child workflow
//      is terminal — no concurrent writers). It then takes the parent lock
//      via stateUpdateParentTeammateSlot / maybeAdvanceParentTeamWaitCursor.
//   2. stateUpdateParentTeammateSlot acquires ONLY the parent lock.
//   3. maybeAdvanceParentTeamWaitCursor acquires ONLY the parent lock.
//   4. Two siblings archiving simultaneously contend on the parent lock and
//      serialize via withLockBlocking's jittered backoff. Each updates a
//      disjoint slot, so both writes land.
//
// If a future change requires holding both a child and parent lock at the
// same time, that is a redesign — update this comment block first.
// =============================================================================
import { promises as fs } from 'fs';
import { stateRead, stateWrite } from '../shared/state.js';
import type { WheelState, StepStatus, AgentStatus, TeammateStatus, TeammateEntry } from '../shared/state.js';
import { mkdirp } from '../shared/fs.js';
import { withLockBlocking } from './lock.js';
import { wheelLog } from './log.js';
import path from 'path';

export interface StateInitParams {
  stateFile: string;
  workflow: { name: string; version: string; steps: { id: string; type: string }[] };
  sessionId: string;
  agentId: string;
  workflowFile?: string;
  parentWorkflow?: string;
  sessionRegistry?: Record<string, string>;
  alternateAgentId?: string;
}

// FR-006: Initialize a new state file from workflow definition
export async function stateInit(params: StateInitParams): Promise<void> {
  const { stateFile, workflow, sessionId, agentId, workflowFile, parentWorkflow, sessionRegistry, alternateAgentId } = params;

  await mkdirp(path.dirname(stateFile));

  const now = new Date().toISOString();
  const state: WheelState = {
    workflow_name: workflow.name,
    workflow_version: workflow.version,
    workflow_file: workflowFile ?? '',
    workflow_definition: null,
    status: 'running',
    cursor: 0,
    owner_session_id: sessionId,
    owner_agent_id: agentId,
    alternate_agent_id: alternateAgentId,
    // FR-001/FR-009 (wheel-wait-all-redesign): persist parent path so the
    // archive helper can locate the parent state file at terminal time.
    parent_workflow: parentWorkflow ?? null,
    started_at: now,
    updated_at: now,
    steps: workflow.steps.map((step) => ({
      id: step.id,
      type: step.type,
      status: 'pending' as StepStatus,
      started_at: null,
      completed_at: null,
      output: null,
      command_log: [],
      agents: {},
      loop_iteration: 0,
      awaiting_user_input: false,
      awaiting_user_input_since: null,
      awaiting_user_input_reason: null,
      resolved_inputs: null,
      contract_emitted: false,
    })),
    teams: {},
    session_registry: sessionRegistry ?? null,
  };

  if (parentWorkflow) {
    // Load parent workflow definition for child workflows
    try {
      const parentState = await stateRead(parentWorkflow);
      state.workflow_definition = parentState.workflow_definition;
    } catch {
      // Parent not available, continue without it
    }
  }

  await stateWrite(stateFile, state);
}

// FR-006: stateGetCursor(state: WheelState): number
export function stateGetCursor(state: WheelState): number {
  return state.cursor;
}

// FR-006: stateSetCursor(stateFile: string, cursor: number): Promise<void>
export async function stateSetCursor(stateFile: string, cursor: number): Promise<void> {
  const state = await stateRead(stateFile);
  state.cursor = cursor;
  await stateWrite(stateFile, state);
}

// FR-006: stateGetStepStatus(state: WheelState, stepIndex: number): StepStatus
export function stateGetStepStatus(state: WheelState, stepIndex: number): StepStatus {
  return state.steps[stepIndex]?.status ?? 'pending';
}

// FR-006: stateSetStepStatus(stateFile: string, stepIndex: number, status: StepStatus): Promise<void>
export async function stateSetStepStatus(stateFile: string, stepIndex: number, status: StepStatus): Promise<void> {
  const state = await stateRead(stateFile);
  const now = new Date().toISOString();
  const step = state.steps[stepIndex];
  if (!step) return;

  step.status = status;
  if (status === 'working') {
    step.started_at = now;
  } else if (status === 'done' || status === 'failed') {
    step.completed_at = now;
  }
  state.updated_at = now;
  await stateWrite(stateFile, state);
}

// FR-006: stateGetAgentStatus(state: WheelState, stepIndex: number, agentType: string): AgentStatus
export function stateGetAgentStatus(state: WheelState, stepIndex: number, agentType: string): AgentStatus {
  const step = state.steps[stepIndex];
  if (!step) throw new Error(`Step ${stepIndex} not found`);
  const agent = step.agents[agentType];
  if (!agent) throw new Error(`Agent ${agentType} not found in step ${stepIndex}`);
  return agent.status;
}

// FR-006: stateSetAgentStatus(stateFile: string, stepIndex: number, agentType: string, status: AgentStatus): Promise<void>
export async function stateSetAgentStatus(stateFile: string, stepIndex: number, agentType: string, status: AgentStatus): Promise<void> {
  const state = await stateRead(stateFile);
  const now = new Date().toISOString();
  const step = state.steps[stepIndex];
  if (!step) return;

  if (!step.agents[agentType]) {
    step.agents[agentType] = { status: 'pending', started_at: null, completed_at: null };
  }
  const agent = step.agents[agentType];
  agent.status = status;
  if (status === 'working') {
    agent.started_at = now;
  } else if (status === 'done' || status === 'failed') {
    agent.completed_at = now;
  }
  state.updated_at = now;
  await stateWrite(stateFile, state);
}

// FR-006: stateSetStepOutput(stateFile: string, stepIndex: number, output: unknown): Promise<void>
export async function stateSetStepOutput(stateFile: string, stepIndex: number, output: unknown): Promise<void> {
  const state = await stateRead(stateFile);
  const step = state.steps[stepIndex];
  if (!step) return;
  step.output = output;
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-006: stateAppendCommandLog(stateFile: string, stepIndex: number, entry: { command: string; exit_code: number; timestamp: string }): Promise<void>
export async function stateAppendCommandLog(
  stateFile: string,
  stepIndex: number,
  entry: { command: string; exit_code: number; timestamp: string }
): Promise<void> {
  const state = await stateRead(stateFile);
  const step = state.steps[stepIndex];
  if (!step) return;
  step.command_log.push(entry);
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-006: stateGetCommandLog(state: WheelState, stepIndex: number): { command: string; exit_code: number; timestamp: string }[]
export function stateGetCommandLog(state: WheelState, stepIndex: number): { command: string; exit_code: number; timestamp: string }[] {
  return state.steps[stepIndex]?.command_log ?? [];
}

// FR-006: stateSetTeam(stateFile: string, stepId: string, teamName: string): Promise<void>
export async function stateSetTeam(stateFile: string, stepId: string, teamName: string): Promise<void> {
  const state = await stateRead(stateFile);
  state.teams[stepId] = {
    team_name: teamName,
    created_at: new Date().toISOString(),
    teammates: {},
  };
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-006: stateGetTeam(state: WheelState, stepId: string)
export function stateGetTeam(state: WheelState, stepId: string) {
  return state.teams[stepId] ?? null;
}

// FR-006: stateAddTeammate(stateFile: string, teamStepId: string, teammate: TeammateEntry): Promise<void>
export async function stateAddTeammate(stateFile: string, teamStepId: string, teammate: TeammateEntry): Promise<void> {
  const state = await stateRead(stateFile);
  if (!state.teams[teamStepId]) {
    state.teams[teamStepId] = { team_name: '', created_at: new Date().toISOString(), teammates: {} };
  }
  state.teams[teamStepId].teammates[teammate.agent_id] = teammate;
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-006: stateUpdateTeammateStatus(stateFile: string, teamStepId: string, agentName: string, status: TeammateStatus): Promise<void>
export async function stateUpdateTeammateStatus(stateFile: string, teamStepId: string, agentName: string, status: TeammateStatus): Promise<void> {
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

// FR-006: stateGetTeammates(state: WheelState, teamStepId: string): Record<string, TeammateEntry>
export function stateGetTeammates(state: WheelState, teamStepId: string): Record<string, TeammateEntry> {
  return state.teams[teamStepId]?.teammates ?? {};
}

// FR-006: stateRemoveTeam(stateFile: string, stepId: string): Promise<void>
export async function stateRemoveTeam(stateFile: string, stepId: string): Promise<void> {
  const state = await stateRead(stateFile);
  delete state.teams[stepId];
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-006: stateList(pattern?: string): Promise<string[]> - list state files matching pattern
export async function stateList(pattern: string = '.wheel/state_*.json'): Promise<string[]> {
  const { readdir } = await import('fs/promises');
  const pathModule = await import('path');

  // Parse pattern - handle basic glob like .wheel/state_*.json
  const dir = pattern.includes('/')
    ? pattern.slice(0, pattern.lastIndexOf('/'))
    : '.';
  const prefix = pattern.slice(pattern.lastIndexOf('/') + 1).replace('*.json', '').replace('*', '');

  let files: string[] = [];
  try {
    const entries = await readdir(dir);
    for (const entry of entries) {
      if (entry.startsWith(prefix) && entry.endsWith('.json')) {
        files.push(pathModule.join(dir, entry));
      }
    }
  } catch {
    // Directory may not exist
  }
  return files;
}

// FR-003/004 (wheel-user-input): stateSetAwaitingUserInput
export async function stateSetAwaitingUserInput(stateFile: string, stepIndex: number, reason: string): Promise<void> {
  const state = await stateRead(stateFile);
  const step = state.steps[stepIndex];
  if (!step) return;
  step.awaiting_user_input = true;
  step.awaiting_user_input_since = new Date().toISOString();
  step.awaiting_user_input_reason = reason;
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-004/008 (wheel-user-input): stateClearAwaitingUserInput
export async function stateClearAwaitingUserInput(stateFile: string, stepIndex: number): Promise<void> {
  const state = await stateRead(stateFile);
  const step = state.steps[stepIndex];
  if (!step) return;
  step.awaiting_user_input = false;
  step.awaiting_user_input_since = null;
  step.awaiting_user_input_reason = null;
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-§4.1 (wheel-typed-schema-locality): stateSetResolvedInputs
export async function stateSetResolvedInputs(stateFile: string, stepIndex: number, resolvedMap: unknown): Promise<void> {
  const state = await stateRead(stateFile);
  const step = state.steps[stepIndex];
  if (!step) return;
  step.resolved_inputs = resolvedMap;
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-§4.2: stateSetContractEmitted
export async function stateSetContractEmitted(stateFile: string, stepIndex: number, emitted: boolean): Promise<void> {
  const state = await stateRead(stateFile);
  const step = state.steps[stepIndex];
  if (!step) return;
  step.contract_emitted = emitted;
  state.updated_at = new Date().toISOString();
  await stateWrite(stateFile, state);
}

// FR-§4.3: stateGetContractEmitted
export async function stateGetContractEmitted(stateFile: string, stepIndex: number): Promise<boolean> {
  try {
    const state = await stateRead(stateFile);
    return state.steps[stepIndex]?.contract_emitted ?? false;
  } catch {
    return false;
  }
}

// =============================================================================
// FR-001, FR-002, FR-006, FR-007, FR-008, FR-009 (wheel-wait-all-redesign)
// =============================================================================
// archiveWorkflow + parent-state helpers. See the lock-ordering invariant
// block at the top of this file. All three helpers below take ONLY the
// parent lock; archiveWorkflow itself never takes a lock (the child
// workflow is terminal at archive time).

// FR-001 (wheel-wait-all-redesign): mutate parent.teams[<team_id>].teammates[<name>]
// where slot.agent_id === childAlternateAgentId. No-op (returns null) if no
// slot matches. Acquires parent lock via withLockBlocking (FR-007 ordering:
// caller MUST NOT hold any other state-file lock).
export async function stateUpdateParentTeammateSlot(
  parentStateFile: string,
  childAlternateAgentId: string,
  newStatus: 'completed' | 'failed'
): Promise<{ teamId: string; teammateName: string } | null> {
  return withLockBlocking(parentStateFile, async () => {
    let parent: WheelState;
    try {
      parent = await stateRead(parentStateFile);
    } catch {
      // FR-001 EC-1: parent missing/corrupt. Caller logs the warning;
      // here we just return null and let archive proceed.
      return null;
    }

    let foundTeam: string | null = null;
    let foundName: string | null = null;
    for (const [teamId, team] of Object.entries(parent.teams ?? {})) {
      const teammates = (team as { teammates?: Record<string, TeammateEntry> })
        .teammates ?? {};
      for (const [name, slot] of Object.entries(teammates)) {
        if (slot && slot.agent_id === childAlternateAgentId) {
          foundTeam = teamId;
          foundName = name;
          break;
        }
      }
      if (foundTeam) break;
    }

    if (!foundTeam || !foundName) {
      return null;
    }

    const now = new Date().toISOString();
    const slot = parent.teams[foundTeam].teammates[foundName];
    slot.status = newStatus;
    slot.completed_at = now;
    parent.updated_at = now;
    await stateWrite(parentStateFile, parent);

    return { teamId: foundTeam, teammateName: foundName };
  });
}

// FR-002 (wheel-wait-all-redesign): if parent's current step is `team-wait`
// AND its `team` field matches `teamId` AND every teammate has terminal
// status, mark the step done and advance cursor (skipping any conditionally
// skipped steps). Otherwise no-op. Acquires parent lock via
// withLockBlocking (FR-007 ordering).
export async function maybeAdvanceParentTeamWaitCursor(
  parentStateFile: string,
  teamId: string
): Promise<boolean> {
  return withLockBlocking(parentStateFile, async () => {
    let parent: WheelState;
    try {
      parent = await stateRead(parentStateFile);
    } catch {
      return false;
    }

    const cursor = parent.cursor ?? 0;
    const step = parent.steps?.[cursor];
    if (!step || step.type !== 'team-wait') {
      // FR-002 / EC-2: parent at unexpected cursor. Slot update from FR-001
      // remains in place; do not advance.
      return false;
    }

    // Resolve the workflow-level step JSON to read its `team` field.
    // Source order: workflow_definition (hot) → null. Fall back to step.id
    // when the JSON's `team` field isn't set (existing convention in
    // dispatchTeamWait: teamRef = step.team ?? step.id).
    const wfDef = parent.workflow_definition;
    const wfStep = wfDef?.steps?.[cursor] as
      | { team?: string; id?: string }
      | undefined;
    const stepTeam = wfStep?.team ?? wfStep?.id ?? step.id;
    if (stepTeam !== teamId) {
      return false;
    }

    const team = parent.teams?.[teamId];
    if (!team) return false;
    const teammates = team.teammates ?? {};
    const names = Object.keys(teammates);
    // FR-002 honors the existing 0-teammate edge case from the rewrite:
    // dispatchTeamWait already short-circuits at total===0, so we don't
    // duplicate that here. If a 0-teammate parent reaches us, we mark
    // done — same effective semantics.
    for (const name of names) {
      const status = teammates[name]?.status ?? 'pending';
      if (status !== 'completed' && status !== 'failed') {
        return false;
      }
    }

    const now = new Date().toISOString();
    step.status = 'done';
    step.completed_at = now;

    // advance_past_skipped: skip over any steps the workflow already
    // marked 'skipped' (e.g., by a branch). Match the shell semantics —
    // bump cursor past the team-wait step, then walk forward across
    // contiguous 'skipped' steps.
    let next = cursor + 1;
    while (
      next < parent.steps.length &&
      parent.steps[next] &&
      parent.steps[next].status === 'skipped'
    ) {
      next++;
    }
    parent.cursor = next;
    parent.updated_at = now;
    await stateWrite(parentStateFile, parent);
    return true;
  });
}

// FR-001, FR-002, FR-006, FR-009 (wheel-wait-all-redesign): single
// deterministic call path for archiving a workflow's state file to
// .wheel/history/<bucket>/. If the workflow has a non-null parent_workflow,
// updates the parent's teammate slot and (when applicable) advances the
// parent's team-wait cursor BEFORE renaming the child file to history.
//
// Lock ordering (FR-007): no child lock is taken; parent lock is taken
// only inside the helpers above. The two helper calls release-then-
// reacquire the parent lock — this is intentional. Concurrent siblings
// serialize on each acquisition; the LAST update will trigger the
// cursor advance because by that time every teammate slot is terminal.
export async function archiveWorkflow(
  stateFile: string,
  bucket: 'success' | 'failure' | 'stopped'
): Promise<string> {
  // Read child state without a lock — child workflow is terminal here.
  const child = await stateRead(stateFile);
  const parentPath = child.parent_workflow ?? null;
  const childAlternate = child.alternate_agent_id ?? null;

  let updateResult: { teamId: string; teammateName: string } | null = null;
  let cursorAdvanced = false;

  if (parentPath && childAlternate) {
    // FR-001 EC-1: parent state file missing → log warning, proceed with
    // rename (no throw). Detect via fs.access; helper itself is also
    // null-safe but we want the explicit log line per EC-1.
    let parentExists = false;
    try {
      await fs.access(parentPath);
      parentExists = true;
    } catch {
      parentExists = false;
    }

    if (!parentExists) {
      await wheelLog('archive_parent_update_skipped', {
        child_agent_id: childAlternate,
        parent_state_file: parentPath,
        reason: 'parent_state_file_missing',
      });
    } else {
      const newStatus: 'completed' | 'failed' =
        bucket === 'success' ? 'completed' : 'failed';
      try {
        updateResult = await stateUpdateParentTeammateSlot(
          parentPath,
          childAlternate,
          newStatus
        );
        if (updateResult) {
          cursorAdvanced = await maybeAdvanceParentTeamWaitCursor(
            parentPath,
            updateResult.teamId
          );
        }
      } catch (err) {
        // Don't let parent-update errors block the archive itself.
        await wheelLog('archive_parent_update_error', {
          child_agent_id: childAlternate,
          parent_state_file: parentPath,
          error: String(err instanceof Error ? err.message : err),
        });
      }

      // FR-008 archive_parent_update log line — emitted from the
      // archive orchestrator (NOT from stateUpdateParentTeammateSlot)
      // so that cursor_advanced can be populated in the same line.
      // The contract JSDoc note "called from stateUpdateParentTeammateSlot"
      // is a call-site convention; the FR-008 field set is what matters.
      if (updateResult) {
        await wheelLog('archive_parent_update', {
          child_agent_id: childAlternate,
          parent_state_file: parentPath,
          team_id: updateResult.teamId,
          teammate_name: updateResult.teammateName,
          new_status: newStatus,
          cursor_advanced: cursorAdvanced,
        });
      } else {
        await wheelLog('archive_parent_update_no_match', {
          child_agent_id: childAlternate,
          parent_state_file: parentPath,
        });
      }
    }
  }

  // parity: shell dispatch.sh:144 — composition parent-resume.
  // When child has a parent_workflow but no alternate_agent_id (or no
  // teammate slot matched), this is a composition (workflow-step parent).
  // Find the parent's currently-working `workflow` step, mark it done,
  // advance cursor past skipped steps. The dispatch of the parent's NEXT
  // step is handled separately by _chainParentAfterArchive at the call
  // site (or by the next hook fire if not invoked).
  if (parentPath && !updateResult) {
    try {
      await fs.access(parentPath);
      const parent = await stateRead(parentPath);
      const workingIdx = parent.steps.findIndex(
        (s: any) => s.type === 'workflow' && s.status === 'working'
      );
      if (workingIdx >= 0) {
        await stateSetStepStatus(parentPath, workingIdx, 'done');
        // resolve next via workflow_definition if available
        const wfDef: any = (parent as any).workflow_definition;
        let nextIdx = workingIdx + 1;
        if (wfDef?.steps) {
          const stepJson = wfDef.steps[workingIdx];
          const wfMod = await import('./workflow.js');
          const rawNext = wfMod.resolveNextIndex(stepJson, workingIdx, wfDef);
          nextIdx = await wfMod.advancePastSkipped(parentPath, rawNext, wfDef);
        }
        await stateSetCursor(parentPath, nextIdx);
        await wheelLog('archive_parent_compose_advance', {
          parent_state_file: parentPath,
          parent_step_index: workingIdx,
          new_cursor: nextIdx,
        });
      }
    } catch {
      // parent file missing or unreadable — already logged above
    }
  }

  // FR-009: rename child state file to .wheel/history/<bucket>/.
  const archiveDir = path.join('.wheel', 'history', bucket);
  await mkdirp(archiveDir);
  const workflowName = child.workflow_name || 'workflow';
  const ts = new Date()
    .toISOString()
    .replace(/[-:]/g, '')
    .replace(/\.\d+Z$/, 'Z')
    .replace('T', '-');
  // Strip trailing 'Z' for compactness; format: YYYYMMDD-HHMMSS
  const compactTs = ts.replace(/Z$/, '');
  const stateBasename = path.basename(stateFile, '.json');
  const stateId = stateBasename.replace(/^state_/, '');
  const target = path.join(
    archiveDir,
    `${workflowName}-${compactTs}-${stateId}.json`
  );

  try {
    await fs.rename(stateFile, target);
  } catch (err) {
    // If rename fails (e.g., cross-device on some FS), fall back to copy + unlink.
    const code = (err as NodeJS.ErrnoException).code;
    if (code === 'EXDEV') {
      await fs.copyFile(stateFile, target);
      await fs.unlink(stateFile);
    } else {
      throw err;
    }
  }
  return target;
}