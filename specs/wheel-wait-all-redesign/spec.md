# Feature Specification: Wheel `wait-all` Redesign — Inverted Control + Polling Backstop

**Feature Branch**: `build/wheel-wait-all-redesign-20260430` (folds into `002-wheel-ts-rewrite`)
**Spec directory**: `specs/wheel-wait-all-redesign/`
**Created**: 2026-04-30
**Status**: Draft
**Input**: PRD `docs/features/2026-04-30-wheel-wait-all-redesign/PRD.md`

## Foundation Note (NON-NEGOTIABLE)

This spec extends — does NOT replace — the in-progress TypeScript code already committed on `002-wheel-ts-rewrite`. The implementer MUST read the current state of `plugin-wheel/src/lib/dispatch.ts`, `plugin-wheel/src/lib/state.ts`, and `plugin-wheel/src/lib/lock.ts` at impl start as the foundation for FR-1 through FR-8. This spec also explicitly OVERRIDES the byte-identity claim in `specs/002-wheel-ts-rewrite/spec.md` for `dispatchTeamWait` and the archive helper: those two functions deliberately deviate from shell behavior because the shell behavior is broken (see PRD §Problem/Motivation).

## User Scenarios & Testing

### User Story 1 — Reliable team-wait advancement (Priority: P1)

A workflow author activates a `team-static` workflow that fans out 3 teammate sub-workflows, then joins on a `team-wait` step. After all 3 sub-workflows archive successfully, the parent's `team-wait` step advances within seconds of the last archive — without manual recovery (no sentinel files, no `wheel-stop`).

**Why this priority**: This is the failure mode that motivates the PRD. Phase 4 fixtures fail today because `team-wait` never advances. Without this, every team workflow stalls indefinitely.

**Independent Test**: Run `tests/team-static` via the isolated `claude --print` recipe in `plugin-wheel/docs/isolated-workflow-testing.md`. Assert: parent state advances past `wait-all` cursor, no orphan `state_*.json` files remain in `.wheel/`, and exit status is 0.

**Acceptance Scenarios**:

1. **Given** a `team-static` parent workflow with 3 teammates and a `team-wait` step at cursor=5, **When** all 3 teammate sub-workflows archive to `history/success/` via the archive helper, **Then** the parent's `teams[<team>].teammates[<name>].status` is `"completed"` for all 3 names AND the parent's cursor advances to step 6 within 5 seconds of the last archive AND `wheel.log` shows three `archive_parent_update` entries.
2. **Given** a `team-static` parent at `team-wait` cursor=5 with one teammate already `completed` and two `running`, **When** a second teammate archives, **Then** the parent's slot for that teammate flips to `"completed"` AND the parent's cursor stays at 5 (one teammate still running) AND no spurious `done`-marking of the `team-wait` step.

---

### User Story 2 — Force-killed teammate recovery (Priority: P2)

A teammate sub-workflow is force-killed (SIGKILL, OS crash) and never reaches the archive path. On the parent's next `post_tool_use` hook fire, the polling backstop detects the missing state file, marks the teammate `failed`, and the parent advances with a recorded failure rather than stalling forever.

**Why this priority**: Without this, force-killed teammates produce the same indefinite stall as the original event-driven design. P2 because force-kill is rarer than graceful completion but still a required recovery path per PRD G3.

**Independent Test**: Manually run `team-static`, identify a worker PID after the team is created, send `kill -9 <pid>` before the worker archives. Verify the parent advances within 30 seconds with the killed teammate's status set to `"failed"` and `failure_reason: "state-file-disappeared"`.

**Acceptance Scenarios**:

1. **Given** a `team-static` parent with 3 teammates running, **When** one teammate's process is `kill -9`'d before archive AND the parent fires a `post_tool_use` hook, **Then** the polling backstop scans `.wheel/history/{success,failure,stopped}/` for that teammate's `alternate_agent_id`, finds nothing, sets the teammate `status: "failed"` with `failure_reason: "state-file-disappeared"` and `completed_at: now`, AND emits a `wait_all_polling` log entry.
2. **Given** a teammate whose state file is gone but whose archive landed in `history/failure/`, **When** the polling backstop runs, **Then** the teammate is marked `"failed"` (NOT `"state-file-disappeared"` — the archive evidence wins).

---

### User Story 3 — Phase 4 fixture acceptance (Priority: P1)

A kiln pipeline maintainer runs `/wheel:wheel-test`. Phase 4 fixtures (`team-static`, `team-dynamic`, `team-partial-failure`) all pass green with total Phase 4 wall time under 90 seconds.

**Why this priority**: This is the PRD's explicit acceptance gate (Absolute Must #5). P1 because it's the headline outcome.

**Independent Test**: `/wheel:wheel-test` exits 0 with all three Phase 4 fixtures reported PASS in the test-run report at `.wheel/logs/test-run-<ts>.md`.

**Acceptance Scenarios**:

1. **Given** the implemented FR-1 through FR-8, **When** `/wheel:wheel-test` runs, **Then** Phase 4 produces 3/3 PASS rows AND no orphan state files exist in `.wheel/` after the run AND wall time for Phase 4 is < 90s.
2. **Given** `team-partial-failure` fixture (one teammate intentionally fails), **When** the run completes, **Then** the parent advances with `fail_fast` / `min_completed` honored per the workflow JSON's existing options AND the failure is recorded in the parent's teammate slot.

---

### User Story 4 — Readable `dispatchTeamWait` (Priority: P3)

A wheel internals reader opens `dispatchTeamWait` in `plugin-wheel/src/lib/dispatch.ts` and finds a single short function with one re-check helper — not a 4-branch switch handling event types they have to mentally trace through `guard.sh`.

**Why this priority**: Maintenance ergonomics. P3 because it's secondary to correctness, but it's the architectural intent of the redesign.

**Independent Test**: `wc -l` of `dispatchTeamWait` after the change is ≤132 lines (per research.md §baseline → ≤132 from baseline 189). Function contains exactly two top-level branches: `stop` and `post_tool_use`.

**Acceptance Scenarios**:

1. **Given** the implemented FR-3, **When** a reader counts top-level `if (hookType === 'X')` branches in `dispatchTeamWait`, **Then** they find exactly 2 (`stop`, `post_tool_use`) AND no inline `Agent` / `TaskUpdate` mutation logic — those are removed because parent updates come from FR-1.
2. **Given** the implemented FR-3, **When** `awk` extracts the function span, **Then** `wc -l` reports ≤132 lines.

---

### Edge Cases

- **EC-1**: Parent state file missing during FR-1 (parent already archived, or wheel-stop ran). Behavior: log warning with phase `archive_parent_update_skipped`, proceed with rename. No throw.
- **EC-2**: Parent at unexpected cursor when child archives (sibling teammate already advanced parent past `team-wait`). Behavior: FR-1 still updates the slot (idempotent), FR-2 skips cursor advance.
- **EC-3**: Two teammates archiving simultaneously. Behavior: each acquires parent's `flock` independently, updates disjoint fields, commits. Lock contention serializes the writes; both updates land.
- **EC-4**: `state-file-disappeared` false-positive during slow archive. Behavior: FR-4 checks `history/{success,failure,stopped}/` BEFORE concluding orphan. Order is mandated in FR-4.
- **EC-5**: Teammate with name suffix from harness re-spawn (`worker-1-2`). Behavior: FR-1 matches on `alternate_agent_id` (stable across re-spawns), NOT on harness-assigned name. The parent's teammate dict key is whatever the team was created with — FR-1 looks up by `agent_id` field, not dict key string equality.
- **EC-6**: Composition (`workflow`-step parent containing a `team-wait` child). Behavior: FR-1 runs first; if parent is at a `team-wait` step targeting this team, do FR-2; otherwise fall through to existing `_chain_parent_after_archive`. Paths are disjoint by parent step type.

## Requirements

### Functional Requirements

- **FR-001 (PRD FR-1)**: The TS archive helper MUST update the parent state file's teammate slot before performing the rename. Match by child's `alternate_agent_id` against `parent.teams[<team_id>].teammates[<name>].agent_id`. On match, set `status` to `"completed"` (success archive) or `"failed"` (failure archive), set `completed_at` to ISO-8601 UTC. Persist under parent's `flock`.

- **FR-002 (PRD FR-2)**: After FR-001 update, IF parent's current step is `team-wait` AND its `team` field matches the updated team_id AND every teammate has `status` of `"completed"` or `"failed"`, the archive helper MUST mark the parent's `team-wait` step `done`, set `completed_at`, write summary `output`, and advance cursor (running `advance_past_skipped` if next step is conditionally skipped). Persist under parent's `flock`. If parent is at a different cursor, leave the slot update in place and do not advance.

- **FR-003 (PRD FR-3)**: `dispatchTeamWait` MUST collapse to two top-level branches: `stop` and `post_tool_use`. The `subagent_stop` and `teammate_idle` cases reuse the `post_tool_use` re-check path. The function MUST NOT contain branch-specific logic that mutates teammate status; all status mutations come from FR-001 (primary) or FR-004 (backstop).

- **FR-004 (PRD FR-4)**: The `post_tool_use` re-check MUST run a polling backstop. For each teammate currently `status == "running"`:
  1. Look up live state files (`.wheel/state_*.json`) by `alternate_agent_id`. If found, skip.
  2. Else scan `.wheel/history/{success,failure,stopped}/` for an archive whose `parent_workflow` equals THIS parent's state file path AND whose `alternate_agent_id` matches the teammate. Mark `completed` (success bucket), `failed` (failure or stopped bucket).
  3. Else mark `failed` with `failure_reason: "state-file-disappeared"` and `completed_at: now`.
  Order MUST be: live state → history → orphan. After reconciliation, run the FR-003 done-check.

- **FR-005 (PRD FR-5)**: `teammate_idle` and `subagent_stop` hook handlers MUST NOT contain `team-wait`-specific status update logic. They resolve the parent state file (existing logic), then if the parent's current step is `team-wait`, dispatch to `dispatchTeamWait` with `hook_type: "post_tool_use"`. Otherwise no-op (`{"decision": "approve"}`).

- **FR-006 (PRD FR-6)**: When a child archives to `history/failure/` (the workflow's terminal step set `status: "failed"`), FR-001 MUST set the parent teammate's `status: "failed"`. The parent's `_team_wait_complete` continues honoring existing `fail_fast` / `min_completed` workflow JSON options unchanged.

- **FR-007 (PRD FR-7)**: Concurrent teammate archives MUST both update parent state without losing either update. Each FR-001 update operates on disjoint fields and acquires parent's `flock` before reading and holds it through the write. Lock-ordering invariant: nothing in wheel takes a child lock while holding a parent lock. This invariant MUST be documented as a comment block in `plugin-wheel/src/lib/state.ts` next to the locking helpers.

- **FR-008 (PRD FR-8)**: Logging:
  - Every FR-001 invocation MUST emit a `wheel.log` entry with phase `archive_parent_update` recording `child_agent_id`, `parent_state_file`, `team_id`, `teammate_name`, `new_status`, `cursor_advanced` (boolean).
  - Every FR-004 sweep MUST emit a `wheel.log` entry with phase `wait_all_polling` recording `parent_state_file`, `team_id`, `reconciled_count`, `still_running_count`.

- **FR-009**: The TS archive helper MUST be a single deterministic call path. Every workflow that archives goes through it (matches the shell behavior asserted in PRD Assumptions). The helper lives in `plugin-wheel/src/lib/state.ts` (or wherever the rewrite parks rename-to-history; final placement decided in plan.md).

- **FR-010**: Workflow JSON schema unchanged. `team-wait`, `team-create`, `teammate` step shapes stay byte-identical to the rewrite's current schema. State-file schema (`teams.<id>.teammates.<name>` shape, `parent_workflow` field, `alternate_agent_id` field) unchanged.

- **FR-011**: No regression in Phases 1–3. `command`, `branch`, `loop`, `agent`, `workflow` (composition) step types and the existing `_chain_parent_after_archive` path stay byte-identical to the rewrite's behavior. Verified by `/wheel:wheel-test` Phase 1–3 still PASS post-change.

### Key Entities

- **Parent state file**: `.wheel/state_<workflow>.json` for the workflow that owns a `team-wait` step. Holds `teams[<team_id>].teammates[<name>]` slots whose status changes are the cross-process signal.
- **Child sub-workflow state file**: `.wheel/state_<workflow>_<teammate>.json`. Has `parent_workflow` (absolute path to parent state file) and `alternate_agent_id` (stable identifier for matching against parent slots, immune to harness name suffixing).
- **Archive bucket**: `.wheel/history/{success,failure,stopped}/<archive>.json`. The archive function moves child state files here and records the bucket choice based on terminal step status.
- **`teammate` slot**: `parent.teams[<team_id>].teammates[<name>]` — has `agent_id`, `status` (`pending`/`running`/`completed`/`failed`), `started_at`, `completed_at`, optional `failure_reason`.

## Success Criteria

### Measurable Outcomes

- **SC-001 (PRD SC-1)**: Phase 4 fixtures (`team-static`, `team-dynamic`, `team-partial-failure`) all pass via `/wheel:wheel-test` with exit 0 and zero orphan state files in `.wheel/`. Verified within 1 week of merge.
- **SC-002 (PRD SC-2)**: `dispatchTeamWait` source ≤132 lines (30% reduction from baseline 189; see research.md §baseline). Measured by `awk 'NR>=<start> { print; if (/^}/ && NR><start>) { exit } }' plugin-wheel/src/lib/dispatch.ts | wc -l` after FR-3 lands.
- **SC-003 (PRD SC-3)**: Force-kill recovery works. Manual test: activate `team-static`, `kill -9` one worker before its archive, observe parent advance via FR-004 within 30s.
- **SC-004**: Phase 4 wall time <90s under `/wheel:wheel-test`.
- **SC-005**: `wheel.log` shows the expected `archive_parent_update` entries (one per teammate per Phase 4 fixture run) and `wait_all_polling` entries (≥1 per parent `post_tool_use` hook fire while `team-wait` is open). Grep-verifiable.
- **SC-006**: Lock-ordering invariant has a `// FR-007` comment block in `plugin-wheel/src/lib/state.ts`. Grep-verifiable.

## Assumptions

- Implementer reads `plugin-wheel/src/lib/dispatch.ts`, `state.ts`, and `lock.ts` at impl start as foundation; does not reset the branch.
- The TS archive helper either exists at impl start (extend it) or doesn't (author it, using shell `_archive_workflow` in `plugin-wheel/lib/dispatch.sh:122–318` as the behavioral reference for rename + bucket-selection).
- `child.parent_workflow` is reliably populated with absolute path post-teammate-spawn (existing contract verified at PRD time).
- `state_*.json` schema stable: `teams.<id>.teammates.<name>.agent_id` and `.status` fields persist across the rewrite. Verified at PRD time.
- `flock`-equivalent atomic-write helper in `plugin-wheel/src/lib/lock.ts` supports per-file locking on absolute paths.
- Polling cost (`stat` + 3-bucket `ls`) on every parent `post_tool_use` is acceptable: with <100 archived workflows in a typical session, this is <5 ms per hook.
- This PRD ships as part of `002-wheel-ts-rewrite` PR — no separate fast-follow.

## Open Questions

The PRD listed Q1, Q2, Q3 as plan-time deferrals. The plan resolves them as follows (carried forward to plan.md):

- **OQ-1 (PRD Q1)**: FR-004 has no grace window. Mitigation is the strict order in FR-4 (live state → history → orphan), which already protects against in-flight archive false-positives because the rename happens AFTER the parent update. By the time the child state file disappears, the archive is on disk in `history/`. Decided: no grace window.
- **OQ-2 (PRD Q2)**: After FR-002 cursor advance, the parent does NOT auto-chain into `team-delete`. It stops after the cursor bump and waits for the next parent hook fire (which arrives within milliseconds because the same archive hook that did FR-002 returns to the parent harness). Decided: no recursion.
- **OQ-3 (PRD Q3)**: No test-runner harness changes anticipated. Existing `wheel-test-runner.sh` Phase 4 timeouts are sufficient. Re-verify during smoke.

## Out of Scope

(Inherited from PRD Non-Goals)

- Port of shell `dispatch_team_wait` (deliberate behavioral change).
- Rewrite of `team-create` / `team-delete` / teammate spawn primitives.
- Discard of in-progress fix code on `002-wheel-ts-rewrite`.
- Fix for shell wheel (stays broken on Phase 4).
- Redesign of `parent_workflow` semantics for plain workflow composition.
- Lock-protocol generalization.
- New step type or schema change.
