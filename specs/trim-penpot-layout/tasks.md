# Tasks: Trim Penpot Layout & Auto-Flows

**Input**: Design documents from `/specs/trim-penpot-layout/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: No test tasks — this feature modifies agent instruction text in workflow JSON and skill Markdown files, not runtime code.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: No project initialization needed — all files already exist. This phase is empty.

**Checkpoint**: Ready to proceed to foundational changes.

---

## Phase 2: Foundational — Positioning Rules for All Workflows (FR-001, FR-003, FR-004)

**Purpose**: Add frame positioning instructions to every agent step that creates Penpot elements. This is the blocking prerequisite for all other changes — without spacing, nothing else matters.

**CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T001 Add positioning rules to push-to-penpot agent instruction in plugin-trim/workflows/trim-push.json (Contract 1: prepend POSITIONING RULES block to the "instruction" field of step id="push-to-penpot")
- [ ] T002 [P] Add positioning rules to pull-design agent instruction in plugin-trim/workflows/trim-pull.json (Contract 1: prepend POSITIONING RULES block to the "instruction" field of step id="pull-design")
- [ ] T003 [P] Add positioning rules to generate-design agent instruction in plugin-trim/workflows/trim-design.json (Contract 1: prepend POSITIONING RULES block to the "instruction" field of step id="generate-design")
- [ ] T004 [P] Add positioning rules to generate-redesign agent instruction in plugin-trim/workflows/trim-redesign.json (Contract 1: prepend POSITIONING RULES block to the "instruction" field of step id="generate-redesign")
- [ ] T005 [P] Add positioning rules to apply-edit agent instruction in plugin-trim/workflows/trim-edit.json (Contract 1: prepend POSITIONING RULES block to the "instruction" field of step id="apply-edit")
- [ ] T006 [P] Add positioning rules to sync-components agent instruction in plugin-trim/workflows/trim-library-sync.json (Contract 1: prepend POSITIONING RULES block to the "instruction" field of step id="sync-components")

**Checkpoint**: All Penpot-creating agent steps now include explicit positioning rules. Frames will have 40px minimum spacing.

---

## Phase 3: User Story 1 — No Overlapping Frames + Page Separation (Priority: P1) MVP

**Goal**: Ensure all trim commands produce non-overlapping frames and page-level designs land on separate Penpot pages.

**Independent Test**: Run `/trim-push` on a multi-page project. Verify no frames overlap and each app page has its own Penpot page.

### Implementation for User Story 1

- [ ] T007 [US1] Add page separation rules to push-to-penpot agent instruction in plugin-trim/workflows/trim-push.json (Contract 2: append PAGE SEPARATION RULES block to step id="push-to-penpot" instruction)
- [ ] T008 [P] [US1] Add page separation rules to generate-design agent instruction in plugin-trim/workflows/trim-design.json (Contract 2: append PAGE SEPARATION RULES block to step id="generate-design" instruction)

**Checkpoint**: Push and design commands now create separate Penpot pages per route and maintain frame spacing. User Story 1 is complete.

---

## Phase 4: User Story 2 — Separate Penpot Pages Per App Page (Priority: P1)

**Goal**: This is already handled by Phase 3 (US1 T007 and T008 implement page separation). This phase is intentionally empty — the page separation rules in Contract 2 cover both the spacing and the per-route page creation.

**Checkpoint**: Covered by Phase 3.

---

## Phase 5: User Story 3 — Components Page with Bento Grid (Priority: P2)

**Goal**: Push and design commands create a "Components" page with categorized bento grid layout.

**Independent Test**: Run `/trim-push` on a project with components in multiple directories. Verify a "Components" page exists in Penpot with grouped, labeled sections.

### Implementation for User Story 3

- [ ] T009 [US3] Add Components page bento grid rules to push-to-penpot agent instruction in plugin-trim/workflows/trim-push.json (Contract 3: append COMPONENTS PAGE RULES block to step id="push-to-penpot" instruction)
- [ ] T010 [P] [US3] Add Components page bento grid rules to generate-design agent instruction in plugin-trim/workflows/trim-design.json (Contract 3: append COMPONENTS PAGE RULES block to step id="generate-design" instruction)
- [ ] T011 [US3] Update trim-push skill report in plugin-trim/skills/trim-push/SKILL.md (Contract 7: add Components Page line to report template)
- [ ] T012 [P] [US3] Update trim-design skill report in plugin-trim/skills/trim-design/SKILL.md (Contract 7: add Components Page line to report template)

**Checkpoint**: Components page with bento grid is created by push and design commands. User Story 3 is complete.

---

## Phase 6: User Story 4 — Auto-Flow Discovery (Priority: P2)

**Goal**: Push, pull, and design commands auto-discover user flows and write them to `.trim/flows.json`.

**Independent Test**: Run `/trim-push` on a Next.js project with 5+ routes. Check `.trim/flows.json` for auto-discovered flows.

### Implementation for User Story 4

- [ ] T013 [US4] Add discover-flows agent step to plugin-trim/workflows/trim-push.json (Contract 4: insert new step between push-to-penpot and update-mappings with flow discovery instruction for codebase scanning)
- [ ] T014 [P] [US4] Add discover-flows agent step to plugin-trim/workflows/trim-pull.json (Contract 5: insert new step between pull-design and update-mappings with flow discovery instruction for Penpot page analysis)
- [ ] T015 [P] [US4] Add discover-flows agent step to plugin-trim/workflows/trim-design.json (Contract 6: insert new step between generate-design and update-mappings with flow discovery instruction for PRD parsing)
- [ ] T016 [US4] Update trim-push skill report in plugin-trim/skills/trim-push/SKILL.md (Contract 7: add Flows Discovered line to report template)
- [ ] T017 [P] [US4] Update trim-pull skill report in plugin-trim/skills/trim-pull/SKILL.md (Contract 7: add Flows Discovered line to report template)
- [ ] T018 [P] [US4] Update trim-design skill report in plugin-trim/skills/trim-design/SKILL.md (Contract 7: add Flows Discovered line to report template)

**Checkpoint**: All three commands auto-discover flows and merge them into .trim/flows.json. User Story 4 is complete.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and cleanup.

- [ ] T019 Verify all 6 workflow JSON files are valid JSON after edits (run `jq . plugin-trim/workflows/*.json`)
- [ ] T020 Review all modified agent instructions for internal consistency (positioning rules don't conflict with Components page rules, flow discovery steps have correct context_from references)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Empty — no setup needed
- **Foundational (Phase 2)**: No dependencies — positioning rules can start immediately
- **User Story 1 (Phase 3)**: Depends on Phase 2 (positioning must be in place before page separation)
- **User Story 3 (Phase 5)**: Depends on Phase 2 (positioning must be in place). Can run in parallel with Phase 3.
- **User Story 4 (Phase 6)**: No dependency on other stories — new steps are independent of positioning/layout changes. Can run in parallel with Phases 3 and 5.
- **Polish (Phase 7)**: Depends on all previous phases

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Phase 2 foundational positioning. No dependencies on other stories.
- **User Story 3 (P2)**: Depends on Phase 2 foundational positioning. No dependencies on other stories.
- **User Story 4 (P2)**: Can start after Phase 2. No dependencies on other stories.

### Within Each User Story

- Workflow JSON changes before skill SKILL.md updates
- All [P] tasks within a story can run in parallel

### Parallel Opportunities

- T002-T006 can all run in parallel (different workflow files)
- T007 and T008 can run in parallel (different files)
- T009 and T010 can run in parallel (different files)
- T013, T014, T015 can run in parallel (different files)
- T016, T017, T018 can run in parallel (different files)
- Phases 3, 5, and 6 can run in parallel once Phase 2 is done

---

## Parallel Example: Phase 2 (Foundational)

```bash
# All positioning rule tasks can run in parallel (different files):
Task T002: "Add positioning rules to trim-pull.json"
Task T003: "Add positioning rules to trim-design.json"
Task T004: "Add positioning rules to trim-redesign.json"
Task T005: "Add positioning rules to trim-edit.json"
Task T006: "Add positioning rules to trim-library-sync.json"
# T001 runs first or in parallel (trim-push.json)
```

## Parallel Example: Phase 6 (Auto-Flow Discovery)

```bash
# All flow discovery steps can run in parallel (different files):
Task T013: "Add discover-flows step to trim-push.json"
Task T014: "Add discover-flows step to trim-pull.json"
Task T015: "Add discover-flows step to trim-design.json"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational positioning rules (T001-T006)
2. Complete Phase 3: Page separation (T007-T008)
3. **SELF-VALIDATE**: Run `/trim-push` on a test project and verify no overlapping frames + separate pages
4. This alone makes the Penpot output usable

### Incremental Delivery

1. Phase 2 (Positioning) → Frames stop overlapping
2. Phase 3 (Page Separation) → Each route gets its own page (MVP!)
3. Phase 5 (Components Page) → Organized component library
4. Phase 6 (Flow Discovery) → Automatic flow tracking
5. Phase 7 (Polish) → Validation pass

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- All changes are text edits to existing JSON and Markdown files
- No new files created (except new JSON step entries within existing arrays)
- Commit after each phase
- User Story 2 (separate pages) is merged with User Story 1 because the same Contract 2 covers both
