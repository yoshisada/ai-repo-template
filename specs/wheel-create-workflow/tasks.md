# Tasks: Wheel Create Workflow

**Input**: Design documents from `specs/wheel-create-workflow/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: No test tasks — this is a plugin skill (SKILL.md). Validation is done by generating and running workflows via `workflow_load` and `/wheel-run`.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Create the skill file with frontmatter and basic structure

- [X] T001 Create skill directory and SKILL.md with frontmatter at `plugin-wheel/skills/wheel-create/SKILL.md`

**Checkpoint**: Skill file exists with valid frontmatter (`name: wheel-create`, `description`).

---

## Phase 2: Foundational (Shared Input Parsing & Output)

**Purpose**: Input parsing, name resolution, validation, and output reporting — shared by all user stories

**CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 Write the Title/Overview section documenting the two input modes (FR-001) in `plugin-wheel/skills/wheel-create/SKILL.md`
- [X] T003 Write the User Input section capturing `$ARGUMENTS` and detecting mode (FR-001, FR-002) in `plugin-wheel/skills/wheel-create/SKILL.md`
- [X] T004 Write Step 1 — Input Parsing: detect `from:` prefix for File Mode vs Description Mode, handle empty arguments by prompting user (FR-001, FR-002, FR-003) in `plugin-wheel/skills/wheel-create/SKILL.md`
- [X] T005 Write Step 2 — Name Resolution: derive kebab-case slug from input, check for collisions and append numeric suffix (FR-004, FR-005) in `plugin-wheel/skills/wheel-create/SKILL.md`
- [X] T006 Write Step 5 — JSON Assembly instructions: set `name`, `version: "1.0.0"`, mark terminal step, enforce step type schemas (FR-010, FR-011, FR-021, FR-022, FR-023, FR-024) in `plugin-wheel/skills/wheel-create/SKILL.md`
- [X] T007 Write Step 6 — Validation: validate generated JSON against `workflow_load` checks, attempt self-correction on failure (FR-017, FR-018) in `plugin-wheel/skills/wheel-create/SKILL.md`
- [X] T008 Write Step 7 — Write Output: write validated JSON to `workflows/<name>.json` with 2-space indent, report file path, name, step count, step summaries, run command (FR-019, FR-020) in `plugin-wheel/skills/wheel-create/SKILL.md`

**Checkpoint**: Foundation sections complete — skill can parse input, resolve names, validate JSON, and write output. User story-specific decomposition sections (Steps 3 and 4) come next.

---

## Phase 3: User Story 1 — Natural Language to Workflow (Priority: P1)

**Goal**: Users describe a multi-step automation in plain language and get a valid workflow JSON file.

**Independent Test**: Run `/wheel-create "gather git stats, analyze repo structure, write a health report"` and verify the output loads via `workflow_load` and runs via `/wheel-run`.

### Implementation for User Story 1

- [X] T009 [US1] Write Step 3 — Step Decomposition (Description Mode): instructions for parsing natural language into discrete steps, classifying by type (command/agent/branch/loop), determining context_from dependencies, assigning output paths, capping at 20 steps (FR-006, FR-007, FR-008, FR-009, FR-025) in `plugin-wheel/skills/wheel-create/SKILL.md`
- [X] T010 [US1] Add step type classification heuristics to Step 3: shell commands/file checks/data gathering → command, LLM reasoning/writing/analysis → agent, conditional logic → branch, repeated execution → loop (FR-007) in `plugin-wheel/skills/wheel-create/SKILL.md`
- [X] T011 [US1] Add output path convention guidance to Step 3: `.wheel/outputs/<step-id>.txt` for command steps, `reports/<name>.md` for agent report steps (FR-009) in `plugin-wheel/skills/wheel-create/SKILL.md`

**Checkpoint**: Description Mode fully functional. `/wheel-create "description"` produces valid workflow JSON.

---

## Phase 4: User Story 2 — File-Based Reverse Engineering (Priority: P2)

**Goal**: Users point at an existing file and get a workflow JSON that replicates its behavior.

**Independent Test**: Run `/wheel-create from:plugin-wheel/skills/wheel-status/SKILL.md` and verify the output workflow preserves the skill's intent and structure.

### Implementation for User Story 2

- [X] T012 [US2] Write Step 4 — Step Decomposition (File Mode): instructions for reading source file, validating existence (FR-003), and analyzing structure (FR-012) in `plugin-wheel/skills/wheel-create/SKILL.md`
- [X] T013 [US2] Add SKILL.md parsing guidance to Step 4: map headings to step boundaries, code blocks to command steps, prose/reasoning sections to agent steps (FR-013, FR-016) in `plugin-wheel/skills/wheel-create/SKILL.md`
- [X] T014 [US2] Add shell script and other file parsing guidance to Step 4: command sequences → command steps, complex logic → agent steps, JSON/YAML/Markdown heuristic parsing (FR-014, FR-015) in `plugin-wheel/skills/wheel-create/SKILL.md`

**Checkpoint**: File Mode fully functional. `/wheel-create from:<path>` produces valid workflow JSON from any supported file type.

---

## Phase 5: User Story 3 — Agent Self-Service Creation (Priority: P3)

**Goal**: Agents mid-conversation can dynamically create workflows without human JSON authoring.

**Independent Test**: Have an agent call `/wheel-create "check test coverage, fix failing tests, re-run tests"` and verify the workflow is valid and runnable.

### Implementation for User Story 3

- [ ] T015 [US3] Add agent-friendly guidance to the skill: ensure output is machine-parseable, collision handling works without prompts, no interactive questions when description is clear enough (FR-005, FR-025) in `plugin-wheel/skills/wheel-create/SKILL.md`

**Checkpoint**: Agent self-service works — agents can create workflows programmatically.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and edge case handling

- [ ] T016 Add edge case handling: vague descriptions (ask clarifying question), complex nested logic (wrap as agent steps), workflows exceeding 20 steps (consolidate), missing `workflows/` directory (create it) in `plugin-wheel/skills/wheel-create/SKILL.md`
- [ ] T017 Add a Rules section at the bottom of the skill summarizing key constraints: never overwrite existing files, max 20 steps, validate before writing, no auto-execution in `plugin-wheel/skills/wheel-create/SKILL.md`
- [ ] T018 End-to-end validation: generate a test workflow from a description, validate it passes `workflow_load`, verify it can run via `/wheel-run`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Phase 2 — can start after foundational sections
- **User Story 2 (Phase 4)**: Depends on Phase 2 — can start after foundational sections
- **User Story 3 (Phase 5)**: Depends on Phase 2 — can start after foundational sections
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Phase 2 — no dependencies on other stories
- **User Story 2 (P2)**: Can start after Phase 2 — independent of US1
- **User Story 3 (P3)**: Can start after Phase 2 — builds on US1 behavior but is independently testable

### Within Each User Story

- All tasks within a single file — must be sequential (same file)
- Each story adds a section to the SKILL.md

### Parallel Opportunities

- US1 (Phase 3), US2 (Phase 4), and US3 (Phase 5) could theoretically run in parallel since they write to different sections of the SKILL.md. However, since they all modify the same file, sequential execution is safer.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002-T008)
3. Complete Phase 3: User Story 1 (T009-T011)
4. **SELF-VALIDATE**: Generate a workflow from a description, validate with `workflow_load`
5. Functional MVP — natural language workflow creation works

### Incremental Delivery

1. Setup + Foundational → Skill structure ready
2. Add User Story 1 → Description Mode works (MVP)
3. Add User Story 2 → File Mode works
4. Add User Story 3 → Agent self-service works
5. Polish → Edge cases handled, rules documented

---

## Notes

- All tasks modify the same file: `plugin-wheel/skills/wheel-create/SKILL.md`
- [P] markers are omitted because all tasks write to the same file
- Total tasks: 18
- Tasks per story: US1=3, US2=3, US3=1, Setup=1, Foundation=7, Polish=3
