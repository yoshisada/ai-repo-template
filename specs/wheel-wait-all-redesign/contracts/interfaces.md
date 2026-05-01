# Interface Contracts: Wheel `wait-all` Redesign

**Feature**: wheel-wait-all-redesign
**Constitution**: Article VII (Interface Contracts Before Implementation, NON-NEGOTIABLE)

These signatures are the SINGLE SOURCE OF TRUTH. Implementation MUST match exactly. If a signature needs to change, update this file FIRST.

## New / extended exported functions

### `archiveWorkflow` — `plugin-wheel/src/lib/state.ts`

```ts
/**
 * FR-001, FR-002, FR-006, FR-009: Archive a workflow's state file to
 * `.wheel/history/<bucket>/`. If the workflow has a non-null parent_workflow,
 * update the parent's teammate slot and (when applicable) advance the parent's
 * team-wait cursor BEFORE performing the rename.
 *
 * Lock ordering (FR-007): release child lock BEFORE acquiring parent lock.
 * Never hold both simultaneously.
 *
 * @param stateFile  Absolute path to `.wheel/state_*.json` to archive.
 * @param bucket     Which history bucket to move into.
 * @returns          Absolute path of the archived file in history/.
 * @throws           Filesystem error from rename. Parent-state-file-missing
 *                   is logged-and-swallowed (FR-001 step "if missing, log
 *                   warning and proceed").
 */
export async function archiveWorkflow(
  stateFile: string,
  bucket: 'success' | 'failure' | 'stopped'
): Promise<string>;
```

### `stateUpdateParentTeammateSlot` — `plugin-wheel/src/lib/state.ts`

```ts
/**
 * FR-001: Mutate parent.teams[<team_id>].teammates[<name>].status and
 * .completed_at, where <name> is found by matching slot.agent_id ===
 * childAlternateAgentId. No-op if no slot matches. Acquires parent flock.
 *
 * @param parentStateFile         Absolute path to parent state file.
 * @param childAlternateAgentId   Stable identifier from child state's
 *                                alternate_agent_id field (immune to
 *                                harness name suffixing).
 * @param newStatus               'completed' or 'failed'.
 * @returns                       { teamId: string, teammateName: string } if
 *                                a slot was updated, or null if no match.
 */
export async function stateUpdateParentTeammateSlot(
  parentStateFile: string,
  childAlternateAgentId: string,
  newStatus: 'completed' | 'failed'
): Promise<{ teamId: string; teammateName: string } | null>;
```

### `maybeAdvanceParentTeamWaitCursor` — `plugin-wheel/src/lib/state.ts`

```ts
/**
 * FR-002: If parent's current step is `team-wait` AND its `team` field
 * matches `teamId` AND every teammate in
 * parent.teams[teamId].teammates has status 'completed' or 'failed',
 * mark the team-wait step done and advance cursor (running
 * advance_past_skipped if next step is conditionally skipped).
 *
 * If parent is at a different cursor, no-op (slot updates from FR-001
 * remain in place idempotently).
 *
 * Acquires parent flock.
 *
 * @param parentStateFile  Absolute path to parent state file.
 * @param teamId           Team id whose slot was just updated.
 * @returns                true if cursor advanced; false otherwise.
 */
export async function maybeAdvanceParentTeamWaitCursor(
  parentStateFile: string,
  teamId: string
): Promise<boolean>;
```

### `dispatchTeamWait` (rewritten) — `plugin-wheel/src/lib/dispatch.ts`

```ts
/**
 * FR-003: Two-branch state-driven dispatcher. Does NOT mutate teammate
 * slot status — those mutations come from FR-001 (archive helper) and
 * FR-004 (polling backstop, which lives in this same file as a private
 * helper).
 *
 * Branches:
 *   - 'stop':           transition pending → working; re-check; if all
 *                       done, mark step done. Return approve.
 *   - 'post_tool_use':  run polling backstop; re-check; if all done,
 *                       mark step done. Return approve.
 *
 * `subagent_stop` and `teammate_idle` hook types are routed by hook
 * handlers (FR-005) into this function with hookType='post_tool_use'.
 *
 * @param step       Workflow step JSON (type=team-wait).
 * @param hookType   'stop' or 'post_tool_use'. Other hook types arrive
 *                   here as 'post_tool_use' per FR-005 routing.
 * @param hookInput  Raw hook input from harness.
 * @param stateFile  Absolute path to parent state file.
 * @param stepIndex  Current cursor (parent.cursor).
 * @returns          HookOutput.
 *
 * Size constraint (SC-002): function body + comments ≤132 lines
 * (30% reduction from baseline 189).
 */
async function dispatchTeamWait(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number
): Promise<HookOutput>;
```

### `_runPollingBackstop` (private to dispatch.ts) — `plugin-wheel/src/lib/dispatch.ts`

```ts
/**
 * FR-004: For each teammate currently status=='running' in
 * parent.teams[teamRef].teammates, reconcile against:
 *   1. Live state files (.wheel/state_*.json) — if found, skip.
 *   2. History buckets (.wheel/history/{success,failure,stopped}/) —
 *      mark completed/failed based on bucket, matched by parent_workflow
 *      and alternate_agent_id.
 *   3. Else mark failed with failure_reason='state-file-disappeared'.
 *
 * Order MUST be live → history → orphan. Persists all mutations under
 * a single parent flock acquisition (one write at end of sweep).
 *
 * @param parentStateFile  Absolute path to parent state file.
 * @param teamRef          Team id from the team-wait step.
 * @returns                { reconciledCount, stillRunningCount }.
 */
async function _runPollingBackstop(
  parentStateFile: string,
  teamRef: string
): Promise<{ reconciledCount: number; stillRunningCount: number }>;
```

### `_recheckAndCompleteIfDone` (private to dispatch.ts) — `plugin-wheel/src/lib/dispatch.ts`

```ts
/**
 * FR-003 helper: pure re-check. Counts teammate statuses; if all are
 * 'completed' or 'failed', marks parent step 'done' via
 * stateSetStepStatus. Otherwise no-op.
 *
 * @returns true if step was marked done; false otherwise.
 */
async function _recheckAndCompleteIfDone(
  stateFile: string,
  stepIndex: number,
  teamRef: string
): Promise<boolean>;
```

### Hook routing (handler simplification) — FR-005

The `teammate_idle` and `subagent_stop` hook handlers route to `dispatchTeamWait` with `hook_type: "post_tool_use"`. No new exported signature — this is a behavior change in existing handlers. The handler entry points (likely `engine.ts` or wherever hook-type → dispatcher mapping lives) MUST satisfy this routing.

Pseudocode contract:

```ts
// In whichever module handles teammate_idle / subagent_stop:
if (parent.steps[parent.cursor].type === 'team-wait') {
  return dispatchTeamWait(
    parent.steps[parent.cursor],
    'post_tool_use',                // remapped per FR-005
    hookInput,
    parentStateFilePath,
    parent.cursor
  );
}
return { decision: 'approve' };     // no-op
```

## Logging contract (FR-008)

`plugin-wheel/src/lib/log.ts` is assumed to expose a `wheelLog(phase: string, fields: Record<string, unknown>): Promise<void>` (or equivalent). The implementer confirms the actual signature at impl start and adapts callers.

Required call sites:

```ts
// FR-008 — called from stateUpdateParentTeammateSlot (FR-001):
await wheelLog('archive_parent_update', {
  child_agent_id: childAlternateAgentId,
  parent_state_file: parentStateFile,
  team_id: teamId,
  teammate_name: teammateName,
  new_status: newStatus,
  cursor_advanced: cursorAdvanced,   // boolean, populated after FR-002 returns
});

// FR-008 — called from _runPollingBackstop (FR-004):
await wheelLog('wait_all_polling', {
  parent_state_file: parentStateFile,
  team_id: teamRef,
  reconciled_count: reconciledCount,
  still_running_count: stillRunningCount,
});
```

## Schema invariants (unchanged — FR-010)

The following are NOT modified by this PRD; signatures listed for documentation only:

- `WorkflowStep`, `HookType`, `HookInput`, `HookOutput` types — unchanged.
- `state.teams[<team_id>].teammates[<name>]` shape (`agent_id`, `status`, `started_at`, `completed_at`) — unchanged. Adds optional `failure_reason: string` field (set only by FR-004 orphan path).
- `state.parent_workflow: string | null` — unchanged contract.
- `state.alternate_agent_id: string` — unchanged contract.

Any signature change to the schema invariants above is OUT OF SCOPE for this PRD and MUST be flagged to the team lead before edits.

## Sync vs async

ALL functions in this contract are `async` and return `Promise<...>`. Locking is `flock`-based (filesystem-level), so all helpers that touch state files do file I/O.

## Compliance check (run before tasks.md is finalized)

- [x] Every FR in spec.md has at least one signature here OR a referenced unchanged signature.
- [x] Every signature here references the FR(s) it implements.
- [x] No signature contradicts the schema invariants in FR-010.
- [x] Lock-ordering invariant (FR-007) referenced in `archiveWorkflow` and `stateUpdateParentTeammateSlot` JSDoc.
- [x] Size constraint (SC-002) noted on `dispatchTeamWait`.
