# Tasks: Analyze Issues Skill

**Input**: Design documents from `/specs/analyze-issues/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Not applicable — this is a kiln skill (markdown file), not compiled code. Testing is done by running the skill on a live repo.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Create the skill directory and SKILL.md with frontmatter and skeleton structure

- [X] T001 Create skill directory and SKILL.md with YAML frontmatter (name, description) and all section headings per contracts/interfaces.md in plugin/skills/analyze-issues/SKILL.md

**Checkpoint**: Skill file exists with correct structure, discoverable by plugin system

---

## Phase 2: Foundational (Core Skill Logic)

**Purpose**: Implement prerequisite validation and issue fetching — blocks all user story functionality

- [X] T002 [US1] Write Step 1 (Validate Prerequisites) — check `gh` CLI availability and authentication, exit with clear error if unavailable, in plugin/skills/analyze-issues/SKILL.md
- [X] T003 [US1] Write Step 2 (Fetch Open Issues) — `gh issue list --state open --json number,title,body,labels,createdAt,updatedAt --limit 50`, handle 0 issues case, in plugin/skills/analyze-issues/SKILL.md
- [X] T004 [US2] Write Step 3 (Filter Issues) — skip issues with `analyzed` label unless `--reanalyze` flag is in `$ARGUMENTS`, handle "no new issues" case, in plugin/skills/analyze-issues/SKILL.md

**Checkpoint**: Skill can fetch and filter issues. Prerequisites validated.

---

## Phase 3: User Story 1 - Triage Accumulated Issues (Priority: P1) — MVP

**Goal**: Categorize all open issues and label them with category + analyzed tags

**Independent Test**: Run `/analyze-issues` on a repo with open issues; verify each gets a `category:*` and `analyzed` label

- [X] T005 [US1] Write Step 4 (Analyze Each Issue) — categorize each issue into one of: skills, agents, hooks, templates, scaffold, workflow, other. Provide categorization guidelines based on issue title and body content. Assess actionability (concrete improvements, bug reports, process changes = actionable; informational summaries, resolved items, stale = not actionable). In plugin/skills/analyze-issues/SKILL.md
- [X] T006 [US1] [US6] Write Step 7 (Create Labels) — create labels with `gh label create "<name>" --color "<hex>" --force` for all category labels and `analyzed` label. Apply `category:<name>` and `analyzed` labels to each issue via `gh issue edit <number> --add-label`. Include label colors from contracts/interfaces.md. In plugin/skills/analyze-issues/SKILL.md
- [X] T007 [US1] Write Step 5 (Present Results) — display issues grouped by category, show which are flagged as actionable with explanations, show which are suggested for closure with reasons. In plugin/skills/analyze-issues/SKILL.md

**Checkpoint**: Running `/analyze-issues` categorizes and labels all issues. Core triage flow works.

---

## Phase 4: User Story 3 - Flag Actionable Issues (Priority: P1)

**Goal**: Flag issues with actionable feedback and explain WHY each is worth acting on

**Independent Test**: Run skill on issues with bug reports and improvement suggestions; verify they are flagged with specific explanations

Note: Actionability assessment is integrated into T005 (Step 4). This phase ensures the presentation in Step 5 (T007) properly highlights flagged issues with clear explanations. Already covered by T005 and T007.

**Checkpoint**: Flagged issues show clear, specific reasons for actionability

---

## Phase 5: User Story 4 - Suggest and Close Issues (Priority: P2)

**Goal**: Suggest closing informational/resolved/stale issues with user confirmation

**Independent Test**: Run skill on a mix of issues; verify closure suggestions appear with reasons and issues close only after confirmation

- [X] T008 [US4] Write Step 6 (Handle Closures) — present closure suggestions with reasons, prompt user for individual or batch confirmation, close confirmed issues via `gh issue close <number> --comment "Closed by /analyze-issues: <reason>"`. In plugin/skills/analyze-issues/SKILL.md

**Checkpoint**: Users can review and confirm issue closures individually or in batch

---

## Phase 6: User Story 5 - Create Backlog Items (Priority: P2)

**Goal**: Offer to create `.kiln/issues/` backlog items from selected flagged issues

**Independent Test**: Flag issues, select some for backlog creation, verify `.kiln/issues/` entries are created

- [X] T009 [US5] Write Step 8 (Offer Backlog Creation) — present flagged actionable issues, let user select which to convert, invoke `/report-issue #<number>` for each selected issue. In plugin/skills/analyze-issues/SKILL.md

**Checkpoint**: Users can convert flagged issues to backlog items via `/report-issue`

---

## Phase 7: User Story 2 - Skip Already-Analyzed Issues (Priority: P1)

Note: Already implemented in T004 (Step 3 — Filter Issues). The `--reanalyze` flag handling and `analyzed` label filtering are part of the foundational phase.

**Checkpoint**: Second run skips analyzed issues; `--reanalyze` forces re-processing

---

## Phase 8: User Story 6 - Category Filtering in GitHub UI (Priority: P3)

Note: Already implemented in T006 (Step 7 — Create Labels). Category labels with `category:` prefix enable GitHub UI filtering.

**Checkpoint**: Issues have `category:*` labels filterable in GitHub UI

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Summary report and edge case handling

- [ ] T010 Write Step 9 (Summary Report) — display table with total issues analyzed, categories assigned, issues flagged as actionable, issues suggested for closure, issues closed, and backlog items created. In plugin/skills/analyze-issues/SKILL.md
- [ ] T011 Write Rules section — document constraints: 50 issue limit, no issue body/title modification, idempotent behavior, error handling for label creation failures, title-only issues. In plugin/skills/analyze-issues/SKILL.md

**Checkpoint**: Skill is complete with summary report and documented rules

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup (T001)
- **User Story Phases (3-8)**: All depend on Foundational phase (T002-T004)
- **Polish (Phase 9)**: Depends on all user story phases being complete

### Within the Skill

All tasks write to the same file (`plugin/skills/analyze-issues/SKILL.md`), so they MUST be executed sequentially in order: T001 through T011.

### Execution Order

```
T001 → T002 → T003 → T004 → T005 → T006 → T007 → T008 → T009 → T010 → T011
```

No parallel opportunities exist because all tasks modify the same single file.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001-T003: Setup + prerequisite validation + issue fetching
2. Complete T004-T007: Filtering + categorization + labeling + presentation
3. **STOP and VALIDATE**: Run `/analyze-issues` on the repo, verify categorization and labeling works

### Incremental Delivery

1. T001-T007 → Core triage works (categorize, label, present) — MVP
2. T008 → Closure suggestions with confirmation
3. T009 → Backlog item creation
4. T010-T011 → Summary report and rules

---

## Notes

- All tasks write to the single file `plugin/skills/analyze-issues/SKILL.md`
- No parallel execution possible (single file)
- User Stories 2, 3, 6 are inherently covered by tasks in other phases (filtering, categorization, labeling)
- Total tasks: 11
- Commit after completing each phase
