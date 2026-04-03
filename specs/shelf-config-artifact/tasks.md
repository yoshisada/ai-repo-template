# Tasks: Shelf Config Artifact

**Input**: Design documents from `specs/shelf-config-artifact/`
**Prerequisites**: plan.md (required), spec.md (required), contracts/interfaces.md

**Tests**: Not applicable — this is a Markdown-only plugin with no compiled code or test suite.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: No setup needed — all target files already exist. This feature modifies existing SKILL.md files only.

(No tasks in this phase)

---

## Phase 2: Foundational

**Purpose**: No foundational/blocking tasks. Each skill file modification is independent.

(No tasks in this phase)

---

## Phase 3: User Story 1 - Config Created on Project Setup (Priority: P1)

**Goal**: `/shelf-create` writes a `.shelf-config` file to the repo root after successfully creating the Obsidian project, with confirmed slug, base_path, and dashboard_path values.

**Independent Test**: Run `/shelf-create plugin-shelf` in a repo. Verify `.shelf-config` exists at repo root with correct key-value pairs.

### Implementation for User Story 1

- [X] T001 [US1] Update shelf-create to read slug from .shelf-config in Step 1 (Resolve Project Slug) and Step 2 (Resolve Base Path) per contracts/interfaces.md parsing algorithm in plugin-shelf/skills/shelf-create/SKILL.md
- [X] T002 [US1] Add new Step 9.5 (Write .shelf-config) to shelf-create that writes the config file after directory structure creation, including user confirmation prompt per FR-007, in plugin-shelf/skills/shelf-create/SKILL.md
- [X] T003 [US1] Update Step 10 (Report Results) in shelf-create to include .shelf-config in the summary output in plugin-shelf/skills/shelf-create/SKILL.md

**Checkpoint**: shelf-create writes .shelf-config after project creation. Other skills not yet updated.

---

## Phase 4: User Story 2 - Skills Read Config Automatically (Priority: P1)

**Goal**: All 5 reading skills resolve project identity from `.shelf-config` instead of guessing from git remote. No arguments needed when config exists.

**Independent Test**: With `.shelf-config` present containing `slug = plugin-shelf` and `base_path = @second-brain/projects`, run `/shelf-status` with no arguments. Verify it reads the correct Obsidian project.

### Implementation for User Story 2

- [X] T004 [P] [US2] Replace Steps 1-2 in shelf-sync with unified "Resolve Project Identity" step per contracts/interfaces.md Contract 3 in plugin-shelf/skills/shelf-sync/SKILL.md
- [X] T005 [P] [US2] Replace Steps 1-2 in shelf-update with unified "Resolve Project Identity" step per contracts/interfaces.md Contract 3 in plugin-shelf/skills/shelf-update/SKILL.md
- [X] T006 [P] [US2] Replace Steps 1-2 in shelf-status with unified "Resolve Project Identity" step per contracts/interfaces.md Contract 3 in plugin-shelf/skills/shelf-status/SKILL.md
- [X] T007 [P] [US2] Replace Steps 1-2 in shelf-feedback with unified "Resolve Project Identity" step per contracts/interfaces.md Contract 3 in plugin-shelf/skills/shelf-feedback/SKILL.md
- [X] T008 [P] [US2] Replace Steps 1-2 in shelf-release with unified "Resolve Project Identity" step per contracts/interfaces.md Contract 3 in plugin-shelf/skills/shelf-release/SKILL.md

**Checkpoint**: All 6 shelf skills read .shelf-config. The full feature is functional end-to-end.

---

## Phase 5: User Story 3 - Graceful Fallback Without Config (Priority: P2)

**Goal**: All skills continue to work correctly when `.shelf-config` is absent or malformed, using the existing default behavior.

**Independent Test**: Remove `.shelf-config` and run `/shelf-status`. Verify it falls back to git remote derivation.

### Implementation for User Story 3

No additional tasks — the unified "Resolve Project Identity" step written in Phase 4 already includes the fallback logic (step 2 of Contract 3). The fallback is built into the path resolution algorithm. This story is validated by review, not by additional code changes.

**Checkpoint**: Fallback behavior is verified as part of the unified path resolution step.

---

## Phase 6: User Story 4 - Manual Config Editing (Priority: P3)

**Goal**: Users can manually edit `.shelf-config` and all skills respect the updated values.

**Independent Test**: Edit `.shelf-config` to change the slug, run `/shelf-status`, verify it uses the new slug.

### Implementation for User Story 4

No additional tasks — the parsing algorithm in Contract 1 reads the file fresh on every invocation. Manual edits are automatically respected. This story is validated by review, not by additional code changes.

**Checkpoint**: Manual editing works by design — no code changes needed.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final cleanup and verification across all skill files.

- [ ] T009 Verify all 6 SKILL.md files have consistent path resolution wording and step numbering after modifications across all files in plugin-shelf/skills/*/SKILL.md
- [ ] T010 Run quickstart.md validation — verify the documented usage matches the implemented behavior in specs/shelf-config-artifact/quickstart.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 3 (US1 - shelf-create writes config)**: No dependencies — can start immediately
- **Phase 4 (US2 - skills read config)**: Independent of Phase 3 — can run in parallel
- **Phase 5 (US3 - fallback)**: No tasks — validated by Phase 4 implementation
- **Phase 6 (US4 - manual editing)**: No tasks — validated by Phase 4 implementation
- **Phase 7 (Polish)**: Depends on Phases 3 and 4 completion

### User Story Dependencies

- **User Story 1 (P1)**: No dependencies — shelf-create changes are self-contained
- **User Story 2 (P1)**: No dependencies on US1 — each skill's path resolution is independent
- **User Story 3 (P2)**: Validated by US2 implementation — no separate tasks
- **User Story 4 (P3)**: Validated by US2 implementation — no separate tasks

### Within Each User Story

- US1: T001 → T002 → T003 (sequential — same file, each step builds on the previous)
- US2: T004, T005, T006, T007, T008 (all parallel — different files, no dependencies)

### Parallel Opportunities

- T004, T005, T006, T007, T008 can all run in parallel (5 different SKILL.md files)
- US1 (Phase 3) and US2 (Phase 4) can run in parallel (different files)

---

## Parallel Example: User Story 2

```bash
# All 5 skill file updates can run in parallel:
Task: "Replace Steps 1-2 in shelf-sync" (T004)
Task: "Replace Steps 1-2 in shelf-update" (T005)
Task: "Replace Steps 1-2 in shelf-status" (T006)
Task: "Replace Steps 1-2 in shelf-feedback" (T007)
Task: "Replace Steps 1-2 in shelf-release" (T008)
```

---

## Implementation Strategy

### MVP First (User Story 1 + User Story 2)

1. Complete Phase 3: shelf-create writes .shelf-config (T001-T003)
2. Complete Phase 4: All reading skills consume .shelf-config (T004-T008)
3. **STOP and VALIDATE**: Test end-to-end by running `/shelf-create` then `/shelf-status`
4. Complete Phase 7: Polish and verify consistency (T009-T010)

### Incremental Delivery

1. Modify shelf-create → config file is now written
2. Modify all 5 reading skills in parallel → config is now consumed
3. Polish → verify consistency across all files
4. Each step adds value without breaking existing behavior

---

## Notes

- All tasks modify Markdown (SKILL.md) files — no compiled code, no tests to run
- The `.shelf-config` file itself is created at runtime in consumer projects, not in this repo
- US3 and US4 require no implementation tasks — they are satisfied by the fallback logic built into the unified path resolution step (Contract 3)
- [P] tasks = different files, no dependencies
- Commit after each completed phase
