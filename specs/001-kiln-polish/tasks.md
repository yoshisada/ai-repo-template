# Tasks: Kiln Polish

**Input**: Design documents from `specs/001-kiln-polish/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Not applicable — this feature modifies markdown skill files, shell scripts, and scaffold code. No compiled test suite.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: No setup needed — all changes are to existing files in the plugin directory.

(No tasks in this phase)

---

## Phase 2: Foundational (QA Directory Manifest)

**Purpose**: Define the canonical QA directory structure in the manifest. This must be done before any skill/agent updates reference the new paths.

- [X] T001 Update QA directory manifest with subdirectory entries in plugin/templates/kiln-manifest.json (FR-004)
- [X] T002 Create QA README scaffold template at plugin/scaffold/qa-readme.md (FR-008)

**Checkpoint**: Manifest and README template exist — skill/agent updates can now reference the canonical structure.

---

## Phase 3: User Story 1 — Suggested Next Command (Priority: P1)

**Goal**: `/next` ends with a single prominent "Suggested next" line showing the highest-priority command with a reason.

**Independent Test**: Run `/next` on a project with outstanding work and verify the last content line (before the report footer) is a blockquote starting with "Suggested next:".

### Implementation for User Story 1

- [ ] T003 [US1] Add "Suggested next" output section to Step 5 (terminal summary) in plugin/skills/next/SKILL.md (FR-001, FR-002)
- [ ] T004 [US1] Add "Nothing urgent" fallback to the "Suggested next" section for clean projects in plugin/skills/next/SKILL.md (FR-003)
- [ ] T005 [US1] Ensure "Suggested next" line appears in --brief mode output in plugin/skills/next/SKILL.md (FR-001)
- [ ] T006 [US1] Add "Suggested next" to the persistent report format in Step 6 of plugin/skills/next/SKILL.md (FR-001)

**Checkpoint**: `/next` shows a "Suggested next" line in all modes (normal, brief, clean project). US1 is independently testable.

---

## Phase 4: User Story 2 — QA Directory Structure (Priority: P1)

**Goal**: `.kiln/qa/` has five standard subdirectories created by `/qa-setup`, and QA agents write to canonical paths.

**Independent Test**: Run `/qa-setup` and verify `.kiln/qa/tests/`, `.kiln/qa/results/`, `.kiln/qa/screenshots/`, `.kiln/qa/videos/`, `.kiln/qa/config/` all exist.

### Implementation for User Story 2

- [ ] T007 [P] [US2] Update mkdir command and output paths in plugin/skills/qa-setup/SKILL.md to use canonical subdirectories (FR-005)
- [ ] T008 [P] [US2] Update report output paths in plugin/agents/qa-reporter.md to write to .kiln/qa/results/ (FR-006)
- [ ] T009 [P] [US2] Update screenshot paths in plugin/agents/ux-evaluator.md to write to .kiln/qa/screenshots/ (FR-006)
- [ ] T010 [US2] Update QA report read paths in Step 2 of plugin/skills/next/SKILL.md to read from .kiln/qa/results/ (FR-006)

**Checkpoint**: QA skills and agents use canonical paths. US2 is independently testable.

---

## Phase 5: User Story 3 — QA Directory README (Priority: P2)

**Goal**: `.kiln/qa/README.md` documents the directory layout.

**Independent Test**: Read plugin/scaffold/qa-readme.md and verify it documents each subdirectory's purpose, expected file types, and which skills/agents write to each location.

### Implementation for User Story 3

(Covered by T002 in Phase 2 — the README template was created as a foundational task. No additional work needed.)

**Checkpoint**: README template exists and documents the full QA directory structure.

---

## Phase 6: User Story 4 — Scaffold Creates QA Structure (Priority: P2)

**Goal**: `init.mjs` creates QA subdirectories and copies the README during scaffold.

**Independent Test**: Read the updated init.mjs and verify the kilnDirs array includes the five QA subdirectories, and a copyIfMissing call copies qa-readme.md to .kiln/qa/README.md.

### Implementation for User Story 4

- [ ] T011 [US4] Add QA subdirectories to kilnDirs array and add README copy in plugin/bin/init.mjs (FR-007)
- [ ] T012 [US4] Update gitignore paths in plugin/scaffold/gitignore for new canonical QA locations

**Checkpoint**: init.mjs creates the full QA directory structure with README. US4 is independently testable.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Ensure consistency across all modified files.

- [ ] T013 Verify all QA path references are consistent across modified files (cross-check contracts/interfaces.md path mapping table)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 2 (Foundational)**: No dependencies — start immediately
- **Phase 3 (US1 — Suggested Next)**: No dependencies on Phase 2 — can start in parallel
- **Phase 4 (US2 — QA Directory Structure)**: Depends on Phase 2 (T001 manifest must exist)
- **Phase 5 (US3 — QA README)**: Covered by T002 in Phase 2
- **Phase 6 (US4 — Scaffold)**: Depends on Phase 2 (T002 README template must exist)
- **Phase 7 (Polish)**: Depends on all prior phases

### User Story Dependencies

- **User Story 1 (P1)**: Independent — no dependencies on other stories
- **User Story 2 (P1)**: Depends on T001 (manifest) from Phase 2
- **User Story 3 (P2)**: Completed as part of Phase 2 (T002)
- **User Story 4 (P2)**: Depends on T002 (README template) from Phase 2

### Within Each User Story

- Tasks marked [P] within a phase can run in parallel
- T003 and T004 are sequential (both modify the same file section)
- T007, T008, T009 can run in parallel (different files)

### Parallel Opportunities

- Phase 2 tasks T001 and T002 can run in parallel (different files)
- Phase 3 (US1) can run in parallel with Phase 2 (no dependency)
- Phase 4 tasks T007, T008, T009 can run in parallel (different files)
- Phase 6 tasks T011 and T012 can run in parallel (different files)

---

## Parallel Example: User Story 2

```bash
# Launch all agent/skill updates together (different files):
Task: "Update mkdir and output paths in plugin/skills/qa-setup/SKILL.md" (T007)
Task: "Update report paths in plugin/agents/qa-reporter.md" (T008)
Task: "Update screenshot paths in plugin/agents/ux-evaluator.md" (T009)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (T001, T002)
2. Complete Phase 3: User Story 1 (T003–T006)
3. **STOP and VALIDATE**: Test `/next` independently
4. The "Suggested next" feature is usable without QA directory changes

### Incremental Delivery

1. Phase 2 (Foundational) → Manifest + README template ready
2. Phase 3 (US1) → `/next` shows suggested command → Testable
3. Phase 4 (US2) → QA skills use canonical paths → Testable
4. Phase 6 (US4) → Scaffold creates QA structure → Testable
5. Phase 7 (Polish) → Cross-file consistency verified

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- No test tasks — this feature modifies markdown and scaffold code, not compiled code
- Total: 13 tasks across 6 phases
- All file paths are relative to the repository root
