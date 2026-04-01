# Tasks: Kiln Rebrand, Infrastructure & QA Reliability

**Input**: Design documents from `specs/kiln-rebrand-and-qa/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/interfaces.md

**Tests**: No test tasks — this plugin has no test suite. Validation is done via pipeline runs on consumer projects.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: No project initialization needed — this is modifying an existing plugin. This phase is intentionally empty.

**Checkpoint**: Ready for user story implementation.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No foundational infrastructure needed — all changes are direct file modifications to existing plugin files.

**Checkpoint**: Ready for user story implementation.

---

## Phase 3: User Story 1 - Plugin Identity is Clear and Consistent (Priority: P1) MVP

**Goal**: Rename the plugin from "speckit-harness" to "kiln" across all user-facing surfaces with zero mixed branding.

**Independent Test**: Grep the entire plugin directory for "speckit-harness" — must return zero matches. All skill directories use new names.

### Implementation for User Story 1

- [X] T001 [US1] Update npm package name from `@yoshisada/speckit-harness` to `@yoshisada/kiln` and bin entry from `speckit-harness` to `kiln` in `plugin/package.json`
- [X] T002 [P] [US1] Update plugin manifest name from `speckit-harness` to `kiln` in `plugin/.claude-plugin/plugin.json`
- [X] T003 [US1] Rename skill directory `plugin/skills/speckit-specify` to `plugin/skills/specify`
- [X] T004 [P] [US1] Rename skill directory `plugin/skills/speckit-plan` to `plugin/skills/plan`
- [X] T005 [P] [US1] Rename skill directory `plugin/skills/speckit-tasks` to `plugin/skills/tasks`
- [X] T006 [P] [US1] Rename skill directory `plugin/skills/speckit-implement` to `plugin/skills/implement`
- [X] T007 [P] [US1] Rename skill directory `plugin/skills/speckit-audit` to `plugin/skills/audit`
- [X] T008 [P] [US1] Rename skill directory `plugin/skills/speckit-constitution` to `plugin/skills/constitution`
- [X] T009 [P] [US1] Rename skill directory `plugin/skills/speckit-analyze` to `plugin/skills/analyze`
- [X] T010 [P] [US1] Rename skill directory `plugin/skills/speckit-coverage` to `plugin/skills/coverage`
- [X] T011 [P] [US1] Rename skill directory `plugin/skills/speckit-checklist` to `plugin/skills/checklist`
- [X] T012 [P] [US1] Rename skill directory `plugin/skills/speckit-clarify` to `plugin/skills/clarify`
- [X] T013 [P] [US1] Rename skill directory `plugin/skills/speckit-taskstoissues` to `plugin/skills/taskstoissues`
- [X] T014 [US1] Update all cross-references in every SKILL.md file under `plugin/skills/` — replace `speckit-harness:speckit-*` with `kiln:*` and `speckit-harness:` with `kiln:` for non-speckit-prefixed skills
- [X] T015 [P] [US1] Update all references in agent files under `plugin/agents/` — replace `speckit-harness:` prefix with `kiln:` and any `speckit` branding with `kiln`
- [X] T016 [P] [US1] Update `plugin/hooks/hooks.json` — replace any `speckit-harness:` skill prefix references with `kiln:`
- [X] T017 [US1] Update all branding in `plugin/bin/init.mjs` — replace "speckit-harness" with "kiln" in banner, log messages, verify output, and next-steps text
- [X] T018 [US1] Update all branding in root `CLAUDE.md` — replace all "speckit-harness" references with "kiln", update all `/speckit-harness:*` command references to `/kiln:*`, update `speckit-*` skill names to drop prefix
- [X] T019 [P] [US1] Update all branding in `plugin/scaffold/CLAUDE.md` — same changes as root CLAUDE.md
- [X] T020 [P] [US1] Update keywords in `plugin/package.json` — replace "speckit" with "kiln"
- [X] T021 [US1] Verify rename completeness: grep entire `plugin/` directory for "speckit-harness" and "speckit" — document any intentional remaining references (e.g., migration notices)

**Checkpoint**: All user-facing surfaces say "kiln". Grep for "speckit-harness" returns zero matches (excluding intentional deprecation notices).

---

## Phase 4: User Story 2 - Centralized Artifact Storage in .kiln/ (Priority: P1)

**Goal**: Establish `.kiln/` as the standard directory for all automation artifacts with proper git tracking.

**Independent Test**: Run init.mjs on a test directory and verify `.kiln/` is created with all 5 subdirectories. Check .gitignore excludes transient directories.

### Implementation for User Story 2

- [X] T022 [US2] Add `.kiln/` directory scaffolding to `plugin/bin/init.mjs` — create `workflows/`, `agents/`, `issues/`, `qa/`, `logs/` subdirectories using `ensureDir()` (idempotent)
- [X] T023 [P] [US2] Update `plugin/scaffold/gitignore` — add entries to exclude `.kiln/agents/`, `.kiln/qa/`, `.kiln/logs/` while allowing `.kiln/workflows/` and `.kiln/issues/`
- [X] T024 [US2] Update `plugin/skills/report-issue/SKILL.md` — change output path from `docs/backlog/` to `.kiln/issues/`
- [X] T025 [P] [US2] Update `plugin/skills/qa-pass/SKILL.md` — route QA artifacts to `.kiln/qa/` instead of `qa-results/`
- [X] T026 [P] [US2] Update `plugin/skills/qa-checkpoint/SKILL.md` — route QA artifacts to `.kiln/qa/`
- [X] T027 [P] [US2] Update `plugin/skills/qa-final/SKILL.md` — route QA artifacts to `.kiln/qa/`
- [X] T028 [US2] Update `plugin/skills/build-prd/SKILL.md` — route pipeline logs to `.kiln/logs/`
- [X] T029 [P] [US2] Update agent files that reference output locations to use `.kiln/agents/` for agent run outputs
- [X] T030 [US2] Create workflow format specification at `plugin/templates/workflow-format.md` defining the structure for `.kiln/workflows/` files

**Checkpoint**: init.mjs scaffolds `.kiln/` with all subdirectories. All skill output paths point to `.kiln/` locations. Gitignore correctly excludes transient outputs.

---

## Phase 5: User Story 3 - Kiln Doctor Validates and Migrates Project State (Priority: P2)

**Goal**: Provide a doctor tool that validates project structure against a manifest and migrates legacy paths.

**Independent Test**: Create a project with `docs/backlog/` and `qa-results/` directories, run doctor in diagnose mode, verify it reports migration needed. Run fix mode and verify files are moved.

### Implementation for User Story 3

- [X] T031 [US3] Create doctor manifest template at `plugin/templates/kiln-manifest.json` — define expected directories, tracked status, and legacy path migrations per contracts/interfaces.md
- [X] T032 [US3] Create `/kiln-doctor` skill at `plugin/skills/kiln-doctor/SKILL.md` — implement diagnose mode (read manifest, compare project state, report findings) and fix mode (present fixes, apply on confirmation, idempotent)
- [X] T033 [US3] Add legacy path mapping for `docs/backlog/` -> `.kiln/issues/` and `qa-results/` -> `.kiln/qa/` in the doctor skill

**Checkpoint**: Doctor correctly identifies missing directories and legacy paths. Fix mode migrates files without data loss. Running doctor twice produces no changes (idempotent).

---

## Phase 6: User Story 4 - QA Engineer Verifies Latest Build Before Testing (Priority: P2)

**Goal**: Add build version verification pre-flight to QA agent and related skills.

**Independent Test**: Modify code without rebuilding, trigger QA, verify version mismatch is detected and rebuild is triggered.

### Implementation for User Story 4

- [X] T034 [US4] Add "Pre-Flight: Build Version Verification" section to `plugin/agents/qa-engineer.md` — version check logic per contracts/interfaces.md (read VERSION, check app, compare, rebuild on mismatch, warn on persistent mismatch)
- [X] T035 [P] [US4] Add version verification pre-flight section to `plugin/skills/qa-pass/SKILL.md`
- [X] T036 [P] [US4] Add version verification pre-flight section to `plugin/skills/ux-evaluate/SKILL.md`

**Checkpoint**: QA agent markdown contains version check instructions. qa-pass and ux-evaluate skills include pre-flight version verification.

---

## Phase 7: User Story 5 - Reusable Workflow Definitions (Priority: P3)

**Goal**: Define the workflow format specification and ensure workflows are tracked in git.

**Independent Test**: Verify workflow-format.md exists in templates, .gitignore allows `.kiln/workflows/` to be tracked.

### Implementation for User Story 5

This story's work is covered by T030 (workflow format spec) in Phase 4 and T023 (gitignore) in Phase 4. No additional tasks needed.

**Checkpoint**: Workflow format specification exists. `.kiln/workflows/` is tracked in git.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and documentation

- [ ] T037 Add deprecation notice to CLAUDE.md and README noting migration from speckit-harness to kiln per FR-007
- [ ] T038 Final verification: grep entire repository for "speckit-harness" — only intentional deprecation notices should remain
- [ ] T039 Update `plugin/bin/init.mjs` verify() function to check for `.kiln/` directory and report "kiln plugin" instead of "speckit-harness plugin"

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Empty — no work needed
- **Foundational (Phase 2)**: Empty — no work needed
- **User Story 1 (Phase 3)**: No dependencies — can start immediately. MUST complete before Phase 4 since all file references change.
- **User Story 2 (Phase 4)**: Depends on Phase 3 completion (skill directories must be renamed before editing SKILL.md files)
- **User Story 3 (Phase 5)**: Depends on Phase 4 completion (needs .kiln/ structure defined)
- **User Story 4 (Phase 6)**: Can run in parallel with Phase 5 (independent agent/skill edits)
- **User Story 5 (Phase 7)**: Covered by Phase 4 tasks
- **Polish (Phase 8)**: Depends on all prior phases

### User Story Dependencies

- **US1 (Rename)**: No dependencies — start immediately
- **US2 (.kiln/ Infrastructure)**: Depends on US1 (files must be renamed first)
- **US3 (Doctor)**: Depends on US2 (.kiln/ structure must be defined first)
- **US4 (QA Version Check)**: Independent of US2/US3 — can run in parallel with US3
- **US5 (Workflows)**: Covered by US2 tasks

### Within Each User Story

- Directory renames (T003-T013) before cross-reference updates (T014-T016)
- Package/manifest updates (T001-T002) can parallel with directory renames
- Init.mjs updates (T017, T022) after directory renames complete
- CLAUDE.md updates (T018-T019) can parallel with init.mjs updates

### Parallel Opportunities

- T001 and T002 can run in parallel
- T003 through T013 (directory renames) can all run in parallel
- T015, T016, T019, T020 can run in parallel
- T023, T025, T026, T027, T029 can run in parallel
- T035 and T036 can run in parallel

---

## Parallel Example: User Story 1

```bash
# Batch 1: Package + manifest updates (parallel)
Task T001: Update plugin/package.json
Task T002: Update plugin/.claude-plugin/plugin.json

# Batch 2: All directory renames (parallel)
Task T003-T013: Rename all speckit-* skill directories

# Batch 3: Cross-reference updates (parallel where marked)
Task T014: Update all SKILL.md cross-references
Task T015: Update agent file references (parallel)
Task T016: Update hooks.json (parallel)

# Batch 4: Branding updates (parallel where marked)
Task T017: Update init.mjs
Task T018: Update root CLAUDE.md
Task T019: Update scaffold CLAUDE.md (parallel)
Task T020: Update package.json keywords (parallel)

# Batch 5: Verification
Task T021: Grep verification
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 3: User Story 1 (Rename)
2. **STOP and VALIDATE**: Grep for "speckit-harness" returns zero matches
3. All skills discoverable under new names

### Incremental Delivery

1. User Story 1 (Rename) → Validate branding is clean
2. User Story 2 (.kiln/ Infrastructure) → Validate init.mjs scaffolds .kiln/
3. User Story 3 (Doctor) → Validate diagnose and fix modes work
4. User Story 4 (QA Version Check) → Validate pre-flight instructions in agent/skills
5. Polish → Final verification pass

### Parallel Team Strategy

With multiple implementers:
1. All complete User Story 1 awareness (it changes file paths everyone touches)
2. Once US1 is done:
   - Implementer A: User Story 2 + 5 (infrastructure)
   - Implementer B: User Story 3 (doctor)
   - Implementer C: User Story 4 (QA version check)
3. Polish phase after all stories merge

---

## Notes

- This plugin consists of markdown files, shell scripts, and one JavaScript file — no compiled code
- "Implementation" means editing instruction text in SKILL.md and agent .md files, plus renaming directories
- No test suite exists; validation is done by running the pipeline on consumer projects
- Directory renames must happen before content edits to avoid editing files at old paths
- The grep verification (T021, T038) is critical — it's the primary way to confirm rename completeness
