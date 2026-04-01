# Tasks: Pipeline Workflow Polish

**Input**: Design documents from `specs/pipeline-workflow-polish/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, contracts/interfaces.md

**Organization**: Tasks are grouped by user story to enable independent implementation. Each phase targets a distinct set of files with no overlap.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- All paths are relative to repo root

---

## Phase 1: Setup

**Purpose**: No setup needed — this feature modifies existing files and creates 3 new files in the existing plugin structure. No dependencies to install, no project initialization required.

---

## Phase 2: User Story 1 — Non-Compiled Feature Validation (Priority: P1) — FR-001, FR-002, FR-003

**Goal**: Create a validation gate for non-compiled features (frontmatter, bash syntax, file references, scaffold) and integrate it into `/implement` and `/audit`.

**Independent Test**: Modify a SKILL.md with bad frontmatter/bash and verify the validation script catches it.

### Implementation

- [ ] T001 [US1] Create non-compiled validation script at scripts/validate-non-compiled.sh — FR-001. Must: (a) accept `--files` and `--all` flags, (b) detect modified files via `git diff` when no flags given, (c) check frontmatter structure in SKILL.md files, (d) extract bash code blocks and run `bash -n`, (e) scan file path references and verify they exist, (f) run `node plugin/bin/init.mjs init` in a temp dir for scaffold verification, (g) output structured markdown report, (h) exit 0 on pass / 1 on fail
- [ ] T002 [US1] Update plugin/skills/implement/SKILL.md to add non-compiled validation gate — FR-002. After step 9 (completion validation), add logic: if no `src/` directory changes exist in the feature branch, skip the 80% coverage gate and run `bash scripts/validate-non-compiled.sh` instead. Report validation results as coverage substitute. Halt on non-zero exit.
- [ ] T003 [US1] Update plugin/skills/audit/SKILL.md to include non-compiled validation evidence in the auditor checklist — FR-003. Add checklist item: "Non-compiled validation: [PASS/FAIL/N/A]" with file counts per check category.

**Checkpoint**: Validation script runs standalone. `/implement` routes non-compiled features through it. Auditor reports include validation evidence.

---

## Phase 3: User Story 2 — Branch and Spec Directory Naming Enforcement (Priority: P1) — FR-004, FR-005, FR-006

**Goal**: Enforce consistent branch and spec directory naming in `/build-prd` and broadcast canonical paths to all agents.

**Independent Test**: Run `/build-prd` and verify the branch name matches `build/<slug>-YYYYMMDD`, spec dir is `specs/<slug>/`, and agent prompts include both paths.

### Implementation

- [ ] T004 [US2] Update plugin/skills/build-prd/SKILL.md Step 5 (branch creation) to enforce `build/<feature-slug>-<YYYYMMDD>` naming — FR-004. Replace the existing branch creation bash block with stricter logic: derive feature slug from PRD directory name (lowercase, hyphenated, 2-4 words), format branch as `build/$SLUG-$(date +%Y%m%d)`, always create fresh from current HEAD via `git checkout -b`.
- [ ] T005 [US2] Update plugin/skills/build-prd/SKILL.md specifier agent prompt to enforce spec directory naming `specs/<feature-slug>/` — FR-005. The feature slug MUST match the branch name's feature portion (between `build/` and `-YYYYMMDD`). No numeric prefixes.
- [ ] T006 [US2] Update plugin/skills/build-prd/SKILL.md Step 2 (agent spawn) to broadcast canonical branch name and spec directory path to all teammates at spawn time — FR-006. Each agent's prompt must include: "Branch: <branch-name>, Spec directory: specs/<feature-slug>/".

**Checkpoint**: `/build-prd` creates correctly named branches and spec dirs. All agents receive canonical paths.

---

## Phase 4: User Story 3 — Issue Lifecycle Auto-Completion (Priority: P2) — FR-007, FR-008

**Goal**: Auto-complete `prd-created` issues after successful pipeline runs and archive them.

**Independent Test**: Create a `.kiln/issues/` entry with `status: prd-created` and matching `prd:` field, simulate pipeline completion, verify status update and archival.

### Implementation

- [ ] T007 [US3] Update plugin/skills/build-prd/SKILL.md to add issue lifecycle completion step after PR creation and before retrospective — FR-007. New step must: (a) read the PRD path used for this build, (b) scan `.kiln/issues/*.md` for `status: prd-created`, (c) check each issue's `prd:` frontmatter against the built PRD path, (d) update matching issues to `status: completed` with `completed_date` and `pr` fields.
- [ ] T008 [US3] In the same build-prd step, add issue archival — FR-008. After updating status, if `.kiln/issues/completed/` exists or can be created, move completed issues there via `mv`.

**Checkpoint**: Pipeline runs auto-complete and archive matching issues.

---

## Phase 5: User Story 4 — Issue and Artifact Cleanup (Priority: P2) — FR-009, FR-010

**Goal**: Extend `/kiln-cleanup` for issue archival and `/kiln-doctor` for stale issue detection.

**Independent Test**: Place completed/prd-created issues in `.kiln/issues/`, run `/kiln-cleanup --dry-run` to verify report, run `/kiln-doctor` to verify stale detection.

### Implementation

- [ ] T009 [P] [US4] Update plugin/skills/kiln-cleanup/SKILL.md to add issue archival — FR-009. Add a new step between Step 2 and Step 3 that: (a) scans `.kiln/issues/*.md` for `status: prd-created` or `status: completed`, (b) in dry-run mode reports what would be archived, (c) in delete mode creates `.kiln/issues/completed/` if needed and moves matching issues there, (d) displays results in table format matching existing QA scan output.
- [ ] T010 [P] [US4] Update plugin/skills/kiln-doctor/SKILL.md to detect stale `prd-created` issues — FR-010. Add a new Step 3f that: (a) greps `.kiln/issues/*.md` for `status: prd-created`, (b) reports each as "STALE: <filename> — status is prd-created (bundled into PRD but never built)", (c) includes findings in the diagnosis table as a new row type.

**Checkpoint**: `/kiln-cleanup` archives issues. `/kiln-doctor` reports stale issues.

---

## Phase 6: User Story 5 — Commit Noise Reduction (Priority: P3) — FR-011, FR-012, FR-013

**Goal**: Reduce commit count by folding version bumps and task-marking into phase commits.

**Independent Test**: Implement a single-phase feature and count resulting commits vs. baseline.

### Implementation

- [ ] T011 [US5] Update plugin/hooks/version-increment.sh to stage changes instead of just writing — FR-011. At the end of the script (after writing VERSION and syncing to package.json/plugin.json), add `git add` calls to stage the modified files so they are included in the next commit the agent creates.
- [ ] T012 [US5] Update plugin/skills/implement/SKILL.md step 8 to combine task-marking into phase commits — FR-012. Add instruction that for single-phase features, task-marking updates to tasks.md SHOULD be included in the phase commit rather than committed separately.
- [ ] T013 [US5] Update plugin/skills/build-prd/SKILL.md QA engineer role description to add QA snapshot guidance — FR-013. Add instruction: "QA result snapshots and incremental test-result files MUST NOT be committed to the feature branch. They belong in `.kiln/qa/` which is gitignored."

**Checkpoint**: Version hook stages changes. Single-phase features produce fewer commits. QA snapshots stay out of git.

---

## Phase 7: User Story 6 — Roadmap Tracking and /next Integration (Priority: P3) — FR-014, FR-015, FR-016

**Goal**: Add roadmap scaffold, `/roadmap` skill, and integrate with `/next`.

**Independent Test**: Run `/roadmap Add monorepo support`, verify it appears in `.kiln/roadmap.md`. Run `/next` with no pending work, verify roadmap items surface.

### Implementation

- [ ] T014 [P] [US6] Create roadmap template at plugin/templates/roadmap-template.md — FR-014. Simple markdown with heading and theme groups: "DX Improvements", "New Capabilities", "Tech Debt", "General". No frontmatter, no status tracking.
- [ ] T015 [P] [US6] Create roadmap skill at plugin/skills/roadmap/SKILL.md — FR-015. Must: (a) check if `.kiln/roadmap.md` exists, create from template if not, (b) parse user input as item description, (c) identify best matching theme group, (d) append item as bullet under that group, (e) report what was added.
- [ ] T016 [US6] Update plugin/bin/init.mjs to scaffold `.kiln/roadmap.md` from template — FR-014. Use existing `copyIfMissing` pattern to copy `plugin/templates/roadmap-template.md` to `.kiln/roadmap.md`.
- [ ] T017 [US6] Update plugin/skills/next/SKILL.md to surface roadmap items when no urgent work exists — FR-016. Add conditional section: if no incomplete tasks, no open blockers, no critical issues, read `.kiln/roadmap.md`, extract up to 5 items, display "Nothing pressing. Here are some ideas from your roadmap:" followed by the items.

**Checkpoint**: Roadmap file scaffolded. `/roadmap` appends items. `/next` surfaces roadmap when idle.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [ ] T018 Verify all modified SKILL.md files have valid frontmatter and consistent formatting
- [ ] T019 Run `bash scripts/validate-non-compiled.sh --all` to self-validate the changes made in this feature

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: N/A — no setup phase needed
- **Phase 2 (US1 — Validation)**: No dependencies — can start immediately. Creates the validation script used by Phase 8.
- **Phase 3 (US2 — Naming)**: No dependencies on Phase 2 — can run in parallel
- **Phase 4 (US3 — Issue Lifecycle)**: No dependencies on Phases 2-3 — can run in parallel
- **Phase 5 (US4 — Cleanup/Doctor)**: No dependencies on Phases 2-4 — can run in parallel
- **Phase 6 (US5 — Commit Noise)**: No dependencies on Phases 2-5 — can run in parallel
- **Phase 7 (US6 — Roadmap)**: No dependencies on Phases 2-6 — can run in parallel
- **Phase 8 (Polish)**: Depends on ALL previous phases

### File Ownership (No Conflicts)

| File | Owner Phase |
|------|-------------|
| scripts/validate-non-compiled.sh | Phase 2 (US1) |
| plugin/skills/implement/SKILL.md | Phase 2 (US1) + Phase 6 (US5) — sequential |
| plugin/skills/audit/SKILL.md | Phase 2 (US1) |
| plugin/skills/build-prd/SKILL.md | Phase 3 (US2) + Phase 4 (US3) + Phase 6 (US5) — sequential |
| plugin/skills/kiln-cleanup/SKILL.md | Phase 5 (US4) |
| plugin/skills/kiln-doctor/SKILL.md | Phase 5 (US4) |
| plugin/hooks/version-increment.sh | Phase 6 (US5) |
| plugin/templates/roadmap-template.md | Phase 7 (US6) |
| plugin/skills/roadmap/SKILL.md | Phase 7 (US6) |
| plugin/bin/init.mjs | Phase 7 (US6) |
| plugin/skills/next/SKILL.md | Phase 7 (US6) |

**Shared file handling**: `implement/SKILL.md` is modified in Phase 2 (FR-002) and Phase 6 (FR-012). `build-prd/SKILL.md` is modified in Phases 3, 4, and 6. These MUST be done sequentially. Split into two implementer groups:

- **impl-pipeline**: Phases 2, 3, 4, 6 (files: validate script, implement, audit, build-prd, version-increment hook) — 13 tasks
- **impl-tooling**: Phases 5, 7 (files: kiln-cleanup, kiln-doctor, roadmap template/skill, init.mjs, next) — 6 tasks

These two groups can run in parallel with no file conflicts.

### Parallel Opportunities

- Phases 5 and 7 can run fully in parallel (no shared files)
- T009 and T010 within Phase 5 can run in parallel [P]
- T014 and T015 within Phase 7 can run in parallel [P]

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Non-compiled validation gate
2. **VALIDATE**: Run the validation script against the plugin repo itself
3. This delivers the highest-value FR (zero-to-something validation for non-compiled features)

### Incremental Delivery

1. Phase 2 (US1): Validation gate — can validate immediately
2. Phase 3 (US2): Branch naming — improves next pipeline run
3. Phase 4 (US3): Issue lifecycle — automates backlog management
4. Phase 5 (US4): Cleanup/doctor extensions — extends existing tools
5. Phase 6 (US5): Commit noise — improves DX
6. Phase 7 (US6): Roadmap — captures future ideas
7. Phase 8: Polish — self-validate everything

### Parallel Team Strategy

With two implementers:
- **impl-pipeline**: Phases 2 → 3 → 4 → 6 (sequential, shared files)
- **impl-tooling**: Phases 5 → 7 (sequential within, parallel with impl-pipeline)
- Both converge at Phase 8 (Polish)

---

## Notes

- All "implementation" is editing markdown and bash — no compiled code
- The non-compiled validation script (T001) should be written first as it self-validates the rest of the work
- Task-marking for this feature should follow FR-012 guidance: fold into phase commits where possible
- Total tasks: 19 (13 for impl-pipeline, 6 for impl-tooling)
