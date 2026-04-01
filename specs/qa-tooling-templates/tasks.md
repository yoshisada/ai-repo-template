# Tasks: QA Agent Optimization, Kiln Doctor Enhancements & Template Improvements

**Input**: Design documents from `specs/qa-tooling-templates/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/interfaces.md

**Tests**: No test tasks — this is a plugin source repo with markdown/bash/JSON files. Verification is done via pipeline runs on consumer projects.

**Organization**: Tasks grouped by user story to enable parallel implementation by separate agents.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Exact file paths included in all descriptions

## Path Conventions

All paths are relative to the repository root: `/Users/ryansuematsu/Documents/github/personal/ai-repo-template/`

---

## Phase 1: Setup

**Purpose**: No project initialization needed — this is an existing plugin repo. Skip directly to user story phases.

*(No tasks in this phase — the repo structure already exists.)*

---

## Phase 2: Foundational

**Purpose**: No blocking prerequisites — all user stories operate on independent files and can begin immediately.

*(No tasks in this phase — all changes are to existing markdown/JSON/JS files with no shared infrastructure to set up.)*

**Checkpoint**: Ready for user story implementation.

---

## Phase 3: User Story 1 - Faster QA Pipeline Runs (Priority: P1)

**Goal**: Reduce QA agent wall-clock time by enabling parallel viewports, failure-only recording, and targeted waits.

**Independent Test**: Run `/qa-setup` on a consumer project and verify the generated Playwright config has `fullyParallel: true`, `video: 'retain-on-failure'`, and `trace: 'retain-on-failure'`. Verify the QA agent instructions prohibit `waitForTimeout` and `networkidle`.

### Implementation for User Story 1

- [X] T001 [P] [US1] Update Playwright config in `plugin/agents/qa-engineer.md` — change `video: 'on'` to `video: 'retain-on-failure'` and `trace: 'on'` to `trace: 'retain-on-failure'` in all config snippets (Step 3 config, test use blocks) — FR-001
- [X] T002 [P] [US1] Update Playwright config in `plugin/skills/qa-setup/SKILL.md` — change `video: 'on'` to `video: 'retain-on-failure'`, `trace: 'on'` to `trace: 'retain-on-failure'`, add `fullyParallel: true` to `defineConfig()`, and add tablet viewport project `{ name: 'tablet', use: { viewport: { width: 768, height: 1024 } } }` in Step 3 and Step 5 — FR-001, FR-002
- [X] T003 [US1] Update `plugin/agents/qa-engineer.md` Test Writing Rules section — add rule: "Prefer `waitForSelector`/`waitForFunction` over `networkidle`. NEVER use `waitForTimeout` — use Playwright auto-waiting assertions instead." — FR-003
- [X] T004 [US1] Add new "Walkthrough Recording" section to `plugin/agents/qa-engineer.md` after Step 7 (QA Report) — when all tests pass, record one clean walkthrough of new feature flows; skip if any tests failed — FR-004

**Checkpoint**: QA agent and setup skill now generate faster Playwright configs with parallel viewports and targeted waits.

---

## Phase 4: User Story 2 - QA Tests Latest Build (Priority: P1)

**Goal**: Ensure the QA agent always tests against the latest build via prompt-based enforcement.

**Independent Test**: Read the QA agent definition and verify it contains explicit instructions to rebuild after every received `SendMessage` and to refuse going idle without a recent build.

### Implementation for User Story 2

- [X] T005 [US2] Add new "Build After Message" section to `plugin/agents/qa-engineer.md` — require the QA agent to run the project build command after every `SendMessage` it receives before proceeding with testing — FR-005
- [X] T006 [US2] Add idle-blocking instruction to the same section in `plugin/agents/qa-engineer.md` — the QA agent MUST NOT go idle if it hasn't run a build since its last received message; it must rebuild first — FR-006

**Checkpoint**: QA agent enforces fresh builds before every test evaluation.

---

## Phase 5: User Story 3 - Feature-Scoped QA Reports (Priority: P2)

**Goal**: Structure QA reports to clearly separate feature-specific results from regression findings.

**Independent Test**: Read the QA agent definition and verify the report template has distinct "Feature Verdict" and "Regression Findings" sections. Verify the agent is instructed to test the feature matrix first.

### Implementation for User Story 3

- [X] T007 [US3] Add new "Feature-Scoped Testing" section to `plugin/agents/qa-engineer.md` — instruct the agent to test the feature's test matrix first, report feature pass/fail as a standalone section before any regression findings — FR-007
- [X] T008 [US3] Restructure the QA Report template in `plugin/agents/qa-engineer.md` Step 7 — split into (1) Feature Verdict (scoped pass/fail with feature test results) and (2) Regression Findings (optional, only when feature touches shared components or explicitly requested) — FR-008

**Checkpoint**: QA reports now clearly separate feature verdict from regression findings.

---

## Phase 6: User Story 4 - Walkthrough Recording (Priority: P2)

**Goal**: Capture a clean walkthrough recording of new features after all tests pass.

**Independent Test**: Covered by T004 in Phase 3. No additional tasks needed — walkthrough recording is part of the QA agent performance changes.

*(Tasks already covered in Phase 3, T004.)*

---

## Phase 7: User Story 5 - Retrospective Agent Friction Data (Priority: P2)

**Goal**: Enable every pipeline agent to write friction notes before shutdown, and the retrospective agent to read them.

**Independent Test**: Read each agent definition and verify it includes a "Friction Notes" section. Read the build-prd skill and verify the retrospective reads from `agent-notes/` directory.

### Implementation for User Story 5

- [X] T009 [P] [US5] Add "Agent Friction Notes" section to `plugin/agents/qa-engineer.md` — before completing, write to `specs/<feature>/agent-notes/qa-engineer.md` with what was confusing, where stuck, and what to improve — FR-009
- [X] T010 [P] [US5] Add "Agent Friction Notes" section to `plugin/agents/debugger.md` — same pattern as T009 — FR-009
- [X] T011 [P] [US5] Add "Agent Friction Notes" section to `plugin/agents/prd-auditor.md` — same pattern as T009 — FR-009
- [X] T012 [P] [US5] Add "Agent Friction Notes" section to `plugin/agents/smoke-tester.md` — same pattern as T009 — FR-009
- [X] T013 [P] [US5] Add "Agent Friction Notes" section to `plugin/agents/spec-enforcer.md` — same pattern as T009 — FR-009
- [X] T014 [P] [US5] Add "Agent Friction Notes" section to `plugin/agents/test-runner.md` — same pattern as T009 — FR-009
- [X] T015 [US5] Update `plugin/skills/build-prd/SKILL.md` — add instruction in the team design section that ALL pipeline agents must write friction notes to `specs/<feature>/agent-notes/<agent-name>.md` before completing their work — FR-009
- [X] T016 [US5] Update `plugin/skills/build-prd/SKILL.md` retrospective section — change retrospective agent to read from `specs/<feature>/agent-notes/` directory instead of relying on live `SendMessage` feedback from teammates — FR-010

**Checkpoint**: All pipeline agents write friction notes and the retrospective agent reads them.

---

## Phase 8: User Story 6 - Kiln Doctor Cleanup and Version Sync (Priority: P2)

**Goal**: Add retention rules, cleanup mode, and version-sync checking to kiln-doctor.

**Independent Test**: Read the kiln-manifest.json for retention rules. Read the kiln-doctor skill for `--cleanup`, `--dry-run`, version-sync check, and version-sync fix sections.

### Implementation for User Story 6

- [X] T017 [US6] Extend `plugin/templates/kiln-manifest.json` — add `retention` property to directory entries: `logs: { keep_last: 10 }`, `issues: { archive_completed: true }`, `qa: { purge_artifacts: true }`. Add `.kiln/issues/completed` directory entry. — FR-011, FR-024
- [X] T018 [US6] Update `plugin/skills/kiln-doctor/SKILL.md` Step 1 — add `--cleanup` mode (applies retention rules) with `--dry-run` support alongside existing `--fix` and `--diagnose` modes — FR-012
- [X] T019 [US6] Add new "Retention Cleanup" step to `plugin/skills/kiln-doctor/SKILL.md` — read retention rules from manifest, apply `keep_last` (delete oldest files beyond limit), `archive_completed` (move closed issues), `purge_artifacts` (remove QA artifacts). Respect `--dry-run` flag. — FR-012
- [X] T020 [US6] Add new "Version Sync Check" step to `plugin/skills/kiln-doctor/SKILL.md` diagnose mode — scan `package.json` and `plugin/package.json` (defaults), compare `version` field against `VERSION` file content, report mismatches — FR-015
- [X] T021 [US6] Add version-sync fix to `plugin/skills/kiln-doctor/SKILL.md` fix mode — when version mismatches are found, update the mismatched files to match `VERSION` — FR-016
- [X] T022 [US6] Add `.kiln/version-sync.json` config support to `plugin/skills/kiln-doctor/SKILL.md` — if the file exists, read `include`/`exclude` arrays to control which files are scanned for version sync — FR-017
- [X] T023 [US6] Integrate QA cleanup into kiln-doctor fix mode in `plugin/skills/kiln-doctor/SKILL.md` — when running `--fix`, also purge stale QA artifacts from `.kiln/qa/` (same behavior as `/kiln-cleanup`) — FR-014

**Checkpoint**: kiln-doctor can diagnose and fix retention, version-sync, and QA artifact issues.

---

## Phase 9: User Story 7 - Dedicated QA Artifact Cleanup (Priority: P3)

**Goal**: Create a new `/kiln-cleanup` skill that removes stale QA artifacts.

**Independent Test**: Verify the new skill file exists at `plugin/skills/kiln-cleanup/SKILL.md` with proper frontmatter, `--dry-run` support, and artifact scanning for `.kiln/qa/` subdirectories.

### Implementation for User Story 7

- [X] T024 [US7] Create `plugin/skills/kiln-cleanup/SKILL.md` — new skill with frontmatter (`name: kiln-cleanup`, `description: Remove stale QA artifacts...`), Step 1: parse `--dry-run` flag, Step 2: scan `.kiln/qa/test-results/`, `playwright-report/`, `videos/`, `traces/` for files, Step 3: in dry-run list files with sizes; otherwise delete and report count/size freed — FR-013

**Checkpoint**: `/kiln-cleanup` skill exists and can purge QA artifacts with dry-run preview.

---

## Phase 10: User Story 8 - Better Templates (Priority: P3)

**Goal**: Externalize the issue template, add common-requirement checklists to spec/PRD templates.

**Independent Test**: Verify `plugin/templates/issue.md` exists with the correct structure. Verify `init.mjs` scaffolds it. Verify spec and plan templates contain the new checklist items.

### Implementation for User Story 8

- [X] T025 [P] [US8] Create `plugin/templates/issue.md` — extract the issue markdown structure (frontmatter + Description + Impact + Suggested Fix sections) from the hardcoded template in `plugin/skills/report-issue/SKILL.md` — FR-018
- [X] T026 [P] [US8] Update `plugin/skills/report-issue/SKILL.md` Step 3 — change from hardcoded template to reading from `plugin/templates/issue.md` (or consumer's `.kiln/templates/issue.md` if it exists) — FR-018
- [X] T027 [US8] Update `plugin/bin/init.mjs` `scaffoldProject()` — add `ensureDir` for `.kiln/templates/`, add `copyIfMissing` for `plugin/templates/issue.md` → `.kiln/templates/issue.md` — FR-019
- [X] T028 [P] [US8] Update `plugin/templates/spec-template.md` — add comment in User Scenarios section: "If feature involves a rename/rebrand: include an FR for grep-based verification of ALL references" — FR-020
- [X] T029 [P] [US8] Update `plugin/templates/spec-template.md` — add comment in Requirements section: "Document credentials and auth flow required for QA testing" — FR-022
- [X] T030 [P] [US8] Update `plugin/templates/plan-template.md` — add comment in Technical Context section: "When depending on container CLI, add Phase 1 task to run `--help` and document results" — FR-021
- [X] T031 [P] [US8] Update `plugin/templates/plan-template.md` — add comment in Technical Context section: "For a11y features, run axe-core locally and fix all violations before committing" — FR-023

**Checkpoint**: Issue template externalized, spec/plan templates updated with common checklists.

---

## Phase 11: User Story 9 - Issue Archival (Priority: P3)

**Goal**: Archive completed issues to `completed/` subdirectory and scope scanning to active issues only.

**Independent Test**: Verify report-issue moves closed/done files to `completed/`. Verify report-issue and issue-to-prd scan only top-level `.kiln/issues/`.

### Implementation for User Story 9

- [X] T032 [US9] Update `plugin/skills/report-issue/SKILL.md` — add archival logic: when setting status to `closed` or `done`, move the file to `.kiln/issues/completed/` (create directory if needed) — FR-024
- [X] T033 [P] [US9] Update `plugin/skills/report-issue/SKILL.md` Step 1 — change duplicate detection to only scan top-level `.kiln/issues/` (not `completed/` subdirectory) — FR-025
- [X] T034 [P] [US9] Update `plugin/skills/issue-to-prd/SKILL.md` Step 1 — change from "Read all `.md` files in `.kiln/issues/`" to "Read all `.md` files in top-level `.kiln/issues/` (not `completed/` subdirectory)" — FR-025
- [X] T035 [US9] Update `plugin/bin/init.mjs` `scaffoldProject()` — add `ensureDir` for `.kiln/issues/completed/` — FR-024
- [X] T036 [US9] Update `plugin/skills/analyze-issues/SKILL.md` — when closing an issue (suggesting closure), add instruction to move the file to `.kiln/issues/completed/` — FR-024

**Checkpoint**: Completed issues archived, active scanning scoped to top-level only.

---

## Phase 12: Polish & Cross-Cutting Concerns

**Purpose**: Final validation across all changes.

- [ ] T037 Verify all 25 FRs are addressed by reading each modified file and cross-referencing against `specs/qa-tooling-templates/contracts/interfaces.md`
- [ ] T038 Verify backwards compatibility — confirm no existing template sections were removed or renamed, only additions

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Skipped — no setup needed
- **Foundational (Phase 2)**: Skipped — no blocking prerequisites
- **User Stories (Phases 3–11)**: All can start immediately and run in parallel
- **Polish (Phase 12)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (P1) — Faster QA**: No dependencies. Modifies `qa-engineer.md` and `qa-setup/SKILL.md`.
- **US2 (P1) — Latest Build**: No dependencies. Modifies `qa-engineer.md` (different sections from US1).
- **US3 (P2) — Scoped Reports**: No dependencies. Modifies `qa-engineer.md` (different sections from US1/US2).
- **US5 (P2) — Friction Notes**: No dependencies. Modifies all agent files + `build-prd/SKILL.md`.
- **US6 (P2) — Doctor Cleanup**: No dependencies. Modifies `kiln-manifest.json` and `kiln-doctor/SKILL.md`.
- **US7 (P3) — QA Cleanup Skill**: No dependencies. Creates new `kiln-cleanup/SKILL.md`.
- **US8 (P3) — Templates**: No dependencies. Creates `issue.md`, modifies `report-issue`, `init.mjs`, `spec-template.md`, `plan-template.md`.
- **US9 (P3) — Issue Archival**: No dependencies. Modifies `report-issue`, `issue-to-prd`, `init.mjs`, `analyze-issues`.

### Parallel Opportunities

All user stories can run in parallel since they modify different files or different sections of shared files. The recommended parallel grouping for agent teams:

- **Agent A (impl-qa)**: US1 + US2 + US3 + US5 (QA agent changes + build enforcement + scoping + friction notes) — T001–T016
- **Agent B (impl-doctor)**: US6 + US7 (kiln-doctor + cleanup) — T017–T024
- **Agent C (impl-templates)**: US8 + US9 (templates + archival) — T025–T036

**Note on shared files**: `qa-engineer.md` is modified by US1, US2, US3, and US5 — these MUST be handled by the same agent to avoid merge conflicts. Similarly, `report-issue/SKILL.md` is modified by US8 and US9 — same agent. `init.mjs` is modified by US8 and US9 — same agent.

---

## Parallel Example: Agent Team Split

```
Agent A (impl-qa): T001–T016
  - T001, T002 in parallel (different files)
  - T003, T004 sequential (same file, different sections)
  - T005, T006 sequential (same file, same section)
  - T007, T008 sequential (same file, related sections)
  - T009–T014 in parallel (six different agent files)
  - T015, T016 sequential (same file)

Agent B (impl-doctor): T017–T024
  - T017 first (manifest changes referenced by later tasks)
  - T018–T023 sequential (same file, building on each other)
  - T024 independent (new file)

Agent C (impl-templates): T025–T036
  - T025, T026 sequential (create template, then update skill to use it)
  - T027 after T025 (init.mjs needs template to exist)
  - T028, T029, T030, T031 in parallel (four different template files)
  - T032, T033 sequential (same file)
  - T034 in parallel with T032 (different file)
  - T035 after T027 (same file, additional change)
  - T036 independent (different file)
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. Complete T001–T004 (QA performance optimizations)
2. **STOP and VALIDATE**: Verify Playwright config changes are correct
3. This alone delivers the primary 50%+ runtime reduction

### Incremental Delivery

1. US1 (Faster QA) → Immediate 50%+ speedup
2. US2 (Latest Build) → Eliminates stale-build false failures
3. US3 (Scoped Reports) → Clearer QA signal for developers
4. US5 (Friction Notes) → Better retrospective data
5. US6 + US7 (Doctor + Cleanup) → Automated maintenance
6. US8 + US9 (Templates + Archival) → Reduced rework, cleaner backlog

### Parallel Team Strategy

With three agents:
1. All agents start immediately (no foundational phase)
2. Agent A: QA changes (T001–T016)
3. Agent B: Doctor + cleanup (T017–T024)
4. Agent C: Templates + archival (T025–T036)
5. All agents complete → T037–T038 (polish/validation)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story
- All changes are markdown/JSON/JS edits — no compilation, no test suite
- Commit after each completed phase
- Phase 6 (US4 - Walkthrough) has no additional tasks — covered by T004 in Phase 3
