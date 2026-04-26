---
description: "Task list for escalation-audit feature implementation"
---

# Tasks: Escalation Audit — Detect Stuck State + Auto-Flip Item Lifecycle

**Input**: `specs/escalation-audit/spec.md`, `specs/escalation-audit/plan.md`, `specs/escalation-audit/contracts/interfaces.md`
**Prerequisites**: spec.md (FR-001..FR-016, NFR-001..NFR-005, SC-001..SC-007), plan.md, contracts/interfaces.md.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel — different files, no dependencies, no shared SKILL.md edits.
- **[Story]**: Maps to spec user story (US1..US5).
- File paths are exact and absolute under repo root.

## Implementer Assignment (FIXED — concurrent-staging hazard)

- **`impl-themes-ab`** owns Phases 1, 3, 4, 5 (all edits to `kiln-build-prd/SKILL.md` + Theme A scripts + `kiln-roadmap` SKILL.md). Sequential within owner.
- **`impl-theme-c`** owns Phases 2 (its own setup), 6, 7. Independent of Themes A + B.
- Both implementers can start in parallel after Phase 1 + Phase 2 each complete.

---

## Phase 1: Setup — Theme A + B shared (impl-themes-ab)

**Purpose**: Confirm working tree is clean and the constitution + spec are read. No code edits yet.

- [X] T001 [impl-themes-ab] Read `.specify/memory/constitution.md`, `specs/escalation-audit/spec.md`, `specs/escalation-audit/plan.md`, `specs/escalation-audit/contracts/interfaces.md` end-to-end before any edit.
- [X] T002 [impl-themes-ab] Verify `git status` is clean on `build/escalation-audit-20260426`. If dirty, stash before starting.

---

## Phase 2: Setup — Theme C (impl-theme-c) [P with Phase 1]

- [X] T003 [impl-theme-c] Read `.specify/memory/constitution.md`, `specs/escalation-audit/spec.md`, `specs/escalation-audit/plan.md`, `specs/escalation-audit/contracts/interfaces.md` end-to-end before any edit.
- [X] T004 [impl-theme-c] Confirm `plugin-kiln/skills/kiln-escalation-audit/` does NOT exist yet (skill is being created fresh).

---

## Phase 3: User Story 1 — Auto-flip on PR merge (P1) 🎯 MVP — impl-themes-ab

**Goal**: Step 4b.5 auto-flip sub-step + extended `update-item-state.sh --status` flag.
**Independent Test**: `plugin-kiln/tests/build-prd-auto-flip-on-merge/run.sh` returns PASS.

### Implementation

- [X] T010 [impl-themes-ab] [US1] Extend `plugin-kiln/scripts/roadmap/update-item-state.sh` per `contracts/interfaces.md` §A.1: parse optional `--status <value>` flag; rewrite BOTH `state:` and `status:` in one atomic awk + tempfile + mv cycle; preserve existing `<state>`-only API byte-identically. Add `# FR-002` comment on every new branch.
- [X] T011 [impl-themes-ab] [US1] In `plugin-kiln/skills/kiln-build-prd/SKILL.md`, append a new sub-section `### Step 4b.5: Auto-flip roadmap items on merge (FR-001..FR-004, NFR-001)` AFTER the existing Step 4b commit block (around line 1010 of current SKILL.md) and BEFORE `## Step 5: Retrospective`. Use the inline Bash from `contracts/interfaces.md` §A.2 verbatim. Mark each block with the FR reference.
- [X] T012 [impl-themes-ab] [US1] Verify Step 4b.5 emits the exact diagnostic line from §A.2 (anchored regex). Add a one-line verification regex comment in the SKILL.md body so the test harness can assert against it.
- [X] T013 [impl-themes-ab] [US1] Idempotency: confirm the patch_pr_and_date inline awk MUST detect existing `pr:` lines and skip them (FR-004); never overwrite `shipped_date:` once present.

### Test for User Story 1

- [ ] T014 [impl-themes-ab] [US1] Create `plugin-kiln/tests/build-prd-auto-flip-on-merge/run.sh` per `contracts/interfaces.md` §D.1. Test cites SC-001 in a header comment.
- [ ] T015 [impl-themes-ab] [US1] Verify `plugin-kiln/tests/build-prd-auto-flip-on-merge/run.sh` returns PASS locally (one PR_STATE=MERGED case, one PR_STATE=OPEN case, one idempotency re-run case).

**Checkpoint**: Phase 3 ends with US1 fully shippable. Commit before moving to Phase 4.

- [ ] T016 [impl-themes-ab] Commit Phase 3 with message `feat(build-prd): step 4b.5 auto-flip roadmap items on PR merge (FR-001..FR-004)`.

---

## Phase 4: User Story 2 — `--check` merged-PR cross-reference (P1) — impl-themes-ab

**Goal**: `/kiln:kiln-roadmap --check` flags drifted items via merged-PR resolution.
**Independent Test**: `plugin-kiln/tests/roadmap-check-merged-pr-drift-detection/run.sh` returns PASS.

### Implementation

- [ ] T020 [impl-themes-ab] [US2] In `plugin-kiln/skills/kiln-roadmap/SKILL.md` §C (Consistency check), append `### Check 5: Merged-PR drift (FR-005)` after the existing Checks 1–4 inside the per-item walk loop. Use the pseudo-code from `contracts/interfaces.md` §A.3 verbatim.
- [ ] T021 [impl-themes-ab] [US2] Add the heuristic-fallback block (R-2 mitigation) — prefer `git for-each-ref --points-at <merge-sha>`, then `build/<theme>-<YYYYMMDD>` heuristic. Document the chosen path in each drift row's `resolution=` field.
- [ ] T022 [impl-themes-ab] [US2] In §C's report assembly, append a Notes-section row for every drift entry whose `resolution=heuristic` (R-2 documentation requirement).
- [ ] T023 [impl-themes-ab] [US2] Confirm NFR-004 backward compat: items with EMPTY `prd:` field MUST skip the new check entirely. Inspect Check 5 entry condition.

### Test for User Story 2

- [ ] T024 [impl-themes-ab] [US2] Create `plugin-kiln/tests/roadmap-check-merged-pr-drift-detection/run.sh` per `contracts/interfaces.md` §D.2. Test cites SC-002.
- [ ] T025 [impl-themes-ab] [US2] Verify the fixture covers: (a) ref-walk-resolved drift, (b) heuristic-fallback drift, (c) item with empty `prd:` (no false-positive), (d) `gh pr list` returning `[]` (no flag).
- [ ] T026 [impl-themes-ab] [US2] Run the fixture; assert PASS.

**Checkpoint**: Phase 4 ends with US2 fully shippable.

- [ ] T027 [impl-themes-ab] Commit Phase 4 with message `feat(roadmap): --check merged-PR cross-reference (FR-005)`.

---

## Phase 5: User Story 3 — Shutdown-nag loop (P2) — impl-themes-ab

**Goal**: Step 6 `/loop` shutdown-nag pass with 60s ticks, 10-tick cap, force-shutdown fallback.
**Independent Test**: `plugin-kiln/tests/build-prd-shutdown-nag-loop/run.sh` returns PASS.

### Implementation

- [ ] T030 [impl-themes-ab] [US3] In `plugin-kiln/skills/kiln-build-prd/SKILL.md` Step 6, AFTER the existing initial `shutdown_request` broadcast (current step 3 in Step 6, around line 1169) and BEFORE `5. Wait for all teammates to shut down`, insert a new sub-section `### 3a. Shutdown-nag loop (FR-007..FR-009, NFR-005)`.
- [ ] T031 [impl-themes-ab] [US3] In sub-section 3a, document the tick contract from `contracts/interfaces.md` §B.1 verbatim: `ScheduleWakeup({delaySeconds: 60, prompt: "<<autonomous-loop-dynamic>>", reason: ...})` invocation; tick body sequence; emit lines for `re-poke` / `force-shutdown` / `team-empty`; env-var `KILN_SHUTDOWN_NAG_MAX_TICKS` (default 10).
- [ ] T032 [impl-themes-ab] [US3] Document NFR-005: re-sending `shutdown_request` to a terminated teammate is a no-op (emit `action=already-terminated reason=` instead of `re-poke`).
- [ ] T033 [impl-themes-ab] [US3] Document the substrate gap (B-1) inline: full `/loop` integration test deferred; FR-010 verifies via direct text assertions only.

### Test for User Story 3

- [ ] T034 [impl-themes-ab] [US3] Create `plugin-kiln/tests/build-prd-shutdown-nag-loop/run.sh` per `contracts/interfaces.md` §D.3. Test cites SC-003.
- [ ] T035 [impl-themes-ab] [US3] Verify the fixture greps for the four required patterns (`ScheduleWakeup` + `delaySeconds: 60`; `KILN_SHUTDOWN_NAG_MAX_TICKS`; `TaskStop`; `team-empty`).
- [ ] T036 [impl-themes-ab] [US3] Run fixture; assert PASS.

**Checkpoint**: Phase 5 ends with US3 fully shippable.

- [ ] T037 [impl-themes-ab] Commit Phase 5 with message `feat(build-prd): step 6 shutdown-nag /loop pass (FR-007..FR-010)`.

- [ ] T038 [impl-themes-ab] Write `specs/escalation-audit/agent-notes/impl-themes-ab.md` with friction notes (any unclear contract, blockers encountered, deferrals).

---

## Phase 6: User Story 4 — `/kiln:kiln-escalation-audit` skill (P1) — impl-theme-c [P with Phase 3+4+5]

**Goal**: New skill that inventories pause events into a markdown report.
**Independent Test**: `plugin-kiln/tests/escalation-audit-inventory-shape/run.sh` returns PASS.

### Implementation

- [X] T040 [impl-theme-c] [US4] Create directory `plugin-kiln/skills/kiln-escalation-audit/`.
- [X] T041 [impl-theme-c] [US4] Create `plugin-kiln/skills/kiln-escalation-audit/SKILL.md` with the metadata block from `contracts/interfaces.md` §C.1 + the three source ingestors (wheel, confirm-never-silent, hook-block) + sort logic + report assembly. Cite FR-011..FR-014 in section anchors.
- [X] T042 [impl-theme-c] [US4] Implement the empty-corpus path (FR-013) — body reads `No pause events found in the last 30 days` when total count == 0.
- [X] T043 [impl-theme-c] [US4] Implement the verdict-deferred placeholder (FR-014) — `## Notes` section ends with the literal string from spec FR-014.
- [X] T044 [impl-theme-c] [US4] Implement ISO-8601 UTC normalization across sources (OQ-3 / NFR-003) — wheel JSON `started_at` is primary; git log `%aI`; for `.kiln/logs/*.md`, use the filename's embedded date if present (`escalation-audit-YYYY-MM-DD.*`), else file mtime as last resort with a Notes row noting the fallback.
- [X] T045 [impl-theme-c] [US4] Implement deterministic sort `(timestamp ASC, source ASC, surface ASC)` with stable tie-break (NFR-003 byte-identical re-run requirement).

### Test for User Story 4

- [X] T046 [impl-theme-c] [US4] Create `plugin-kiln/tests/escalation-audit-inventory-shape/run.sh` per `contracts/interfaces.md` §D.4. Cites SC-004 + SC-005.
- [X] T047 [impl-theme-c] [US4] Add SC-005 second-run idempotency assertion (`diff` of `## Events` block between two runs returns empty).
- [X] T048 [impl-theme-c] [US4] Add empty-corpus assertion: with zero source files, the report body contains the exact string `No pause events found in the last 30 days`.
- [X] T049 [impl-theme-c] [US4] Run fixture; assert PASS.

**Checkpoint**: Phase 6 ends with US4 fully shippable.

- [ ] T050 [impl-theme-c] Commit Phase 6 with message `feat(kiln-escalation-audit): inventory skill V1 (FR-011..FR-015, NFR-003)`.

---

## Phase 7: User Story 5 — `kiln-doctor` `4-escalation-frequency` subcheck (P3) — impl-theme-c

**Goal**: Doctor tripwire suggesting `/kiln:kiln-escalation-audit` when pauses spike.
**Independent Test**: Inline doctor smoke assertion in audit phase (SC-007).

### Implementation

- [ ] T060 [impl-theme-c] [US5] In `plugin-kiln/skills/kiln-doctor/SKILL.md`, AFTER existing `### 3h: Structural hygiene drift` section, insert a new section `### 4: Escalation-frequency tripwire (FR-016)`.
- [ ] T061 [impl-theme-c] [US5] Use the Bash block from `contracts/interfaces.md` §C.2 verbatim. Threshold: `> 20` events in 7-day window.
- [ ] T062 [impl-theme-c] [US5] Confirm the subcheck is suggestion-only — no auto-invoke of `/kiln:kiln-escalation-audit`.
- [ ] T063 [impl-theme-c] [US5] Update doctor's `### 3e: Report` (or equivalent terminal report block) to include subcheck `4` in its enumeration.

### Test for User Story 5

- [ ] T064 [impl-theme-c] [US5] Add an inline doctor smoke assertion to the existing fixture coverage (or, if absent, document SC-007 as covered by an audit-phase manual run with seeded `.wheel/history/` and recorded in `blockers.md` if substrate-blocked). Cite SC-007.

**Checkpoint**: Phase 7 ends with US5 fully shippable.

- [ ] T065 [impl-theme-c] Commit Phase 7 with message `feat(kiln-doctor): subcheck 4-escalation-frequency tripwire (FR-016)`.

- [ ] T066 [impl-theme-c] Write `specs/escalation-audit/agent-notes/impl-theme-c.md` with friction notes.

---

## Phase 8: Polish & Cross-cutting

- [ ] T070 [impl-themes-ab] [P] Verify NFR-001: scaffold a 10-item PRD locally; time the Step 4b.5 block end-to-end. Record observed wall-clock in `agent-notes/impl-themes-ab.md`. (If > 5s, surface as a blocker; the budget is generous so this is unlikely.)
- [ ] T071 [impl-theme-c] [P] Re-run all 4 fixtures via `/kiln:kiln-test` (auto-detect plugin) and confirm every fixture is PASS in the consolidated test report.
- [ ] T072 [impl-themes-ab] [P] Confirm `plugin-kiln/skills/kiln-build-prd/SKILL.md` total length stays within reasonable bounds (target < 1500 lines after the +90 inserted lines from Phases 3/5; current 1332).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup AB)**: no deps. Starts immediately.
- **Phase 2 (Setup C)**: no deps. **Parallel with Phase 1** (different owner).
- **Phase 3 (US1)**: depends on Phase 1. Sequential within `impl-themes-ab`.
- **Phase 4 (US2)**: depends on Phase 3. Sequential within `impl-themes-ab` (next after auto-flip lands).
- **Phase 5 (US3)**: depends on Phase 4. Sequential within `impl-themes-ab` (last for AB).
- **Phase 6 (US4)**: depends on Phase 2. **Parallel with Phases 3/4/5** (different owner, different files).
- **Phase 7 (US5)**: depends on Phase 6. Sequential within `impl-theme-c`.
- **Phase 8 (Polish)**: depends on Phases 5 + 7.

### Within Each User Story

- Implementation tasks before test-fixture tasks within the same phase (the fixture asserts the implementation).
- Commit after each phase (T016, T027, T037, T050, T065).
- Friction notes (T038, T066) before the implementer signals completion to team-lead.

### Parallel Opportunities

- Phases 1 + 2 run in parallel (different owners).
- Phase 6 (impl-theme-c) runs in parallel with Phases 3 + 4 + 5 (impl-themes-ab) — strict file separation, no edit collision.
- Within Phase 8, T070 / T071 / T072 are [P] — different file scopes.

---

## Implementation Strategy

### MVP First (US1 + US2 + US4 — three P1 stories)

1. Phase 1 + Phase 2 (parallel setup).
2. Phase 3 (US1 — auto-flip): MVP. Closes the highest-friction drift loop.
3. Phase 4 (US2 — `--check`): catches pre-existing drift across the 81-item roadmap.
4. Phase 6 (US4 — escalation-audit): foundation primitive for autonomy calibration.
5. Phase 5 (US3 — shutdown-nag) + Phase 7 (US5 — doctor subcheck): convenience layers.
6. Phase 8 polish.

### Concurrent-Staging Hazard Reminder

`impl-themes-ab` and `impl-theme-c` MUST NOT both edit `kiln-build-prd/SKILL.md`. The contract above gives Theme A + Theme B (`impl-themes-ab`) exclusive ownership of that file. `impl-theme-c` does not touch it.

---

## Notes

- [P] tasks = different files, no dependencies, different owners.
- [Story] label maps task to spec user story.
- Each user story (US1..US5) is independently completable and testable.
- Verify fixtures fail before implementation (TDD-lite); add the impl, re-verify they PASS.
- Commit after each phase; do not batch.
- Friction notes are part of the deliverable, not optional (FR-009 of build-prd).
