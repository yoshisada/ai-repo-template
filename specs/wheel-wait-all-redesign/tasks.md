# Tasks: Wheel `wait-all` Redesign

**Feature**: wheel-wait-all-redesign
**Branch**: `build/wheel-wait-all-redesign-20260430` (folds into `002-wheel-ts-rewrite`)
**Constitution Article VIII**: Mark each task `[X]` IMMEDIATELY upon completion. Commit after each phase. Do NOT batch checkmarks at the end.

Hooks block any `src/` edits until at least ONE task is `[X]`. The first task (T-001) intentionally does not touch `src/` so the implementer can begin without hook blockage.

---

## Phase 0 — Foundation read (NO src/ edits)

- [X] **T-001** [Foundation] Read CURRENT branch state of foundation files. Capture brief notes (≤200 words) at `specs/wheel-wait-all-redesign/agent-notes/implementer-foundation.md` summarizing:
  - Current `dispatchTeamWait` shape (line span, branches present)
  - Whether a TS `archiveWorkflow` already exists in `state.ts` or if it must be authored
  - Current `lock.ts` API surface (function names + signatures)
  - Current `wheelLog` (or equivalent) API surface
  - Hook-routing entry point for `teammate_idle` / `subagent_stop`
  - Files: read `plugin-wheel/src/lib/{dispatch.ts,state.ts,lock.ts,log.ts,engine.ts}` + `plugin-wheel/lib/dispatch.sh:122-318`. Mark `[X]` after the notes file is written.

---

## Phase 1 — Archive helper extension (FR-001, FR-002, FR-006, FR-009)

- [X] **T-002** [P1] Implement (or extend) `archiveWorkflow(stateFile, bucket): Promise<string>` in `plugin-wheel/src/lib/state.ts` per `contracts/interfaces.md`. Body wires: read child state → if `parent_workflow` non-null, call `stateUpdateParentTeammateSlot` → call `maybeAdvanceParentTeamWaitCursor` → rename child to `history/<bucket>/`. Add `// FR-001, FR-009` comments.
- [X] **T-003** [P1] Implement `stateUpdateParentTeammateSlot(parentStateFile, childAlternateAgentId, newStatus): Promise<{teamId, teammateName} | null>` in `state.ts` per contract. Acquires parent flock; finds slot by `agent_id` match; sets `status` + `completed_at`. Emits `archive_parent_update` log (FR-008). Add `// FR-001, FR-006, FR-007, FR-008` comments.
- [X] **T-004** [P1] Implement `maybeAdvanceParentTeamWaitCursor(parentStateFile, teamId): Promise<boolean>` in `state.ts` per contract. Guards on parent step type AND team match AND all-teammates-done. Calls existing `advance_past_skipped` semantics. Acquires parent flock. Add `// FR-002` comment.
- [X] **T-005** [P1] Document FR-007 lock-ordering invariant as a comment block in `state.ts` adjacent to locking helpers. Reference grep target `// FR-007` per SC-006.
- [X] **T-006** [P1] Commit Phase 1 with message `feat(wheel-ts): archive helper updates parent teammate slot (FR-001, FR-002, FR-006, FR-007, FR-009)`. Mark T-002 through T-006 `[X]`.

---

## Phase 2 — `dispatchTeamWait` rewrite (FR-003)

- [ ] **T-007** [P2] Extract private helper `_recheckAndCompleteIfDone(stateFile, stepIndex, teamRef): Promise<boolean>` in `plugin-wheel/src/lib/dispatch.ts` per contract. Pure re-check; marks step done via `stateSetStepStatus` if all teammates are completed/failed. Add `// FR-003` comment.
- [ ] **T-008** [P2] Rewrite `dispatchTeamWait` body to two top-level branches: `stop` and `post_tool_use`. Delete the entire `teammate_idle` branch. Delete inline `Agent`/`TaskUpdate` mutation logic. (Teammate `agent_id` registration moves to wherever the team-create / teammate spawn dispatcher already handles it — implementer decides based on T-001 notes.) Add `// FR-003` comment.
- [ ] **T-009** [P2] Verify SC-002 line count: run `awk 'NR>=<dispatchTeamWait_start> { print; if (/^}/ && NR><start>) { exit } }' plugin-wheel/src/lib/dispatch.ts | wc -l`. Assert ≤132 lines. If over, simplify before marking T-009 `[X]`.
- [ ] **T-010** [P2] Commit Phase 2 with message `feat(wheel-ts): dispatchTeamWait collapses to two branches (FR-003, SC-002)`. Mark T-007 through T-010 `[X]`.

---

## Phase 3 — Polling backstop (FR-004)

- [ ] **T-011** [P3] Implement `_runPollingBackstop(parentStateFile, teamRef): Promise<{reconciledCount, stillRunningCount}>` in `dispatch.ts` per contract. Order: live state files → `history/{success,failure,stopped}` → orphan default. Single parent flock acquisition for all writes. Cache `history/` directory reads within the sweep. Emits `wait_all_polling` log (FR-008). Add `// FR-004, FR-008` comment.
- [ ] **T-012** [P3] Wire `_runPollingBackstop` into the `post_tool_use` branch of `dispatchTeamWait` (run BEFORE `_recheckAndCompleteIfDone`). Add `// FR-004` comment.
- [ ] **T-013** [P3] Commit Phase 3 with message `feat(wheel-ts): polling backstop reconciles orphan teammates (FR-004, FR-008)`. Mark T-011 through T-013 `[X]`.

---

## Phase 4 — Hook handler simplification (FR-005)

- [ ] **T-014** [P4] Locate `teammate_idle` and `subagent_stop` hook routing entry points (per T-001 notes). Strip any `team-wait`-specific status update logic. Replace with: resolve parent state file → if parent's current step is `team-wait`, dispatch to `dispatchTeamWait(step, 'post_tool_use', hookInput, parentStateFile, parentStepIndex)`. Otherwise return `{decision: 'approve'}`. Add `// FR-005` comments.
- [ ] **T-015** [P4] Commit Phase 4 with message `feat(wheel-ts): teammate_idle and subagent_stop become wake-up nudges (FR-005)`. Mark T-014, T-015 `[X]`.

---

## Phase 5 — Tests (FR-001 through FR-008; ≥80% coverage gate per Article II)

- [ ] **T-016** [P5] Extend `plugin-wheel/src/lib/state.test.ts` with `archiveWorkflow` tests covering: single-teammate archive updates parent slot; all-done triggers cursor advance; parent at unexpected cursor leaves slot updated and does NOT advance; concurrent archives via `Promise.all` (both updates land); failure bucket → `status: "failed"`; missing parent state file → log warning, no throw. Each test references its FR/AC in a comment.
- [ ] **T-017** [P5] Add `plugin-wheel/src/lib/dispatch-team-wait.test.ts` (or extend `dispatch.test.ts`) covering: `stop` branch all-done → step done; `stop` branch one running → step stays working; `post_tool_use` polling no-op when live state present; polling marks `completed` when archive in `history/success/`; polling marks `failed` when archive in `history/failure/`; polling marks `failed: state-file-disappeared` when nothing matches; polling order asserted (archive evidence wins over orphan default). Each test references its FR/AC.
- [ ] **T-018** [P5] (Optional, only if T-001 notes flag a gap) Add new Phase 4 fixture `plugin-wheel/tests/team-force-kill-recovery/` exercising FR-004 end-to-end via the isolated-test recipe. If `team-partial-failure` already covers the orphan path, document that in T-018's checkmark line and skip the new fixture.
- [ ] **T-019** [P5] Run `npm test` (or `vitest run`) with coverage. Verify ≥80% line + branch coverage on new/changed code in `state.ts` and `dispatch.ts`. If under, add targeted tests before marking `[X]`.
- [ ] **T-020** [P5] Commit Phase 5 with message `test(wheel-ts): unit + integration coverage for wait-all redesign (FR-001..008)`. Mark T-016 through T-020 `[X]`.

---

## Phase 6 — Phase 4 fixture validation + smoke (SC-001, SC-003, SC-004)

- [ ] **T-021** [P6] Run `/wheel:wheel-test` from a clean checkout. Assert all 3 Phase 4 fixtures (`team-static`, `team-dynamic`, `team-partial-failure`) PASS in `.wheel/logs/test-run-<ts>.md`. Assert zero orphan `state_*.json` files in `.wheel/`. Assert Phase 4 wall time <90s (SC-004). Save the run report path in T-021's checkmark line.
- [ ] **T-022** [P6] Manual SC-003 force-kill test per `plugin-wheel/docs/isolated-workflow-testing.md`: activate `team-static`, `kill -9` one worker before its archive, observe parent advance via FR-004 within 30s with `failure_reason: "state-file-disappeared"`. Record the resulting parent state-file diff in T-022's checkmark line.
- [ ] **T-023** [P6] Grep-verify SC-005 / SC-006: `git grep -F "archive_parent_update"`, `git grep -F "wait_all_polling"`, `git grep -F "// FR-007"` all return ≥1 hit each. Mark `[X]` with the hit counts.
- [ ] **T-024** [P6] Commit Phase 6 with message `chore(wheel-ts): smoke + grep verification for wait-all redesign (SC-001, SC-003, SC-004, SC-005, SC-006)`. Mark T-021 through T-024 `[X]`.

---

## Phase 7 — Audit + handoff

- [ ] **T-025** [P7] Run `/kiln:audit` (or invoke prd-auditor agent). Address any PRD→Spec→Code→Test gaps. Document unfixable gaps in `specs/wheel-wait-all-redesign/blockers.md`.
- [ ] **T-026** [P7] Write implementer friction note to `specs/wheel-wait-all-redesign/agent-notes/implementer.md` covering: anything ambiguous in spec/plan/contracts, anything that took more than expected, anything to flag for the team-lead.
- [ ] **T-027** [P7] Final commit of any audit fixes + friction note with message `chore(wheel-ts): audit fixes + implementer friction note for wait-all redesign`. Mark T-025 through T-027 `[X]`.

---

## Dependency graph

- T-001 unblocks all downstream phases.
- Phase 1 (T-002..T-006) blocks Phase 2 (parent-update functions are called by `dispatchTeamWait`'s eventual `_recheck` path indirectly via archive flow, AND tests in Phase 5 depend on Phase 1's helpers).
- Phase 2 (T-007..T-010) and Phase 3 (T-011..T-013) MAY interleave at the implementer's discretion, but Phase 3's `_runPollingBackstop` is wired into Phase 2's `post_tool_use` branch via T-012, so T-012 depends on T-008.
- Phase 4 (T-014..T-015) depends on Phase 2 (it routes to `dispatchTeamWait`).
- Phase 5 (T-016..T-020) depends on Phases 1–4.
- Phase 6 (T-021..T-024) depends on Phase 5 (tests pass before live smoke).
- Phase 7 (T-025..T-027) depends on Phase 6.

## FR → task traceability

| FR | Tasks |
|---|---|
| FR-001 | T-002, T-003, T-016 |
| FR-002 | T-004, T-016 |
| FR-003 | T-007, T-008, T-009, T-017 |
| FR-004 | T-011, T-012, T-017, T-022 |
| FR-005 | T-014, T-017 |
| FR-006 | T-003, T-016 |
| FR-007 | T-005, T-023 |
| FR-008 | T-003, T-011, T-023 |
| FR-009 | T-002 |
| FR-010 | (schema invariants, asserted by T-019 + T-021) |
| FR-011 | T-021 (Phase 1–3 fixtures still PASS) |

## SC → task traceability

| SC | Verifying task |
|---|---|
| SC-001 | T-021 |
| SC-002 | T-009 |
| SC-003 | T-022 |
| SC-004 | T-021 |
| SC-005 | T-023 |
| SC-006 | T-023 |

## Notes

- Constitution Article VIII: each task → `[X]` immediately on completion, NOT batched.
- Hooks block `src/` edits until at least one task is `[X]`. T-001 (notes file, not src/) is the unblocker.
- Thresholds reconciled against `research.md` §baseline (189 → ≤132 lines).
