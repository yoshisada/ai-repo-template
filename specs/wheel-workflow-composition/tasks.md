# Tasks: Wheel Workflow Composition

**Input**: Design documents from `specs/wheel-workflow-composition/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: No test framework for this shell-based plugin. Validation is done via e2e workflow execution in Phase 7.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: No new files or dependencies needed. This phase ensures the spec artifacts are committed before code changes begin.

- [ ] T001 Commit spec.md, plan.md, research.md, data-model.md, quickstart.md, contracts/interfaces.md, and tasks.md to git before any code changes

---

## Phase 2: Foundational — Validation (workflow.sh)

**Purpose**: Add workflow step reference validation, circular detection, and nesting depth enforcement. These MUST be in place before any dispatch or state changes, because invalid workflows must be rejected at load time.

**CRITICAL**: No dispatch/state/hook work can begin until validation is complete.

- [ ] T002 [US2] Add `workflow_validate_workflow_refs()` function to `plugin-wheel/lib/workflow.sh` — FR-003: validate that every `workflow` step references an existing `workflows/<name>.json` file. FR-004: detect circular references via DFS with visited set. FR-005: recursively validate child workflows. FR-006: cap nesting depth at 5 levels. Signature per contracts/interfaces.md.
- [ ] T003 [US2] Modify `workflow_load()` in `plugin-wheel/lib/workflow.sh` — after existing validation passes, call `workflow_validate_workflow_refs()` with the validated JSON, empty visited string, and depth 0. If it fails, return 1.

**Checkpoint**: `workflow_load` now rejects workflows with missing refs, circular refs, and excessive nesting depth.

---

## Phase 3: User Story 1 — Compose Workflows (Priority: P1) MVP

**Goal**: A parent workflow with a `workflow` step activates a child workflow, the child runs to completion, and the parent advances.

**Independent Test**: Create a parent workflow with a `workflow` step referencing a child. Run the parent. Verify child activates, runs, completes, and parent advances.

### Implementation for User Story 1

- [ ] T004 [P] [US1] Modify `state_init()` in `plugin-wheel/lib/state.sh` — add optional `$6` parameter `parent_workflow`. When provided, include `"parent_workflow": "<path>"` in the state JSON object. FR-016.
- [ ] T005 [P] [US1] Add `dispatch_workflow()` function to `plugin-wheel/lib/dispatch.sh` — FR-007/FR-008: on `stop` hook type, if step status is `pending`, mark step `working`, load child workflow file from `workflows/<name>.json`, call `state_init()` with parent's `owner_session_id`, `owner_agent_id`, and `parent_workflow` set to the parent state file path. Call `engine_kickstart()` on the child state file. Return `{"decision": "block", "reason": "Workflow step activated child: <name>"}`. On `post_tool_use` hook type, delegate to existing PostToolUse handling (no special action needed — fan-in is in handle_terminal_step). Signature per contracts/interfaces.md.
- [ ] T006 [US1] Modify `dispatch_step()` in `plugin-wheel/lib/dispatch.sh` — add `workflow)` case to the case statement that calls `dispatch_workflow()` with the same parameters as other dispatch functions. FR-001/FR-002.
- [ ] T007 [US1] Modify `handle_terminal_step()` in `plugin-wheel/lib/dispatch.sh` — FR-009/FR-012: before archiving, check if the state file has a `parent_workflow` field (via `jq -r '.parent_workflow // empty'`). If parent exists and the parent state file exists: read parent state, find the step index where type is `workflow` and status is `working`, mark that step `done`, resolve next index and advance parent cursor (using `resolve_next_index` and `advance_past_skipped`). If the parent's workflow step is terminal, recursively call `handle_terminal_step` on the parent. FR-010: if child fails/stops, do NOT update parent (parent step stays `working`).
- [ ] T008 [US1] Modify `engine_kickstart()` in `plugin-wheel/lib/engine.sh` — FR-014: add `workflow` to the case statement. When cursor lands on a `workflow` step, do nothing (return 0 without dispatching). The step stays in `pending` for the hook to handle. FR-015: child workflow kickstart happens inside `dispatch_workflow()`.

**Checkpoint**: Parent workflow with a workflow step runs end-to-end. Child activates, executes, completes, and parent advances automatically.

---

## Phase 4: User Story 2 — Validation Catches Errors (Priority: P1)

**Goal**: Broken references, circular dependencies, and excessive nesting are caught at validation time.

**Independent Test**: Call `workflow_load` on workflows with known invalid references, circular chains, and deep nesting. Verify appropriate error messages.

**Note**: The validation functions were implemented in Phase 2. This phase validates they work correctly by testing edge cases during e2e validation in Phase 7.

(No additional implementation tasks — Phase 2 covers the code. E2E validation in Phase 7 covers testing.)

---

## Phase 5: User Story 3 — Reduce Duplication (Priority: P2)

**Goal**: Multiple parent workflows reference the same child; updating the child automatically propagates changes.

**Independent Test**: Two parent workflows reference the same child. Modify child. Both parents execute the updated version.

**Note**: This is an emergent property of US1 (child workflows are loaded at activation time, not cached). No additional implementation needed. Validated in Phase 7.

---

## Phase 6: User Story 4 — Stopping Parent Stops Children (Priority: P2)

**Goal**: Stopping a parent via `/wheel-stop` cascades to active child workflows.

**Independent Test**: Start parent with active child. Stop parent. Verify both are archived to `history/stopped/`.

### Implementation for User Story 4

- [ ] T009 [US4] Modify deactivate.sh interception in `plugin-wheel/hooks/post-tool-use.sh` — FR-018: after stopping a workflow (archiving its state file), scan remaining `.wheel/state_*.json` files for any with a `parent_workflow` field matching the stopped file's path. Archive those child state files to `.wheel/history/stopped/` as well.

**Checkpoint**: Stopping a parent cascades to children. No orphaned child state files remain.

---

## Phase 7: E2E Validation

**Purpose**: Verify the full lifecycle end-to-end with real workflow files.

- [ ] T010 Create test child workflow at `workflows/test-child.json` with 2 command steps (echo commands, terminal on last step)
- [ ] T011 Create test parent workflow at `workflows/test-parent.json` with: setup command step, workflow step referencing `test-child`, teardown command step (terminal)
- [ ] T012 Run parent workflow via `/wheel-run test-parent` and verify: child activates, child steps execute, child completes, parent advances past workflow step, parent completes
- [ ] T013 Test circular reference detection: create two workflows that reference each other, verify `workflow_load` rejects with circular error
- [ ] T014 Test missing reference: create workflow referencing nonexistent child, verify `workflow_load` rejects with missing workflow error
- [ ] T015 Test nesting depth: create chain of 6+ nested workflows, verify `workflow_load` rejects with depth exceeded error
- [ ] T016 Test parent stop cascade: start parent with active child, stop parent, verify both archived to `history/stopped/`
- [ ] T017 Clean up test workflow files (remove `test-child.json` and `test-parent.json` if they were only for testing)

**Checkpoint**: All FRs validated end-to-end.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final cleanup and documentation.

- [ ] T018 [P] Verify all existing workflows still pass `workflow_load` validation (no regressions)
- [ ] T019 [P] Write agent friction notes to `specs/wheel-workflow-composition/agent-notes/` documenting implementation experience

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Validation)**: Depends on Phase 1 — BLOCKS all implementation phases
- **Phase 3 (US1 - Compose)**: Depends on Phase 2
- **Phase 4 (US2 - Validation)**: Code done in Phase 2, validated in Phase 7
- **Phase 5 (US3 - Duplication)**: Emergent from US1, validated in Phase 7
- **Phase 6 (US4 - Stop cascade)**: Depends on Phase 3 (needs dispatch_workflow in place)
- **Phase 7 (E2E)**: Depends on Phases 2, 3, 6
- **Phase 8 (Polish)**: Depends on Phase 7

### User Story Dependencies

- **US1 (Compose)**: Depends on Phase 2 (validation). Core feature.
- **US2 (Validation)**: Implemented in Phase 2. Independent of other stories.
- **US3 (Duplication)**: Emergent from US1. No additional code.
- **US4 (Stop cascade)**: Depends on US1 (needs workflow step dispatch). Independent otherwise.

### Within Phase 3 (US1)

- T004 (state.sh) and T005 (dispatch_workflow) can run in parallel [P]
- T006 (dispatch_step case) depends on T005
- T007 (handle_terminal_step fan-in) depends on T004 and T005
- T008 (engine_kickstart) can run in parallel with T004/T005 [P]

### Parallel Opportunities

```
Phase 2: T002, T003 — sequential (T003 depends on T002)
Phase 3: T004 ∥ T005 ∥ T008, then T006 → T007
Phase 6: T009 — single task
Phase 7: T010-T017 — sequential (each builds on previous)
Phase 8: T018 ∥ T019
```

---

## Parallel Example: Phase 3 (US1)

```bash
# Launch these in parallel (different files, no dependencies):
Task T004: "Modify state_init() in plugin-wheel/lib/state.sh"
Task T005: "Add dispatch_workflow() in plugin-wheel/lib/dispatch.sh"
Task T008: "Modify engine_kickstart() in plugin-wheel/lib/engine.sh"

# Then sequentially:
Task T006: "Modify dispatch_step() in plugin-wheel/lib/dispatch.sh" (depends on T005)
Task T007: "Modify handle_terminal_step() in plugin-wheel/lib/dispatch.sh" (depends on T004, T005)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Commit artifacts
2. Complete Phase 2: Validation in workflow.sh
3. Complete Phase 3: Core composition (state, dispatch, engine)
4. **SELF-VALIDATE**: Create test workflows, run parent, verify child executes and parent advances
5. This alone delivers the core value — workflows can invoke other workflows

### Incremental Delivery

1. Phase 1 + 2 → Validation catches broken/circular/deep workflow refs
2. Phase 3 → Core composition works end-to-end (MVP!)
3. Phase 6 → Stop cascade ensures no orphaned children
4. Phase 7 → Full e2e validation of all scenarios
5. Phase 8 → Polish and regression check

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- No test framework — validation is via manual e2e workflow execution
- All modifications follow existing patterns in the wheel engine
- Commit after each phase completion
- Total tasks: 19
- Tasks per story: US1=5, US2=2 (Phase 2), US3=0, US4=1
- Key parallel opportunity: T004 ∥ T005 ∥ T008 in Phase 3
