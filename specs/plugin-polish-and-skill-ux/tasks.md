# Tasks: Plugin Polish & Skill UX

**Input**: Design documents from `specs/plugin-polish-and-skill-ux/`
**Prerequisites**: plan.md (required), spec.md (required), contracts/interfaces.md

**Tests**: Not applicable — plugin testing is done via pipeline runs on consumer projects.

**Organization**: Tasks grouped by user story. US1 and US2 are P1 (highest), then US3-US6.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: No project initialization needed — all target files already exist. This phase is empty.

---

## Phase 2: Foundational

**Purpose**: No shared foundational tasks — each user story modifies independent files.

---

## Phase 3: User Story 1 — Workflow Ships with Plugin (Priority: P1)

**Goal**: Make `/report-issue` work out of the box in consumer projects by shipping the workflow with the npm package and syncing it during init/update.

**Independent Test**: Install the plugin in a fresh project, run `/report-issue`, verify the workflow executes without manual file copying.

### Implementation for User Story 1

- [X] T001 [US1] Add `"workflows"` array to `plugin-kiln/.claude-plugin/plugin.json` declaring `"workflows/report-issue-and-sync.json"` (FR-001)
- [X] T002 [US1] Add `syncWorkflows()` function to `plugin-kiln/bin/init.mjs` that reads plugin.json workflows array and copies each to consumer `workflows/` directory using `copyIfMissing()` (FR-002)
- [X] T003 [US1] Call `syncWorkflows()` from `syncShared()` function in `plugin-kiln/bin/init.mjs` so it runs on both `init` and `update` commands (FR-002)

**Checkpoint**: Consumer projects get `report-issue-and-sync.json` automatically on init/update.

---

## Phase 4: User Story 2 — Trim-Push Full Page Compositions (Priority: P1)

**Goal**: Upgrade trim-push to classify files as component vs page and push them to appropriate Penpot locations.

**Independent Test**: Run trim-push on a project with `components/` and `pages/` directories, verify both component bento grid and individual page frames appear in Penpot.

### Implementation for User Story 2

- [X] T004 [US2] Add `classify-files` command step to `plugin-trim/workflows/trim-push.json` after `scan-components` step — classifies each file as "component" or "page" based on directory conventions (FR-003)
- [X] T005 [US2] Update `push-to-penpot` agent instruction in `plugin-trim/workflows/trim-push.json` to read classification output and handle component vs page push: components to "Components" bento grid page, pages to individual Penpot pages as full-screen composed frames (FR-004)
- [X] T006 [US2] Add `classify-files` to the `context_from` array of `push-to-penpot` step in `plugin-trim/workflows/trim-push.json` (FR-004)
- [X] T007 [US2] Update `plugin-trim/skills/trim-push/SKILL.md` to document component vs page classification behavior and update the report format to show counts for both types (FR-005)

**Checkpoint**: Trim-push creates both component-level and page-level Penpot frames.

---

## Phase 5: User Story 3 — Clean Init Scaffold (Priority: P2)

**Goal**: Stop creating `src/` and `tests/` directories during `kiln init`.

**Independent Test**: Run `kiln init` on an empty repo, verify `.kiln/`, `specs/`, `.specify/` are created but `src/` and `tests/` are NOT.

### Implementation for User Story 3

- [X] T008 [US3] Remove the `for (const dir of ["src", "tests"])` block (lines 88-96) from `scaffoldProject()` in `plugin-kiln/bin/init.mjs` (FR-006)

**Checkpoint**: Init scaffold no longer creates opinionated project directories.

---

## Phase 6: User Story 4 — Wheel Pre-flight Auto-Setup (Priority: P2)

**Goal**: Show a clear error message when wheel isn't configured, instead of opaque failures.

**Independent Test**: Run `/wheel-run` without wheel configured, verify the message mentions `/wheel-init`.

### Implementation for User Story 4

- [X] T009 [US4] Add Step 0 pre-flight check to `plugin-wheel/skills/wheel-run/SKILL.md` before current Step 1 — verify `.wheel/` directory exists, print actionable message if missing, offer to run `/wheel-init` (FR-007, FR-008)

**Checkpoint**: Wheel failures produce actionable guidance.

---

## Phase 7: User Story 5 — /next High-Level Commands Only (Priority: P2)

**Goal**: Filter `/next` output to show only user-facing commands, not internal pipeline steps.

**Independent Test**: Run `/next`, verify output contains zero internal pipeline commands.

### Implementation for User Story 5

- [ ] T010 [US5] Add command filtering section to Step 4 in `plugin-kiln/skills/next/SKILL.md` with whitelist of allowed commands and blocklist of internal commands, including replacement rules (FR-009, FR-010)
- [ ] T011 [US5] Update the Command Mapping Rules table in `plugin-kiln/skills/next/SKILL.md` to use only whitelisted commands as outputs — replace `/implement` with `/build-prd`, `/specify` with `/build-prd`, `/debug-diagnose` with `/fix` (FR-009, FR-010)

**Checkpoint**: `/next` only recommends high-level user-facing commands.

---

## Phase 8: User Story 6 — Issue Backlinks with Repo and File Context (Priority: P3)

**Goal**: Add repo URL and file path backlinks to backlog issue frontmatter.

**Independent Test**: Run `/report-issue`, verify the created issue has `repo:` and `files:` fields.

### Implementation for User Story 6

- [ ] T012 [P] [US6] Add `repo` and `files` fields to frontmatter in `plugin-kiln/templates/issue.md` (FR-011)
- [ ] T013 [P] [US6] Update scaffold copy of issue template — run sync or update `plugin-kiln/scaffold/` if needed to include new frontmatter fields (FR-011)
- [ ] T014 [US6] Update `plugin-kiln/skills/report-issue/SKILL.md` to instruct the workflow agent to auto-detect repo URL via `gh repo view --json url` and extract file paths from description into frontmatter (FR-012)

**Checkpoint**: New backlog issues include repo URL and relevant file paths.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final validation across all changes.

- [X] T015 Verify `plugin-kiln/package.json` `files` array still includes all needed directories (`workflows/` is already listed)
- [X] T016 Verify backwards compatibility: existing consumer projects with customized workflows, existing issues without new fields, existing wheel setups all continue working

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Empty — no setup needed
- **Foundational (Phase 2)**: Empty — no shared prerequisites
- **User Stories (Phases 3-8)**: All independent — can run in parallel
- **Polish (Phase 9)**: Depends on all user stories being complete

### User Story Dependencies

- **US1** (Workflow Ships): Independent — modifies `plugin-kiln/plugin.json` + `init.mjs`
- **US2** (Trim-Push Pages): Independent — modifies `plugin-trim/` files only
- **US3** (Clean Init): Independent — modifies `init.mjs` (different section than US1)
- **US4** (Wheel Pre-flight): Independent — modifies `plugin-wheel/` files only
- **US5** (/next Filtering): Independent — modifies `plugin-kiln/skills/next/`
- **US6** (Issue Backlinks): Independent — modifies `plugin-kiln/templates/` + `skills/report-issue/`

### Parallel Opportunities

All 6 user stories can be worked on in parallel since they modify different files:
- **Agent A** (impl-packaging): US1 + US3 + US4 (FR-001,002,006,007,008) — plugin-kiln init.mjs, plugin.json, plugin-wheel
- **Agent B** (impl-skills): US2 + US5 + US6 (FR-003,004,005,009,010,011,012) — plugin-trim, plugin-kiln skills/templates

---

## Parallel Example: Two Implementers

```
Agent impl-packaging (parallel):
  T001 [US1] plugin.json workflows declaration
  T002 [US1] syncWorkflows() in init.mjs
  T003 [US1] Call syncWorkflows() from syncShared()
  T008 [US3] Remove src/tests from init.mjs
  T009 [US4] Wheel pre-flight in wheel-run SKILL.md

Agent impl-skills (parallel):
  T004 [US2] classify-files step in trim-push.json
  T005 [US2] push-to-penpot page-aware instruction
  T006 [US2] context_from update
  T007 [US2] trim-push SKILL.md docs
  T010 [US5] Command filtering in next SKILL.md
  T011 [US5] Command mapping table update
  T012 [US6] Issue template frontmatter
  T013 [US6] Scaffold template sync
  T014 [US6] Report-issue auto-detection
```

---

## Implementation Strategy

### MVP First (User Story 1 — Workflow Ships)

1. Complete T001-T003 (workflow packaging)
2. Verify: consumer project discovers the workflow via plugin manifest
3. This alone fixes the highest-severity bug

### Incremental Delivery

1. US1 (Workflow Ships) + US3 (Clean Init) -> Plugin packaging fixed
2. US4 (Wheel Pre-flight) -> Onboarding improved
3. US5 (/next Filtering) -> UX improved
4. US6 (Issue Backlinks) -> Triage improved
5. US2 (Trim-Push Pages) -> Design pipeline complete
6. Polish (T015-T016) -> Final validation

---

## Notes

- All tasks modify existing files — no new files are created except during init/update runs in consumer projects
- US1 and US3 both modify `init.mjs` but different sections (syncShared vs scaffoldProject) — safe for same agent
- T012 and T013 are marked [P] because they modify different files
- No test tasks — plugin testing is via pipeline runs per CLAUDE.md
