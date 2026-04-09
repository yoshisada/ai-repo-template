# Tasks: Shelf Skills Polish

**Input**: Design documents from `specs/shelf-skills-polish/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the canonical status labels file — shared dependency for all user stories

- [ ] T001 Create canonical status labels file at `plugin-shelf/status-labels.md` with six statuses (idea, active, paused, blocked, completed, archived), descriptions, and non-canonical equivalent mappings per FR-012

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No foundational tasks needed — all user stories work against independent files

**Checkpoint**: Phase 1 complete — user story implementation can begin

---

## Phase 3: User Story 1 - Deterministic Project Scaffolding via Workflow (Priority: P1)

**Goal**: Rewrite shelf-create as a wheel workflow with command steps for data gathering and agent steps for MCP operations

**Independent Test**: Run `/shelf-create` on a repo with `.shelf-config` and verify `.wheel/outputs/` contains step outputs and the Obsidian vault has the created project

### Implementation for User Story 1

- [ ] T002 [US1] Create shelf-create workflow JSON at `plugin-shelf/workflows/shelf-create.json` with `read-shelf-config` command step that reads `.shelf-config` or derives defaults from git remote per contracts/interfaces.md
- [ ] T003 [US1] Add `detect-repo-progress` command step to `plugin-shelf/workflows/shelf-create.json` that inspects repo for progress signals (specs count, code dirs, test files, VERSION, commit count, open issues, .kiln/ artifacts) per FR-005
- [ ] T004 [US1] Add `detect-tech-stack` command step to `plugin-shelf/workflows/shelf-create.json` that scans for config files and parses package.json dependencies (reuse pattern from shelf-full-sync)
- [ ] T005 [US1] Add `get-repo-metadata` command step to `plugin-shelf/workflows/shelf-create.json` that extracts git remote URL and package.json description
- [ ] T006 [US1] Add `resolve-vault-path` agent step to `plugin-shelf/workflows/shelf-create.json` with instruction to navigate from vault root via `list_files("/")` and verify/create base_path per FR-003, FR-004. Context from: read-shelf-config
- [ ] T007 [US1] Add `check-duplicate` agent step to `plugin-shelf/workflows/shelf-create.json` with instruction to list files at target project path and abort if project exists. Context from: read-shelf-config, resolve-vault-path
- [ ] T008 [US1] Add `create-project` agent step to `plugin-shelf/workflows/shelf-create.json` with instruction to create dashboard + about + directory structure using templates, setting initial status from progress signals per FR-002, FR-006. Context from: read-shelf-config, detect-repo-progress, detect-tech-stack, get-repo-metadata, resolve-vault-path, check-duplicate. Must reference `plugin-shelf/status-labels.md` for valid status values
- [ ] T009 [US1] Add `write-shelf-config` terminal command step to `plugin-shelf/workflows/shelf-create.json` that writes `.shelf-config` if it doesn't already exist
- [ ] T010 [US1] Rewrite `plugin-shelf/skills/shelf-create/SKILL.md` as thin wrapper that validates input and delegates to `/wheel-run shelf:shelf-create` per FR-007

**Checkpoint**: shelf-create workflow is fully defined and the skill delegates to it

---

## Phase 4: User Story 2 - Holistic Progress Detection on Create (Priority: P1)

**Goal**: Ensure the detect-repo-progress step and create-project agent step correctly populate initial status based on repo signals

**Independent Test**: Run `/shelf-create` on a repo with existing code, specs, and tests — verify dashboard status is `active` with a populated progress entry

**Note**: This story's implementation is embedded in Phase 3 tasks T003 and T008. The progress detection logic is in the `detect-repo-progress` command step (T003), and the status mapping is in the `create-project` agent instruction (T008). No additional tasks needed — the contracts already specify the behavior.

**Checkpoint**: Progress detection integrated into shelf-create workflow via T003 and T008

---

## Phase 5: User Story 3 - Canonical Status Labels Across All Skills (Priority: P2)

**Goal**: All shelf skills reference the canonical status list and reject or warn on non-canonical values

**Independent Test**: Inspect each shelf skill's SKILL.md for the status label validation section referencing `plugin-shelf/status-labels.md`

### Implementation for User Story 3

- [ ] T011 [P] [US3] Add status label validation section to `plugin-shelf/skills/shelf-update/SKILL.md` referencing `plugin-shelf/status-labels.md` per FR-013. Add instructions to normalize non-canonical values and warn the user
- [ ] T012 [P] [US3] Add status label validation section to `plugin-shelf/skills/shelf-status/SKILL.md` referencing `plugin-shelf/status-labels.md` per FR-013. Add instructions to display canonical status with a note if the stored value was non-canonical
- [ ] T013 [P] [US3] Add status label validation section to `plugin-shelf/skills/shelf-sync/SKILL.md` referencing `plugin-shelf/status-labels.md` per FR-013. Add instructions to normalize status values encountered during sync

**Checkpoint**: All existing shelf skills reference canonical status labels

---

## Phase 6: User Story 4 - Repair Existing Dashboards (Priority: P2)

**Goal**: Create shelf-repair workflow that re-applies templates to existing projects while preserving user content

**Independent Test**: Run `/shelf-repair` on a project with an outdated dashboard — verify structure matches current template and user content (Feedback, Human Needed, Feedback Log) is preserved

### Implementation for User Story 4

- [ ] T014 [US4] Create shelf-repair workflow JSON at `plugin-shelf/workflows/shelf-repair.json` with `read-shelf-config` command step and `read-current-template` command step per contracts/interfaces.md
- [ ] T015 [US4] Add `read-existing-dashboard` agent step to `plugin-shelf/workflows/shelf-repair.json` with instruction to read current dashboard from Obsidian via MCP and extract all sections. Context from: read-shelf-config
- [ ] T016 [US4] Add `generate-diff-report` agent step to `plugin-shelf/workflows/shelf-repair.json` with instruction to compare dashboard to template and report structural differences, flagging non-canonical status per FR-010. Context from: read-shelf-config, read-current-template, read-existing-dashboard
- [ ] T017 [US4] Add `apply-repairs` agent step to `plugin-shelf/workflows/shelf-repair.json` with instruction to apply template structure while preserving user content (Feedback, Human Needed, Feedback Log, progress entries) and normalizing status labels per FR-009, FR-011. Context from: read-shelf-config, read-current-template, read-existing-dashboard, generate-diff-report. Must reference `plugin-shelf/status-labels.md`
- [ ] T018 [US4] Add `verify-repair` terminal agent step to `plugin-shelf/workflows/shelf-repair.json` with instruction to re-read dashboard and confirm it matches template structure. Context from: read-shelf-config, apply-repairs
- [ ] T019 [US4] Create `plugin-shelf/skills/shelf-repair/SKILL.md` as thin wrapper that validates project exists and delegates to `/wheel-run shelf:shelf-repair` per contracts/interfaces.md

**Checkpoint**: shelf-repair workflow and skill are fully defined

---

## Phase 7: User Story 5 - Full Sync Summary (Priority: P3)

**Goal**: Add a summary step to shelf-full-sync that consolidates all sync action counts

**Independent Test**: Run `shelf-full-sync` and verify `.wheel/outputs/shelf-full-sync-summary.md` contains accurate counts matching individual step outputs

### Implementation for User Story 5

- [ ] T020 [US5] Remove `"terminal": true` from the `push-progress-update` step in `plugin-shelf/workflows/shelf-full-sync.json`
- [ ] T021 [US5] Add `generate-sync-summary` command step to `plugin-shelf/workflows/shelf-full-sync.json` as the new terminal step. The command must read `.wheel/outputs/sync-issues-results.md`, `.wheel/outputs/sync-docs-results.md`, `.wheel/outputs/update-tags-results.md`, and `reports/shelf-full-sync-report.md`, extract counts using grep/sed, and format a consolidated summary at `.wheel/outputs/shelf-full-sync-summary.md` per FR-014, FR-015

**Checkpoint**: shelf-full-sync produces a human-readable summary with action counts

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and cleanup

- [ ] T022 Verify all workflow JSON files pass validation by checking they have valid `name`, `steps` with `id` and `type` fields, and all `context_from` references point to existing step IDs
- [ ] T023 Run quickstart.md validation — confirm all file paths mentioned in quickstart.md exist after implementation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — create status-labels.md first
- **Phase 3 (US1 shelf-create)**: Depends on Phase 1 (needs status-labels.md)
- **Phase 4 (US2 progress detection)**: No additional tasks — embedded in Phase 3
- **Phase 5 (US3 status labels)**: Depends on Phase 1 (needs status-labels.md). Can run in parallel with Phase 3
- **Phase 6 (US4 shelf-repair)**: Depends on Phase 1 (needs status-labels.md). Can run in parallel with Phase 3 and Phase 5
- **Phase 7 (US5 sync summary)**: No dependencies on other user stories — modifies shelf-full-sync independently
- **Phase 8 (Polish)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (shelf-create)**: Depends on T001 (status-labels.md). No dependencies on other stories
- **US2 (progress detection)**: Embedded in US1 tasks. No separate dependencies
- **US3 (status labels in skills)**: Depends on T001 (status-labels.md). Independent of other stories
- **US4 (shelf-repair)**: Depends on T001 (status-labels.md). Independent of other stories
- **US5 (sync summary)**: Fully independent. Can run in parallel with all other stories

### Within Each User Story

- Workflow steps are built sequentially within each JSON file (later steps reference earlier steps via context_from)
- Skill wrapper is created last (after workflow is complete)

### Parallel Opportunities

- T011, T012, T013 (US3) can all run in parallel — different skill files
- Phase 3 (US1), Phase 5 (US3), Phase 6 (US4), Phase 7 (US5) can all run in parallel after Phase 1

---

## Parallel Example: User Story 3 (Status Labels)

```bash
# All three skill updates can run in parallel (different files):
Task T011: "Add status label validation to plugin-shelf/skills/shelf-update/SKILL.md"
Task T012: "Add status label validation to plugin-shelf/skills/shelf-status/SKILL.md"
Task T013: "Add status label validation to plugin-shelf/skills/shelf-sync/SKILL.md"
```

---

## Implementation Strategy

### MVP First (User Story 1 + Status Labels)

1. Complete Phase 1: Create status-labels.md (T001)
2. Complete Phase 3: Build shelf-create workflow (T002-T010)
3. **SELF-VALIDATE**: Verify shelf-create.json is valid JSON with correct step structure
4. Complete Phase 5: Add status label refs to existing skills (T011-T013)

### Incremental Delivery

1. T001 → Status labels defined — foundation for all stories
2. T002-T010 → shelf-create is a workflow — core improvement
3. T011-T013 → All skills use canonical labels — consistency achieved
4. T014-T019 → shelf-repair exists — template maintenance possible
5. T020-T021 → shelf-full-sync has summary — user visibility improved
6. T022-T023 → Polish — everything validated

---

## Notes

- This is a plugin source repo — no src/ or tests/ directories
- All deliverables are Markdown (skills, config) or JSON (workflows) files
- No automated test suite — validation is structural (JSON validity, file existence)
- Workflow JSON files are built incrementally (step by step) rather than all at once
- Each task adds one or more steps to a workflow file, building on the previous task's output
