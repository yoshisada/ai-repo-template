# Feature Specification: Wheel Workflow Composition

**Feature Branch**: `build/wheel-workflow-composition-20260407`  
**Created**: 2026-04-07  
**Status**: Draft  
**Input**: User description: "Workflow composition - a workflow step type that invokes another workflow inline. PRD at docs/features/2026-04-07-wheel-workflow-composition/PRD.md"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Compose Workflows from Reusable Building Blocks (Priority: P1)

As a workflow author, I want to reference another workflow as a step in my workflow so that I can reuse tested workflows without duplicating their steps. When the engine reaches a `workflow` step, it activates the referenced workflow as a child. The child runs to completion, then the parent advances to its next step.

**Why this priority**: This is the core value proposition. Without the ability to invoke a child workflow, no other composition features matter. Every other user story depends on this working correctly.

**Independent Test**: Create a parent workflow with a `workflow` step referencing an existing child workflow. Run the parent. Verify the child activates, runs to completion, and the parent advances past the workflow step.

**Acceptance Scenarios**:

1. **Given** a parent workflow with a step `{"id": "run-sync", "type": "workflow", "workflow": "shelf-full-sync"}`, **When** the engine cursor reaches `run-sync`, **Then** the child workflow `shelf-full-sync` is activated with its own state file, cursor, and step statuses.
2. **Given** a child workflow that has completed (terminal step done, state archived), **When** the hook detects child completion, **Then** the parent's `workflow` step is marked `done` and the parent cursor advances to the next step.
3. **Given** a parent workflow with a terminal `workflow` step, **When** the child completes, **Then** the parent's workflow step is marked `done` and the parent workflow itself completes (state archived).

---

### User Story 2 - Validation Catches Errors Before Execution (Priority: P1)

As a workflow author, I want the system to validate workflow step references at load time so that I discover broken references, circular dependencies, and excessive nesting before execution begins.

**Why this priority**: Validation errors caught at load time prevent confusing runtime failures. This is critical for a reliable composition system and is equally important as the core execution.

**Independent Test**: Create workflows with known invalid references, circular chains, and deep nesting. Run `workflow_load` on each and verify appropriate error messages without any workflow executing.

**Acceptance Scenarios**:

1. **Given** a workflow with a step referencing `nonexistent-workflow`, **When** `workflow_load` is called, **Then** validation fails with: `ERROR: workflow step '<id>' references missing workflow: nonexistent-workflow`.
2. **Given** workflow A references workflow B and workflow B references workflow A, **When** `workflow_load` is called on A, **Then** validation fails with: `ERROR: circular workflow reference detected: A -> B -> A`.
3. **Given** a chain of workflow steps nested 6 levels deep, **When** `workflow_load` is called on the outermost workflow, **Then** validation fails with: `ERROR: workflow nesting depth exceeds maximum (5)`.
4. **Given** a workflow step references a child workflow that itself has invalid steps, **When** `workflow_load` is called on the parent, **Then** the parent is also invalid.

---

### User Story 3 - Reduce Step Duplication Across Workflows (Priority: P2)

As a workflow maintainer, I want to update a shared workflow in one place and have all workflows that reference it automatically use the updated version, eliminating step duplication.

**Why this priority**: This is the motivating use case (e.g., `report-issue-and-sync` reduced from 12 steps to 3), but it's a consequence of US-1 working correctly rather than a separate implementation concern.

**Independent Test**: Create two parent workflows that both reference the same child workflow. Modify the child workflow. Run both parents and verify they both execute the updated child.

**Acceptance Scenarios**:

1. **Given** `report-issue-and-sync` uses a `workflow` step to invoke `shelf-full-sync`, **When** `shelf-full-sync` is updated with a new step, **Then** running `report-issue-and-sync` executes the updated version.
2. **Given** multiple parent workflows reference the same child, **When** the child is modified, **Then** all parents reflect the change without any edits to the parent workflow files.

---

### User Story 4 - Stopping a Parent Stops Its Children (Priority: P2)

As a workflow operator, I want stopping a parent workflow to also stop any active child workflows, so that no orphaned workflows continue running.

**Why this priority**: Without this, stopping a parent could leave child state files active and confuse the hook system.

**Independent Test**: Start a parent workflow with an active child. Stop the parent via `/wheel-stop`. Verify both the parent and child state files are archived to `history/stopped/`.

**Acceptance Scenarios**:

1. **Given** a parent workflow is running with an active child workflow, **When** the parent is stopped via `/wheel-stop`, **Then** the child state file is also archived to `history/stopped/`.
2. **Given** a child workflow fails or is stopped independently, **When** the hook checks the parent, **Then** the parent's workflow step remains in `working` status and the parent does not advance.

---

### Edge Cases

- What happens when a child workflow has zero steps? Validation should reject it (existing validation already catches "workflow has no steps").
- What happens when a child workflow is deleted between validation and execution? The child activation at runtime should fail gracefully and the parent step remains in `working` status.
- What happens when two workflow steps in the same parent reference the same child workflow? Each invocation creates a separate child state file; they do not conflict.
- What happens when the engine is interrupted mid-child-execution and resumes? The session resume logic should detect the child state file and continue from where it left off.
- What happens when a workflow step has `terminal: true` and the child completes? The parent workflow step is marked done, then the parent workflow completes (archives to history).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A `workflow` step MUST have: `id` (string), `type: "workflow"`, `workflow` (string referencing a workflow by name, resolved to `workflows/<name>.json`).
- **FR-002**: A `workflow` step MUST support optional fields: `terminal` (boolean), `next` (step ID). It MUST NOT support `context_from`, `command`, `instruction`, `output`, `condition`, or fields from other step types.
- **FR-003**: During `workflow_load`, the system MUST validate that every `workflow` step references a workflow file that exists at `workflows/<name>.json`. If missing, fail with: `ERROR: workflow step '<id>' references missing workflow: <name>`.
- **FR-004**: The system MUST detect circular workflow references (direct or transitive) using depth-first traversal with a visited set. Fail with: `ERROR: circular workflow reference detected: <chain>`.
- **FR-005**: The system MUST recursively validate referenced child workflows (call `workflow_load`). If the child is invalid, the parent is invalid.
- **FR-006**: The system MUST cap nesting depth at 5 levels. Exceeding this MUST fail with: `ERROR: workflow nesting depth exceeds maximum (5)`.
- **FR-007**: When the engine cursor reaches a `workflow` step, the system MUST activate the child workflow with its own state file, cursor, step statuses, and ownership fields matching the parent's `owner_session_id` and `owner_agent_id`.
- **FR-008**: The parent workflow's step status MUST transition to `working` when the child is activated. The parent cursor MUST NOT advance until the child completes.
- **FR-009**: When the child workflow's terminal step completes (state archived), the parent's workflow step MUST be marked `done` and the parent cursor MUST advance to the next step (or complete if terminal).
- **FR-010**: If the child workflow fails or is stopped, the parent's workflow step MUST remain in `working` status. The parent MUST NOT advance.
- **FR-011**: The hook system MUST distinguish parent and child state files using existing content-based `owner_session_id` + `owner_agent_id` matching.
- **FR-012**: When a child workflow completes, the hook MUST detect the parent-child relationship, mark the parent's step as `done`, and advance the parent's cursor (fan-in). The parent MUST be updated BEFORE the child is archived.
- **FR-013**: The hook MUST identify parent-child relationships by checking if any other state file has a `workflow` step with status `working` and matching ownership.
- **FR-014**: Workflow steps MUST NOT be kickstartable. During kickstart, if the cursor lands on a `workflow` step, kickstarting MUST stop and leave the step in `pending` status.
- **FR-015**: The child workflow's own kickstart logic MUST apply normally when the child is activated.
- **FR-016**: The child state file MUST include a `parent_workflow` field containing the parent state file path.
- **FR-017**: When the child completes, the `parent_workflow` field MUST be preserved in the archived state for audit trail.
- **FR-018**: If the parent is stopped, any active child state files with matching ownership MUST also be stopped and archived to `history/stopped/`.

### Key Entities

- **Workflow Step (type: "workflow")**: A step definition within a workflow JSON file that references another workflow by name. Key attributes: `id`, `type`, `workflow` (name reference), `terminal`, `next`.
- **Child State File**: A `.wheel/state_*.json` file created when a workflow step activates a child workflow. Contains `parent_workflow` field pointing to the parent state file. Ownership fields match the parent's.
- **Parent-Child Relationship**: Identified at runtime by matching `owner_session_id`/`owner_agent_id` between state files and checking for a `workflow` step in `working` status. The `parent_workflow` field in the child provides a direct reference.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A parent workflow containing a `workflow` step that references a valid child workflow runs to completion without manual intervention — child activates, executes all steps, completes, and parent advances automatically.
- **SC-002**: Circular workflow references (direct and transitive) are detected and rejected at validation time with a clear error message, before any workflow step executes.
- **SC-003**: A workflow using composition (e.g., `report-issue-and-sync` referencing `shelf-full-sync`) has fewer steps than the equivalent inlined version (e.g., 3 steps instead of 12).
- **SC-004**: All existing workflows (those not using the `workflow` step type) continue to pass validation and run correctly with zero modifications.
- **SC-005**: Nesting depth of 5 levels is validated and enforced, with a clear error message for violations.
- **SC-006**: Stopping a parent workflow also stops all active child workflows, leaving no orphaned state files in `.wheel/`.

## Assumptions

- One child workflow per parent step — no fan-out from a single workflow step.
- Child workflows are resolved by name from the `workflows/` directory at activation time, not cached at validation time.
- The child workflow runs in the same session/agent context as the parent — no new agents are spawned.
- Child workflows do not receive parameters or arguments from the parent (independent execution).
- The child's outputs are not accessible to subsequent parent steps via `context_from` (no data passing in v1).
- The existing content-based ownership matching (`owner_session_id` + `owner_agent_id`) is sufficient to route hook events correctly when multiple state files coexist.
- The tech stack remains Bash 5.x + jq with no new dependencies.
