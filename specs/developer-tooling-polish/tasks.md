# Tasks: Developer Tooling Polish

**Input**: Design documents from `/specs/developer-tooling-polish/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, contracts/

**Tests**: Not requested — these are Claude Code plugin skills (Markdown + Bash) with no test framework.

**Organization**: Tasks are grouped by user story. US1 and US2 are independent and can be implemented in parallel by separate agents.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Create skill directories

- [X] T001 [P] Create wheel-list skill directory at plugin-wheel/skills/wheel-list/
- [X] T002 [P] Create qa-audit skill directory at plugin-kiln/skills/qa-audit/

---

## Phase 2: User Story 1 — Discover Available Workflows (Priority: P1)

**Goal**: A `/wheel-list` command that scans `workflows/` and displays all available workflows with metadata, grouped by directory, with validation status.

**Independent Test**: Place workflow JSON files (valid and invalid) in `workflows/` and `workflows/tests/`, run `/wheel-list`, verify grouped output with accurate step counts, types, composition flags, and error indicators.

### Implementation for User Story 1

- [X] T003 [US1] Create SKILL.md frontmatter and introduction in plugin-wheel/skills/wheel-list/SKILL.md
- [X] T004 [US1] Implement Step 1 — Scan: recursively find all .json files in workflows/ directory (FR-001) in plugin-wheel/skills/wheel-list/SKILL.md
- [X] T005 [US1] Implement Step 2 — Parse & Validate: extract name, step count, step types, composition flag, validation status for each workflow using jq (FR-002, FR-004) in plugin-wheel/skills/wheel-list/SKILL.md
- [X] T006 [US1] Implement Step 3 — Group & Display: group workflows by parent directory and output formatted tables (FR-003) in plugin-wheel/skills/wheel-list/SKILL.md
- [X] T007 [US1] Implement empty state: display helpful message suggesting /wheel-create when no workflows found (FR-005) in plugin-wheel/skills/wheel-list/SKILL.md
- [X] T008 [US1] End-to-end validation: run /wheel-list on this repo's workflows/ directory and verify output matches expected format from contracts/interfaces.md

**Checkpoint**: `/wheel-list` is fully functional and independently testable.

---

## Phase 3: User Story 2 — Audit Test Suite for Redundancy (Priority: P1)

**Goal**: A `/qa-audit` command that reads test files, detects duplicate scenarios and redundant assertions, and writes a prioritized report to `.kiln/qa/test-audit-report.md`.

**Independent Test**: Point `/qa-audit` at a project with 10+ test files containing intentional duplicates. Verify the report identifies at least one overlapping pair with estimated redundancy.

### Implementation for User Story 2

- [ ] T009 [US2] Create SKILL.md frontmatter and introduction in plugin-kiln/skills/qa-audit/SKILL.md
- [ ] T010 [US2] Implement Step 1 — Discover: find test files matching common patterns (*.test.*, *.spec.*, tests/**, __tests__/**, e2e/**), excluding node_modules/ (FR-006) in plugin-kiln/skills/qa-audit/SKILL.md
- [ ] T011 [US2] Implement Step 2 — Extract: read each test file, extract test names/descriptions from test()/it()/describe() blocks, collect selector patterns, URL patterns, and assertion targets (FR-007, FR-008) in plugin-kiln/skills/qa-audit/SKILL.md
- [ ] T012 [US2] Implement Step 3 — Analyze: compare test descriptions for similarity, compare selector/URL/assertion patterns across files, flag high-overlap pairs (FR-007, FR-008) in plugin-kiln/skills/qa-audit/SKILL.md
- [ ] T013 [US2] Implement Step 4 — Report: create .kiln/qa/ if needed, write prioritized report with summary stats, duplicate scenario pairs, redundant assertion groups, and consolidation suggestions to .kiln/qa/test-audit-report.md (FR-009, FR-010) in plugin-kiln/skills/qa-audit/SKILL.md
- [ ] T014 [US2] Implement empty state: display message when no test files found in plugin-kiln/skills/qa-audit/SKILL.md
- [ ] T015 [US2] End-to-end validation: run /qa-audit on a project with test files and verify report output matches expected format from contracts/interfaces.md

**Checkpoint**: `/qa-audit` is fully functional and independently testable.

---

## Phase 4: User Story 3 — Prevent Test Bloat During Pipeline (Priority: P2)

**Goal**: Optional pipeline integration mode for `/qa-audit` that routes findings to implementers before test execution.

**Independent Test**: Invoke `/qa-audit` during a pipeline build and verify findings are flagged to the implementer agent.

### Implementation for User Story 3

- [ ] T016 [US3] Add Step 5 — Pipeline Integration: add optional pipeline mode that routes critical overlaps to implementer agents via SendMessage (FR-011) in plugin-kiln/skills/qa-audit/SKILL.md

**Checkpoint**: Pipeline integration mode works alongside standalone mode.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Final verification across both skills

- [ ] T017 Verify both skills handle edge cases: missing directories, invalid JSON, deeply nested files, empty projects
- [ ] T018 Run quickstart.md validation — confirm both commands work with zero configuration on existing projects

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **US1 (Phase 2)**: Depends on T001 (directory creation) only
- **US2 (Phase 3)**: Depends on T002 (directory creation) only
- **US3 (Phase 4)**: Depends on US2 completion (T009-T015)
- **Polish (Phase 5)**: Depends on US1 and US2 completion

### User Story Dependencies

- **User Story 1 (P1)**: Independent — can run in parallel with US2
- **User Story 2 (P1)**: Independent — can run in parallel with US1
- **User Story 3 (P2)**: Depends on US2 (adds pipeline mode to existing qa-audit skill)

### Parallel Opportunities

- T001 and T002 can run in parallel (different directories)
- US1 (T003-T008) and US2 (T009-T015) can be implemented in parallel by separate agents
- US1 agent owns: `plugin-wheel/skills/wheel-list/`
- US2 agent owns: `plugin-kiln/skills/qa-audit/`
- No file conflicts between the two user stories

---

## Parallel Example: Full Team

```bash
# Agent 1 (wheel-list): US1 tasks sequentially
T001 → T003 → T004 → T005 → T006 → T007 → T008

# Agent 2 (qa-audit): US2 tasks sequentially
T002 → T009 → T010 → T011 → T012 → T013 → T014 → T015

# After both complete: US3 + Polish
T016 → T017 → T018
```

---

## Implementation Strategy

### MVP First (User Story 1 + User Story 2 in Parallel)

1. Complete Phase 1: Setup (T001, T002 in parallel)
2. Complete Phase 2 + Phase 3 in parallel:
   - Agent A: User Story 1 (wheel-list) — T003-T008
   - Agent B: User Story 2 (qa-audit) — T009-T015
3. **SELF-VALIDATE**: Each agent validates their skill independently
4. Complete Phase 4: User Story 3 (pipeline integration) — T016
5. Complete Phase 5: Polish — T017, T018

### Incremental Delivery

1. Setup → directories created
2. US1 complete → `/wheel-list` works standalone
3. US2 complete → `/qa-audit` works standalone
4. US3 complete → pipeline integration added
5. Polish → edge cases verified

---

## Notes

- Both skills are single SKILL.md files — all tasks for a skill write to the same file sequentially
- No shared code between the two skills
- FR references map directly to PRD functional requirements
- Each skill follows the established pattern from existing wheel/kiln skills (frontmatter + numbered steps with Bash blocks)
