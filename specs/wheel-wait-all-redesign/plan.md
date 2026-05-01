# Implementation Plan: Wheel `wait-all` Redesign

**Feature**: wheel-wait-all-redesign
**Branch**: `build/wheel-wait-all-redesign-20260430` (folds into `002-wheel-ts-rewrite`)
**Created**: 2026-04-30
**Status**: Draft

## Foundation (NON-NEGOTIABLE — first impl step)

Implementer reads CURRENT branch state of these files BEFORE editing:

1. `plugin-wheel/src/lib/dispatch.ts` (current `dispatchTeamWait` lives at lines 425–612, baseline 189 lines per `research.md` §baseline).
2. `plugin-wheel/src/lib/state.ts` (current `stateUpdateTeammateStatus`, `stateAddTeammate`, etc. — extension surface).
3. `plugin-wheel/src/lib/lock.ts` (locking primitives — confirm per-file lock semantics).
4. `plugin-wheel/src/lib/log.ts` (wheel.log helpers — confirm phase-tagged emit API).
5. `plugin-wheel/lib/dispatch.sh:122–318` (shell `_archive_workflow` — behavioral reference for the TS archive helper if not yet ported).

The implementer extends these. Resetting the branch or discarding existing in-progress code is NOT permitted.

## Technical Approach

The redesign collapses `dispatchTeamWait` from event-driven (4 branches) to state-driven (2 branches) and moves status-mutation responsibility from the parent's hook handler INTO the archive helper. The cross-process signal becomes a deterministic file write under `flock`, not a hook event.

Three loci of change:

1. **Archive helper** (`state.ts`): adds parent-update + cursor-advance block before rename. New helper `archiveWorkflow(stateFile, bucket)` orchestrates: parent update (FR-001) → cursor advance check (FR-002) → rename to `history/<bucket>/`.
2. **`dispatchTeamWait`** (`dispatch.ts`): rewritten to two pure branches that do NOT mutate teammate slot status. They run a re-check + (in `post_tool_use`) the polling backstop (FR-003, FR-004).
3. **Hook handlers for `teammate_idle` / `subagent_stop`** (`dispatch.ts` or wherever they're routed): simplified to wake-up nudges that delegate to `dispatchTeamWait` with `hook_type: "post_tool_use"` (FR-005).

### Phase 1 — Archive helper extension (FR-001, FR-002, FR-006, FR-009)

**Goal**: A single TS function owns rename-to-history AND parent-state update. Atomic-ish via lock ordering.

**Steps**:
1. Confirm whether `archiveWorkflow` exists in `state.ts`. If not, port shell `_archive_workflow` (`plugin-wheel/lib/dispatch.sh:122–318`) for the rename + bucket-selection skeleton.
2. Add a `_updateParentTeammateSlot` helper that: opens parent state under parent's `flock`, finds the slot whose `agent_id == child.alternate_agent_id`, sets `status` + `completed_at`, writes back, releases lock.
3. Add `_maybeAdvanceParentTeamWaitCursor` that runs IF parent's current step is `team-wait` AND its `team` field matches the updated team_id AND every teammate is `completed`/`failed`. Uses existing `advance_past_skipped` semantics.
4. Wire `archiveWorkflow(stateFile, bucket)` to: read child state → if `parent_workflow != null`, call `_updateParentTeammateSlot` then `_maybeAdvanceParentTeamWaitCursor` → rename child to `history/<bucket>/`.
5. Lock ordering: child lock released BEFORE parent lock taken (FR-007 invariant). Document with comment block.

**Files**: `plugin-wheel/src/lib/state.ts`, possibly `plugin-wheel/src/lib/dispatch.ts` (if archive helper currently lives there).

### Phase 2 — `dispatchTeamWait` rewrite (FR-003)

**Goal**: Two-branch pure re-check function ≤132 lines.

**Steps**:
1. Extract a private `_recheckAndCompleteIfDone(state, stepIndex, teamRef)` helper that: counts `completed`/`failed`/`running` teammates, returns done-or-not. If done, mark step `done` via `stateSetStepStatus`.
2. Rewrite `dispatchTeamWait` body:
   - `stop` branch: transition `pending → working`. Call `_recheckAndCompleteIfDone`. If done, return approve. Else return `{decision: "approve"}` (parent goes idle).
   - `post_tool_use` branch: call `_runPollingBackstop` (FR-004) FIRST, then `_recheckAndCompleteIfDone`. Return appropriate `HookOutput`.
3. Delete the inline `Agent` and `TaskUpdate` mutation logic — those don't belong here anymore. Teammate `agent_id` registration moved to wherever the team-create / teammate spawn dispatcher already handles it (`team-create` step type), or kept as a thin pass-through if that's where it currently lives. (Implementer decides during Phase 2 based on current code structure.)
4. Delete the entire `teammate_idle` branch in `dispatchTeamWait`. The hook handlers (Phase 4) will dispatch `teammate_idle` to the `post_tool_use` branch.
5. Verify line count: target ≤132 lines after this phase.

**Files**: `plugin-wheel/src/lib/dispatch.ts`.

### Phase 3 — Polling backstop (FR-004)

**Goal**: `_runPollingBackstop(parentState, teamRef)` reconciles `running` teammates against live state files + history buckets.

**Steps**:
1. Implement `_runPollingBackstop(parentStateFile, parentState, teamRef)`:
   - For each teammate with `status == "running"`:
     - List live `.wheel/state_*.json`. If any match `alternate_agent_id`, skip (still working).
     - Else scan `.wheel/history/{success,failure,stopped}/`. Read each archived file's `parent_workflow` and `alternate_agent_id`. On match in `success/`, mark `completed`. On match in `failure/` or `stopped/`, mark `failed`.
     - Else mark `failed` with `failure_reason: "state-file-disappeared"`.
   - Persist updated parent state under parent's `flock` (single write at end of sweep).
2. Order is mandated: live → history → orphan. Document inline.
3. Cost target: ≤N `stat` calls + ≤3 directory reads per parent hook fire. Cache `history/` directory reads within a single sweep.
4. Emit `wait_all_polling` log entry (FR-008).

**Files**: `plugin-wheel/src/lib/dispatch.ts` (helper lives here, called from `dispatchTeamWait`).

### Phase 4 — Hook handler simplification (FR-005)

**Goal**: `teammate_idle` and `subagent_stop` route to `dispatchTeamWait` `post_tool_use` branch.

**Steps**:
1. Locate the `teammate_idle` and `subagent_stop` hook entry points (likely `engine.ts` or a dispatch router).
2. Strip any `team-wait`-specific status-update logic. Keep only: resolve parent state file (existing logic), if parent's current step is `team-wait`, call `dispatchTeamWait(step, "post_tool_use", hookInput, parentStateFile, parentStepIndex)`.
3. Otherwise no-op (`{decision: "approve"}`).

**Files**: `plugin-wheel/src/lib/dispatch.ts`, `plugin-wheel/src/lib/engine.ts` (whichever owns hook routing).

### Phase 5 — Logging + lock-ordering doc (FR-007, FR-008)

**Goal**: All required log entries emit; FR-007 invariant codified.

**Steps**:
1. Verify `archive_parent_update` log emits in `_updateParentTeammateSlot` with all required fields.
2. Verify `wait_all_polling` log emits in `_runPollingBackstop` with all required fields.
3. Add comment block in `state.ts` next to locking helpers documenting child→parent lock ordering invariant. Reference FR-007.

**Files**: `plugin-wheel/src/lib/state.ts`, `plugin-wheel/src/lib/dispatch.ts`.

### Phase 6 — Tests (NON-NEGOTIABLE — ≥80% coverage gate per Constitution Article II)

**Goal**: Unit + E2E coverage matching FR-001 through FR-008 acceptance scenarios.

**Steps**:
1. Extend `plugin-wheel/src/lib/state.test.ts` with `archiveWorkflow` tests:
   - Single-teammate archive updates parent slot.
   - All-teammates-done triggers cursor advance.
   - Parent at unexpected cursor leaves slot updated, no advance.
   - Concurrent archives (use `Promise.all` of two `archiveWorkflow` calls — both updates land under lock).
   - Failure bucket → `status: "failed"`.
   - Missing parent state file → warning log, no throw.
2. Extend `plugin-wheel/src/lib/dispatch.test.ts` (or add `dispatch-team-wait.test.ts`):
   - `stop` branch with all teammates done → step marked done.
   - `stop` branch with one teammate running → step stays `working`.
   - `post_tool_use` polling backstop: live state file → no change.
   - Polling: archive in `history/success/` → teammate `completed`.
   - Polling: archive in `history/failure/` → teammate `failed`.
   - Polling: no live state, no archive → `failed: state-file-disappeared`.
   - Polling order assertion: archive evidence wins over orphan default.
3. Add E2E fixture coverage. The three Phase 4 fixtures (`team-static`, `team-dynamic`, `team-partial-failure`) ALREADY exist; this PRD makes them pass. Add a NEW Phase 4 fixture `team-force-kill-recovery` that simulates the FR-004 backstop end-to-end (or document why the existing `team-partial-failure` covers it).
4. Verify coverage via `npm test` + coverage tooling. New/changed code must hit ≥80% line + branch.

**Files**: `plugin-wheel/src/lib/state.test.ts`, `plugin-wheel/src/lib/dispatch.test.ts` (or new `dispatch-team-wait.test.ts`), `plugin-wheel/tests/team-force-kill-recovery/` (if added).

### Phase 7 — Phase 4 fixture validation + smoke

**Goal**: SC-001 hit. Validate against live `/wheel:wheel-test`.

**Steps**:
1. Run `/wheel:wheel-test` from a clean checkout.
2. Assert all 3 Phase 4 fixtures PASS.
3. Verify zero orphan `state_*.json` files in `.wheel/` post-run.
4. Manually test SC-003 force-kill scenario per `plugin-wheel/docs/isolated-workflow-testing.md` recipe.
5. Update `plugin-wheel/CHANGELOG.md` (if it exists) and re-confirm Phase 4 fixtures' READMEs are accurate.

## Constitution Compliance

- **I. Spec-First**: spec.md exists; FRs have IDs; functions reference FRs in comments (Phase 1–5 enforce this).
- **II. 80% Coverage**: Phase 6 lists explicit test cases. Coverage gate verified before completion.
- **III. PRD as Source of Truth**: This plan does not contradict PRD. SC-2 reconciled via research.md §baseline.
- **IV. Hooks Enforce Rules**: Hooks block any `src/` edits until tasks.md exists with `[X]` markers — enforced by Phase 1 ordering (artifacts committed first).
- **V. E2E Required**: Phase 6 step 3 + Phase 7 cover E2E via `/wheel:wheel-test` Phase 4 fixtures.
- **VI. Small Focused Changes**: Each phase touches ≤2 files. Function file-size limits respected.
- **VII. Interface Contracts**: `contracts/interfaces.md` contains all signatures (see deliverable below).
- **VIII. Incremental Task Completion**: tasks.md (next deliverable) breaks Phase 1–7 into tasks; implementer marks `[X]` immediately after each completes.

## Risks & Mitigations

(Inherited from PRD §Risks/Unknowns; mitigations confirmed plan-side)

- **R-1 (lock ordering deadlock)**: Mitigation: FR-007 invariant documented in code; auditor greps for `lock(child).+lock(parent)` patterns. ✅ codified in Phase 5.
- **R-2 (FR-001 succeeds, rename fails)**: Mitigation: parent update is idempotent. Re-running archive on the same child produces same `completed` status. ✅ tests cover.
- **R-3 (parent at unexpected cursor)**: Mitigation: FR-002 guards on parent step type before advance. ✅ tested in Phase 6 step 1.
- **R-4 (composition + team interaction)**: Mitigation: archive helper does FR-001/FR-002 first; if parent step is NOT `team-wait`, falls through to existing `_chain_parent_after_archive`. Disjoint paths. ✅ Phase 1 step 4 codifies.
- **R-5 (false-positive orphan during slow archive)**: Mitigation: FR-004 strict order (live state → history → orphan). Archive always lands in `history/` BEFORE child state file is removed because rename is the last step. ✅ tested in Phase 6 step 2.
- **R-6 (test fixtures asserting broken behavior)**: 5-min audit during Phase 7. Confirm fixtures expect Phase 4 to PASS, not FAIL.

## Open Questions Resolution

Per spec.md §Open Questions:
- **OQ-1**: No grace window. FR-004 strict order suffices.
- **OQ-2**: No auto-recurse into `team-delete` after FR-002. Next parent hook fire dispatches it (within milliseconds; the same hook returns to parent harness post-archive).
- **OQ-3**: No test-runner harness changes anticipated; re-verify during smoke (Phase 7).

## Files Touched (estimated)

- `plugin-wheel/src/lib/state.ts` — archive helper + parent-update helper + lock-ordering doc.
- `plugin-wheel/src/lib/dispatch.ts` — `dispatchTeamWait` rewrite + polling backstop + hook-handler simplification.
- `plugin-wheel/src/lib/dispatch.test.ts` (or new `dispatch-team-wait.test.ts`) — unit tests.
- `plugin-wheel/src/lib/state.test.ts` — archive helper tests.
- (Optional) `plugin-wheel/tests/team-force-kill-recovery/` — new Phase 4 fixture.
- `plugin-wheel/src/lib/engine.ts` — only IF hook routing currently lives here and needs the FR-005 simplification.

No `team-create` / `team-delete` / `teammate` / workflow JSON schema changes.

## See also

- `contracts/interfaces.md` — exact function signatures (Article VII).
- `tasks.md` — phase-by-phase task breakdown with `[ ]` markers (Article VIII).
- `research.md` — SC-2 baseline reconciliation.
