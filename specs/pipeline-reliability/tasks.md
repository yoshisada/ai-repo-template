# Tasks: Pipeline Reliability & Health

**Input**: Design documents from `/specs/pipeline-reliability/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, contracts/

**Tests**: No test tasks — this is the kiln plugin source repo which has no test suite. Validation is via pipeline runs on consumer projects.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: No project initialization needed — all target files already exist. This phase is intentionally empty.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core hook restructuring that all other stories depend on

**CRITICAL**: The hook overhaul (US1, US2, US3, US4) all modify `plugin/hooks/require-spec.sh`. These must be done sequentially in a single phase to avoid conflicts.

- [ ] T001 Add `get_current_feature()` function to `plugin/hooks/require-spec.sh` — extracts feature name from git branch using patterns `build/<name>-<date>` and `<number>-<name>`, falls back to `.kiln/current-feature` file, prints empty string if all fail (FR-001)
- [ ] T002 Replace all `specs/*/` glob checks in `plugin/hooks/require-spec.sh` with `specs/$CURRENT_FEATURE/` scoped checks for Gates 1-3, using output of `get_current_feature()`. If feature is empty, fall back to existing glob behavior for backwards compatibility (FR-001)
- [ ] T003 Add `is_implementation_path()` function to `plugin/hooks/require-spec.sh` — returns 0 for paths in `src/`, `cli/`, `lib/`, `modules/`, `app/`, `components/` directories; returns 1 for always-allowed paths (`docs/`, `specs/`, `scripts/`, `tests/`, `plugin/`, `.claude/`, `.specify/`, `.json`, `.yml`, `.yaml`, `.toml`, `.md`, `.gitignore`, `.env*`) (FR-003)
- [ ] T004 Replace the `case` statement allowlist in `plugin/hooks/require-spec.sh` with a call to `is_implementation_path()` — if not an implementation path, exit 0; otherwise proceed to gate checks (FR-003)
- [ ] T005 Add Gate 3.5 to `plugin/hooks/require-spec.sh` — after Gate 3, check that `specs/$CURRENT_FEATURE/contracts/interfaces.md` exists. Add missing contracts to the BLOCKED message (FR-004)
- [ ] T006 Add `check_implementing_lock()` function to `plugin/hooks/require-spec.sh` — reads `.kiln/implementing.lock`, parses JSON for timestamp field, returns 0 if lock exists and is less than 30 minutes old, returns 1 otherwise (FR-002)
- [ ] T007 Update Gate 4 in `plugin/hooks/require-spec.sh` — pass if `check_implementing_lock()` returns 0 OR if tasks.md has `[X]` marks. Update the BLOCKED message to explain both conditions (FR-002)

**Checkpoint**: Hook script fully restructured. All 4 gates + contracts gate + implementing lock working. Verify by inspecting script logic.

---

## Phase 3: User Story 1 — Hook Gates Scope to Current Feature (Priority: P1)

**Goal**: Hook gates check current feature's spec artifacts, not any prior feature's

**Independent Test**: Create a consumer project with `specs/old-feature/spec.md`, switch to branch `build/new-feature-20260401`, try to edit `src/app.js` — should be blocked.

All implementation for this story is completed in Phase 2 (T001, T002). This phase validates the integration.

- [ ] T008 [US1] Verify `get_current_feature()` correctly extracts "pipeline-reliability" from branch `build/pipeline-reliability-20260401` by tracing the function logic in `plugin/hooks/require-spec.sh`

---

## Phase 4: User Story 2 — Gate 4 Works During Implementation (Priority: P1)

**Goal**: Gate 4 allows writes during active `/implement` runs without chicken-and-egg deadlock

**Independent Test**: Create `.kiln/implementing.lock` with fresh timestamp, verify hook allows source file edits even with no `[X]` in tasks.md.

All implementation for this story is completed in Phase 2 (T006, T007). This phase adds the lock file management to the implement skill.

- [ ] T009 [US2] Add implementing lock creation to `plugin/skills/implement/SKILL.md` — in the Outline section, after step 1 (check-prerequisites), add instruction to create `.kiln/implementing.lock` with JSON payload `{"timestamp": "<ISO8601>", "feature": "<name>", "pid": "$$"}` (FR-002)
- [ ] T010 [US2] Add implementing lock cleanup to `plugin/skills/implement/SKILL.md` — add instruction at end of Outline (after step 9 completion validation) and in error/failure paths to remove `.kiln/implementing.lock` (FR-002)

---

## Phase 5: User Story 3 — Expanded Hook Allowlist (Priority: P1)

**Goal**: Hook uses blocklist approach — gates apply to implementation directories, everything else is always allowed

**Independent Test**: Edit files in `cli/`, `lib/`, `modules/` without spec artifacts — should be blocked. Edit files in `docs/`, `tests/` — should always be allowed.

All implementation for this story is completed in Phase 2 (T003, T004). No additional tasks needed.

---

## Phase 6: User Story 4 — Contracts Gate Enforcement (Priority: P2)

**Goal**: `contracts/interfaces.md` must exist before implementation writes are allowed

**Independent Test**: Create spec, plan, and tasks but omit contracts — verify source file edits are blocked with a message about missing contracts.

All implementation for this story is completed in Phase 2 (T005). No additional tasks needed.

---

## Phase 7: User Story 5 — Pipeline Stall Detection (Priority: P2)

**Goal**: Build-prd orchestrator detects stalled agents and sends check-in messages

**Independent Test**: Review the build-prd skill prompt for clear stall detection instructions with configurable timeout.

- [ ] T011 [US5] Add stall detection section to `plugin/skills/build-prd/SKILL.md` — in the "Monitor and Steer" section (or after Task Dependencies), add instructions for the team lead to: track last activity time per agent, check every agent's status when processing task updates, send a check-in message if an agent's task has been `in_progress` for 10+ minutes with no commits/task-updates/messages, escalate or reassign if agent is unresponsive after check-in (FR-005)

---

## Phase 8: User Story 6 — Phase Dependency Enforcement (Priority: P2)

**Goal**: Downstream phase agents are not dispatched until upstream phase tasks are complete

**Independent Test**: Review the build-prd skill prompt for explicit phase-gating instructions.

- [ ] T012 [US6] Add phase dependency enforcement to `plugin/skills/build-prd/SKILL.md` — in the agent dispatch logic (Step 3 or Monitor and Steer section), add instructions that the team lead MUST verify all tasks in Phase N are marked `[X]` in tasks.md before dispatching Phase N+1 agents. Include instruction to read tasks.md and check completion status before each dispatch (FR-006)

---

## Phase 9: User Story 7 — STOP AND VALIDATE Clarification (Priority: P2)

**Goal**: Replace ambiguous "STOP and VALIDATE" with explicit self-validation vs QA-gated language

**Independent Test**: Search all skill/template files for "STOP and VALIDATE" — should be zero occurrences. Search for "SELF-VALIDATE" — should be present with clear instructions.

- [ ] T013 [P] [US7] Replace "STOP and VALIDATE" in `plugin/templates/tasks-template.md` line 219 — change to "SELF-VALIDATE: Run tests locally and verify User Story 1 independently. Do NOT wait for external QA feedback." (FR-007)
- [ ] T014 [P] [US7] Review `plugin/skills/implement/SKILL.md` for any "STOP and VALIDATE" or ambiguous validation language — replace with "SELF-VALIDATE: Run tests locally and verify the phase works. Proceed to the next phase if tests pass. Do NOT wait for external QA feedback." Add a note distinguishing self-validation from QA-gated checkpoints (FR-007)

---

## Phase 10: User Story 8 — Docker Rebuild Between Impl and QA (Priority: P3)

**Goal**: Build-prd orchestrator triggers Docker rebuild after implementation, before QA

**Independent Test**: Review build-prd skill prompt for Docker rebuild step conditioned on Dockerfile presence.

- [ ] T015 [US8] Add Docker rebuild step to `plugin/skills/build-prd/SKILL.md` — after all implementers complete and before dispatching QA agents, add instruction: if `Dockerfile` or `docker-compose.yml` exists in the project root, run `docker compose build` (or `docker build -t <project> .`). Log the rebuild. If rebuild fails, log warning and proceed (FR-008)

---

## Phase 11: User Story 9 — QA Container Freshness Pre-Flight (Priority: P3)

**Goal**: QA engineer agent verifies container freshness before testing

**Independent Test**: Review qa-engineer agent prompt for container freshness check in Pre-Flight section.

- [ ] T016 [US9] Add container freshness pre-flight to `plugin/agents/qa-engineer.md` — in the "Pre-Flight: Build Version Verification" section, add a step before version checking: if `Dockerfile` or `docker-compose.yml` exists in project root, read `.kiln/qa/last-build-sha` (if exists), compare against `git rev-parse HEAD`, if mismatch or file missing run `docker compose build` and update `.kiln/qa/last-build-sha` with current HEAD. If no Dockerfile, skip (FR-009)

---

## Phase 12: User Story 10 — QA Checkpoint Container Verification (Priority: P3)

**Goal**: qa-checkpoint skill verifies container freshness before running checkpoint tests

**Independent Test**: Review qa-checkpoint skill prompt for container freshness step between "Determine What to Test" and "Start Dev Server."

- [ ] T017 [US10] Add container freshness step to `plugin/skills/qa-checkpoint/SKILL.md` — add a new "Step 1.5: Container Freshness Check" between Step 1 (Determine What to Test) and Step 2 (Start Dev Server): if `Dockerfile` or `docker-compose.yml` exists in project root, read `.kiln/qa/last-build-sha`, compare against `git rev-parse HEAD`, rebuild if stale, update the SHA file. If no Dockerfile, skip (FR-010)

---

## Phase 13: Polish & Cross-Cutting Concerns

**Purpose**: Documentation and final validation

- [ ] T018 Update CLAUDE.md "Active Technologies" section to reflect changes made in this feature (Bash hook modifications, Markdown skill/agent updates)
- [ ] T019 Run quickstart.md validation — trace through each verification scenario described in `specs/pipeline-reliability/quickstart.md` against the implemented changes to confirm correctness

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: Empty — no work needed
- **Phase 2 (Foundational)**: No dependencies — start immediately. Tasks T001-T007 MUST be sequential (all modify `plugin/hooks/require-spec.sh`)
- **Phase 3-6 (US1-US4)**: Depend on Phase 2 completion. US1/US3/US4 are validation-only (work done in Phase 2). US2 (T009-T010) modifies `plugin/skills/implement/SKILL.md`
- **Phase 7-9 (US5-US7)**: Can run in parallel after Phase 2. Each modifies a different file:
  - US5 (T011): `plugin/skills/build-prd/SKILL.md`
  - US6 (T012): `plugin/skills/build-prd/SKILL.md` (same file as T011 — run sequentially after T011)
  - US7 (T013-T014): `plugin/templates/tasks-template.md` and `plugin/skills/implement/SKILL.md`
- **Phase 10-12 (US8-US10)**: Can run in parallel after Phase 2. Each modifies a different file:
  - US8 (T015): `plugin/skills/build-prd/SKILL.md` (run after T012)
  - US9 (T016): `plugin/agents/qa-engineer.md`
  - US10 (T017): `plugin/skills/qa-checkpoint/SKILL.md`
- **Phase 13 (Polish)**: Depends on all previous phases

### Parallel Opportunities

- T013 and T014 can run in parallel (different files)
- T016 and T017 can run in parallel (different files)
- Phases 7-12 have limited parallelism due to shared files (build-prd/SKILL.md is modified by T011, T012, T015)

---

## Implementation Strategy

### MVP First (Hook Gate Overhaul)

1. Complete Phase 2: Foundational hook restructuring (T001-T007)
2. Complete Phases 3-6: Validate hook changes (T008-T010)
3. **SELF-VALIDATE**: Trace through hook script logic to verify all gates work correctly
4. Commit hook changes

### Incremental Delivery

1. Hook gate overhaul (Phase 2-6) — fixes the most critical enforcement bugs
2. Pipeline health (Phase 7-9) — adds stall detection, phase gating, clearer prompts
3. Docker awareness (Phase 10-12) — adds container freshness to QA workflow
4. Polish (Phase 13) — documentation and final validation

---

## Notes

- All tasks modify files under `plugin/` — this is the kiln plugin source repo, not a consumer project
- No `src/` directory exists; no compilation step; no test suite
- Tasks T001-T007 MUST be sequential (same file: `plugin/hooks/require-spec.sh`)
- T011, T012, T015 MUST be sequential (same file: `plugin/skills/build-prd/SKILL.md`)
- Commit after each completed phase
