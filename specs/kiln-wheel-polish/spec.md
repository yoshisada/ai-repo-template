# Feature Specification: Kiln & Wheel Polish

**Feature Branch**: `build/kiln-wheel-polish-20260404`  
**Created**: 2026-04-04  
**Status**: Draft  
**Input**: PRD at docs/features/2026-04-04-kiln-wheel-polish/PRD.md — 21 FRs, 3 NFRs across 4 backlog items

## User Scenarios & Testing

### User Story 1 - Branch Step Control Flow (Priority: P1)

As a workflow author, I want branch steps to only execute the matched path so that mutually exclusive cleanup logic (success vs failure) doesn't collide.

**Why this priority**: This is the highest-severity issue. Without proper control flow, branch steps are unusable for any realistic conditional logic. Every workflow with a branch currently runs both paths.

**Independent Test**: Create a workflow with a branch step that routes to either a "success" or "failure" path using the `next` field. Run the workflow with a condition that selects one path. Verify only the selected path executes and the other is skipped.

**Acceptance Scenarios**:

1. **Given** a step with `"next": "cleanup-success"`, **When** the step completes, **Then** the engine jumps to the step with id `cleanup-success` instead of cursor+1.
2. **Given** a step with no `next` field and it is not the last step, **When** the step completes, **Then** the engine advances to cursor+1 (backwards compatible).
3. **Given** a step with no `next` field and it is the last step in a branch path, **When** the step completes, **Then** the workflow ends (cursor set to total steps).
4. **Given** a workflow where a `next` field references a nonexistent step ID, **When** the workflow is loaded, **Then** validation rejects it with an error.
5. **Given** a branch step that routes to a target step with `"next": "final-step"`, **When** the target step completes, **Then** the engine follows its `next` field to `final-step`.

---

### User Story 2 - Automatic Terminal Cleanup (Priority: P2)

As a workflow author, I want cleanup to happen automatically when a workflow reaches a terminal step so that I don't need boilerplate cleanup steps in every workflow.

**Why this priority**: Removes boilerplate from every workflow and eliminates "no state file" errors. Lower priority than US1 because US1 is a correctness bug while US2 is a convenience improvement.

**Independent Test**: Create a workflow with a step marked `"terminal": true`. Run the workflow to that step. Verify state.json is archived to the correct history directory and removed, with no manual cleanup step needed.

**Acceptance Scenarios**:

1. **Given** a step with `"terminal": true` and id containing "success", **When** the step completes, **Then** state.json is archived to `.wheel/history/success/` and removed.
2. **Given** a step with `"terminal": true` and id containing "failure", **When** the step completes, **Then** state.json is archived to `.wheel/history/failure/` and removed.
3. **Given** a step with `"terminal": true` and id not containing "success" or "failure", **When** the step completes, **Then** state.json is archived to `.wheel/history/success/` (default) and removed.
4. **Given** a workflow with no `terminal` fields on any step, **When** the workflow runs to completion, **Then** it behaves identically to today (backwards compatible).
5. **Given** no `.wheel/state.json` file exists, **When** the hook fires, **Then** it exits silently (no error, no-op).

---

### User Story 3 - /todo Skill (Priority: P3)

As a developer using kiln, I want a quick `/todo` command to jot down tasks without going through the full spec pipeline.

**Why this priority**: Pure additive feature. Does not fix a bug or unblock other functionality. Nice-to-have for developer quality of life.

**Independent Test**: Run `/todo buy milk` to create an item, `/todo` to list it, `/todo done 1` to mark it complete, `/todo clear` to remove completed items. Verify `.kiln/todos.md` reflects each operation.

**Acceptance Scenarios**:

1. **Given** `.kiln/todos.md` does not exist, **When** `/todo buy milk` is run, **Then** the file is created with `- [ ] buy milk (2026-04-04)`.
2. **Given** `.kiln/todos.md` has 3 items, **When** `/todo` is run with no arguments, **Then** all items are listed with their index numbers.
3. **Given** `.kiln/todos.md` has item #2 unchecked, **When** `/todo done 2` is run, **Then** item #2 changes to `- [x]` with a completion date.
4. **Given** `.kiln/todos.md` has 2 completed and 1 open item, **When** `/todo clear` is run, **Then** only the open item remains.

---

### User Story 4 - UX Evaluator Path Fix (Priority: P4)

As a QA engineer, I want screenshots saved to the correct directory so that other tools can find and clean them up.

**Why this priority**: Low severity bug — only manifests during QA runs and doesn't block any workflow. Easy fix.

**Independent Test**: Run the UX evaluator agent and verify screenshots land in `${REPO_ROOT}/.kiln/qa/screenshots/` (not nested `.kiln/qa/.kiln/qa/screenshots/`).

**Acceptance Scenarios**:

1. **Given** the UX evaluator agent runs from any working directory, **When** it creates the screenshot output directory, **Then** it resolves to `${REPO_ROOT}/.kiln/qa/screenshots/`.
2. **Given** a nested `.kiln/qa/.kiln/` directory exists inside `.kiln/qa/`, **When** `/kiln-cleanup` is run, **Then** the nested `.kiln/` tree is detected and removed.

---

### Edge Cases

- What happens when a `next` field creates a cycle (step A -> step B -> step A)? The engine follows the chain without cycle detection — workflows are expected to be DAGs or use `terminal: true` to break cycles. This mirrors the existing loop step behavior which has a `max_iterations` guard but branches do not.
- What happens when two steps both have `"next"` pointing to the same target? Both will jump to the target. The second to arrive finds the step already done and the engine advances past it.
- What happens if `terminal: true` is on a step that also has a `next` field? `terminal` takes precedence — the workflow archives and ends. `next` is ignored.
- What happens if `.wheel/history/` directories don't exist when archiving? They are created with `mkdir -p`.

## Requirements

### Functional Requirements

**Wheel: Branch Subroutine Support**

- **FR-001**: Steps MAY include a `next` field containing a step ID. After the step completes, the engine jumps to that step instead of advancing cursor+1.
- **FR-002**: If a step has no `next` field and is not the last step, the engine advances to cursor+1 (backwards compatible).
- **FR-003**: If a step has no `next` field and is the last step in a branch path, the workflow ends (cursor set to total steps).
- **FR-004**: `dispatch_command` in `plugin-wheel/lib/dispatch.sh` must check for `next` field before defaulting to cursor+1.
- **FR-005**: `dispatch_agent` in `plugin-wheel/lib/dispatch.sh` must check for `next` field before defaulting to cursor+1.
- **FR-006**: `workflow_get_step_index` (or equivalent) in `plugin-wheel/lib/workflow.sh` must resolve a step ID to its array index for `next` field targeting.
- **FR-007**: Validation must reject workflows where a `next` field references a nonexistent step ID.

**Wheel: Automatic Cleanup at Terminal Steps**

- **FR-008**: Steps MAY include a `terminal: true` field indicating the workflow should end after this step.
- **FR-009**: When a terminal step completes, the hook archives `state.json` to `.wheel/history/success/` or `.wheel/history/failure/` based on the step ID containing "success" or "failure" (default: success).
- **FR-010**: After archiving, the hook removes `.wheel/state.json`.
- **FR-011**: The "no state file" error in the hook should be downgraded to a silent no-op (workflow not active, nothing to do).
- **FR-012**: Existing workflows that use explicit cleanup steps must continue to work (terminal field is optional).

**Kiln: /todo Skill**

- **FR-013**: Create a `/todo` skill at `plugin-kiln/skills/todo/` with a `prompt.md`.
- **FR-014**: `/todo` without arguments lists all open TODOs from `.kiln/todos.md`.
- **FR-015**: `/todo <text>` appends a new `- [ ] <text>` item with a date stamp to `.kiln/todos.md`.
- **FR-016**: `/todo done <N>` marks the Nth item as `- [x]` with a completion date.
- **FR-017**: `/todo clear` removes all completed items from the file.
- **FR-018**: The file format is plain markdown — one checkbox item per line, compatible with any markdown viewer.

**UX Evaluator Path Fix**

- **FR-019**: The UX evaluator agent must use absolute paths (relative to repo root) when creating the screenshot output directory.
- **FR-020**: The screenshot directory must always resolve to `${REPO_ROOT}/.kiln/qa/screenshots/` regardless of the agent's current working directory.
- **FR-021**: `/kiln-cleanup` should detect and remove nested `.kiln/` trees inside `.kiln/qa/` as a safety net.

### Key Entities

- **Step (workflow JSON)**: Extended with optional `next` (string, step ID) and `terminal` (boolean) fields.
- **State (state.json)**: No schema changes — cursor advancement logic changes only.
- **Todo item (todos.md)**: `- [ ] text (date)` or `- [x] text (date) [done: date]` format.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A workflow with a branch step and two mutually exclusive paths only executes the matched path — verified by checking that the skipped path's step status remains "skipped" in state.json.
- **SC-002**: Workflows with `terminal: true` steps auto-archive state and remove state.json without any manual cleanup steps in the workflow.
- **SC-003**: `/todo buy milk` creates an entry, `/todo` lists it, `/todo done 1` marks it complete, `/todo clear` removes completed items — all verifiable by reading `.kiln/todos.md`.
- **SC-004**: UX evaluator screenshots appear in `.kiln/qa/screenshots/` (not nested) after a QA run.
- **SC-005**: All existing workflows and hooks continue to work without modification (NFR-001 backwards compatibility).

## Assumptions

- The wheel engine's `dispatch_command` and `dispatch_agent` functions are the only two places that advance the cursor after step completion (excluding parallel fan-in and loop re-dispatch).
- `workflow_get_step_index` already exists and correctly resolves step IDs to indices — it just needs to be called from the `next` field resolution path.
- The UX evaluator's path bug is in the agent markdown instructions, not in code — the fix is updating the agent definition to use absolute paths.
- `.kiln/todos.md` is a new file that does not conflict with any existing kiln artifact.
- The `next` field validation can be added to the existing `workflow_validate_references` function alongside branch target validation.
