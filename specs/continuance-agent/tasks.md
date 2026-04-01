# Tasks: Continuance Agent (/next)

**Input**: Design documents from `specs/continuance-agent/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Not applicable — this is a markdown-based plugin feature with no compiled code. Testing is via manual pipeline runs.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Plugin skills**: `plugin/skills/<name>/SKILL.md`
- **Plugin agents**: `plugin/agents/<name>.md`
- **Existing skills**: `plugin/skills/build-prd/skill.md`, `plugin/skills/resume/SKILL.md`

---

## Phase 1: Setup

**Purpose**: Create the directory structure for the new skill

- [X] T001 Create `plugin/skills/next/` directory for the /next skill

---

## Phase 2: Foundational — Create Agent Definition

**Purpose**: Define the continuance agent's role, analysis methodology, and output format. This is referenced by the skill and documents the agent's capabilities.

**Checkpoint**: Agent definition exists and is discoverable by the plugin system

- [X] T002 Create continuance agent definition at `plugin/agents/continuance.md` with frontmatter (name: "continuance", description, model: sonnet), role description, analysis methodology (6-step: gather sources, classify findings, assign priorities, map to commands, deduplicate, produce output), priority ordering rules (blockers > incomplete > QA/audit > backlog > improvements), command mapping table, and output format specifications per `contracts/interfaces.md`

---

## Phase 3: User Story 1 — Post-Build Pipeline Guidance (Priority: P1) + User Story 3 — Actionable Command Mapping (Priority: P1)

**Goal**: Create the /next skill with full project state analysis, prioritized recommendations, and concrete command mapping. US1 and US3 are combined because command mapping is integral to every recommendation — they cannot be separated.

**Independent Test**: Run `/next` in a project with incomplete tasks, blockers, and QA failures. Verify all items appear in the terminal summary with correct priorities and valid kiln commands.

### Implementation

- [ ] T003 [US1] Create `/next` skill definition at `plugin/skills/next/SKILL.md` with frontmatter per `contracts/interfaces.md` (name: "next", description). Include `$ARGUMENTS` parsing for `--brief` flag.
- [ ] T004 [US1] Add Step 1 to `plugin/skills/next/SKILL.md`: Read project context — VERSION file, current branch via `git branch --show-current`, constitution at `.specify/memory/constitution.md`
- [ ] T005 [US1] Add Step 2 to `plugin/skills/next/SKILL.md`: Gather state from all local sources via bash commands — `specs/*/tasks.md` (grep for `[ ]` incomplete items), `specs/*/blockers.md`, `specs/*/retrospective.md`, `.kiln/qa/` reports (QA-REPORT.md, QA-PASS-REPORT.md, UX-REPORT.md), `.kiln/issues/` open items, `specs/*/spec.md` cross-referenced with tasks for unimplemented FRs
- [ ] T006 [US1] Add Step 3 to `plugin/skills/next/SKILL.md`: Gather state from GitHub sources — `gh issue list --state open --json number,title,labels` and `gh pr list --state open --json number,title,comments`, wrapped in `command -v gh` and `gh auth status` availability checks per FR-014. Note skipped sources when unavailable.
- [ ] T007 [US1] Add Step 4 to `plugin/skills/next/SKILL.md`: Classification and prioritization logic — classify each finding into categories (blocker/incomplete-work/qa-audit-gap/backlog/improvement), assign priority levels (critical/high/medium/low), map each finding to a specific kiln command per the mapping table in `contracts/interfaces.md` (incomplete task → `/implement`, failing test → `/fix`, QA finding → `/fix` or `/qa-pass`, audit gap → `/implement`, unimplemented FR → `/specify` or `/implement`, backlog → `/fix` or `/specify`, retrospective action → `/specify` or `/fix`)
- [ ] T008 [US1] Add Step 5 to `plugin/skills/next/SKILL.md`: Terminal summary output — max 15 items grouped by priority (Critical/High/Medium/Low), each with description + command + source reference, per the terminal output format in `contracts/interfaces.md`. Include project name, branch, version header. If `--brief`, show only top 5 and stop (no report, no backlog updates).

**Checkpoint**: `/next` produces correct prioritized output from local and GitHub sources with valid kiln commands. `--brief` flag works.

---

## Phase 4: User Story 4 — Persistent Report (Priority: P2)

**Goal**: Save detailed analysis to `.kiln/logs/` for later reference and sharing.

**Independent Test**: Run `/next` and verify a report file is created at `.kiln/logs/next-<timestamp>.md` with full analysis. Run `/next --brief` and verify no file is created.

### Implementation

- [ ] T009 [US4] Add Step 6 to `plugin/skills/next/SKILL.md`: Persistent report generation — create `.kiln/logs/` directory if it doesn't exist, generate timestamp (`date +%Y-%m-%d-%H%M%S`), write detailed report to `.kiln/logs/next-<YYYY-MM-DD-HHmmss>.md` per the report format in `contracts/interfaces.md` (header with timestamp/branch/version, project state summary, sources analyzed checklist, full recommendations table, backlog updates section). Skip if `--brief` flag is set.

**Checkpoint**: Report file is created with correct name and content. `--brief` skips report creation.

---

## Phase 5: User Story 5 — Automatic Backlog Gap Discovery (Priority: P2)

**Goal**: Auto-create `.kiln/issues/` entries for untracked gaps with deduplication.

**Independent Test**: Run `/next` on a project with QA failures not yet tracked in `.kiln/issues/`. Verify new issue files are created with `[auto:continuance]` tag and existing issues are not duplicated.

### Implementation

- [ ] T010 [US5] Add Step 7 to `plugin/skills/next/SKILL.md`: Backlog issue creation — for each discovered gap, read existing `.kiln/issues/` filenames and first-line titles, compare against the gap description for title similarity. If no match found, create `.kiln/issues/<YYYY-MM-DD>-<slug>.md` with title, description, source reference, and `[auto:continuance]` tag. Ensure `.kiln/issues/` directory exists before writing. Log created and skipped (already tracked) issues in the terminal output and persistent report. Skip if `--brief` flag is set.

**Checkpoint**: New issues are created for untracked gaps. Existing issues are not duplicated. `--brief` skips issue creation.

---

## Phase 6: User Story 2 — Session Start State Recovery (Priority: P1) — /resume Deprecation

**Goal**: Replace `/resume` with `/next` as the session-start command. Keep `/resume` as a deprecated alias.

**Independent Test**: Run `/resume` and verify it prints a deprecation notice then produces the full `/next` output.

### Implementation

- [ ] T011 [US2] Modify `plugin/skills/resume/SKILL.md` to replace the existing content with a deprecated alias: frontmatter updated per `contracts/interfaces.md` (name: "resume", description: "Deprecated — use /next instead"), deprecation notice printed first ("Note: `/resume` has been replaced by `/next`. Please use `/next` going forward."), then the full `/next` skill logic executed inline

**Checkpoint**: `/resume` prints deprecation notice and produces identical output to `/next`.

---

## Phase 7: User Story 1 (continued) — Build-prd Integration (FR-006, FR-011)

**Goal**: Add the continuance agent as the final step of `/build-prd`, running after the retrospective.

**Independent Test**: Run `/build-prd` and verify the continuance analysis appears as the final step before PR creation, with output included in the terminal summary.

### Implementation

- [ ] T012 [US1] Modify `plugin/skills/build-prd/skill.md` to add continuance as the final pipeline step: after the retrospective section completes and before PR creation, add instructions for the team lead to invoke `/next` (not `--brief`) to produce full analysis. Include the continuance output in the terminal summary. If `/next` fails, log a warning and proceed with PR creation (advisory, non-blocking).

**Checkpoint**: `/build-prd` includes continuance as final step. Pipeline still completes if continuance fails.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and documentation

- [ ] T013 Verify all four files exist and have correct frontmatter: `plugin/agents/continuance.md`, `plugin/skills/next/SKILL.md`, `plugin/skills/resume/SKILL.md`, `plugin/skills/build-prd/skill.md`
- [ ] T014 Verify `/next` skill output format matches `contracts/interfaces.md` terminal summary format exactly
- [ ] T015 Verify `/next` skill persistent report format matches `contracts/interfaces.md` report format exactly

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Agent Definition)**: Depends on Phase 1
- **Phase 3 (US1+US3: /next skill)**: Depends on Phase 2 (agent definition informs skill logic)
- **Phase 4 (US4: Persistent Report)**: Depends on Phase 3 (extends the /next skill)
- **Phase 5 (US5: Backlog Discovery)**: Depends on Phase 3 (extends the /next skill)
- **Phase 6 (US2: /resume Deprecation)**: Depends on Phase 3 (/next must exist first)
- **Phase 7 (Build-prd Integration)**: Depends on Phase 3 (/next must exist first)
- **Phase 8 (Polish)**: Depends on all previous phases

### User Story Dependencies

- **US1+US3 (/next skill)**: Can start after Phase 2 — no dependencies on other stories
- **US4 (Report)**: Depends on US1+US3 — extends the same file
- **US5 (Backlog)**: Depends on US1+US3 — extends the same file
- **US2 (/resume)**: Depends on US1+US3 — needs /next to exist
- **Build-prd integration**: Depends on US1+US3 — needs /next to exist

### Within Each Phase

- Tasks within a phase are sequential (they modify the same file)
- Phases 4, 5, 6, and 7 can run in parallel after Phase 3 completes (different files)

### Parallel Opportunities

- **After Phase 3 completes**: T009 (US4), T010 (US5), T011 (US2), T012 (US1 build-prd) can all run in parallel since they modify different files
- **Phase 8**: All polish tasks marked [P] can run in parallel

---

## Parallel Example: After Phase 3

```
# These can run simultaneously after Phase 3:
Agent A: T009 — Add persistent report to plugin/skills/next/SKILL.md
Agent B: T011 — Modify plugin/skills/resume/SKILL.md  
Agent C: T012 — Modify plugin/skills/build-prd/skill.md
```

Note: T009 and T010 modify the same file (SKILL.md) so they must be sequential within the /next skill work.

---

## Implementation Strategy

### MVP First (Phase 1-3)

1. Complete Phase 1: Setup (directory creation)
2. Complete Phase 2: Agent definition
3. Complete Phase 3: Core /next skill with analysis + prioritization + command mapping
4. **STOP and VALIDATE**: Test `/next` independently — does it produce correct prioritized output?

### Incremental Delivery

1. Setup + Agent + Core Skill → `/next` works standalone (MVP)
2. Add Persistent Report → reports saved to `.kiln/logs/`
3. Add Backlog Discovery → auto-creates `.kiln/issues/` entries
4. Add /resume Deprecation → backward compatibility preserved
5. Add Build-prd Integration → pipeline closes the loop
6. Polish → verify all contracts and formats

---

## Notes

- All tasks modify markdown files — no compiled code
- Tasks T003-T008 build up a single file (`plugin/skills/next/SKILL.md`) incrementally
- T009 and T010 also extend `plugin/skills/next/SKILL.md`
- T011 modifies `plugin/skills/resume/SKILL.md`
- T012 modifies `plugin/skills/build-prd/skill.md`
- Total: 15 tasks across 8 phases
- Commit after each phase completion
