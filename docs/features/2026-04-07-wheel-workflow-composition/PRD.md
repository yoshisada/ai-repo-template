# Feature PRD: Wheel Workflow Composition

**Status**: Draft
**Date**: 2026-04-07

## Parent Product

[Kiln Plugin](../../PRD.md) — spec-first development workflow plugin for Claude Code. This feature extends the **wheel** subsystem's workflow engine to support calling one workflow from another.

## Feature Overview

A `workflow` step type that invokes another workflow inline. When the engine encounters a `workflow` step, it activates the referenced workflow as a child. When the child completes, the parent workflow advances to its next step. This turns every workflow into a reusable building block — complex pipelines can be composed from smaller, tested workflows instead of duplicating steps.

## Problem / Motivation

Workflows currently duplicate steps when they need shared functionality. For example, `report-issue-and-sync` needs all 10 steps from `shelf-full-sync` copied inline, resulting in 12 steps instead of 3. Any change to `shelf-full-sync` must be manually propagated to every workflow that embeds it. This is the same problem as copy-pasting functions instead of calling them.

Composition solves this: a workflow step says "run this other workflow" and the engine handles the rest.

## Goals

- Enable workflows to invoke other workflows as steps
- Eliminate step duplication across workflows that share common sequences
- Keep the execution model simple — child runs to completion, then parent advances
- No changes to existing workflows or step types

## Non-Goals

- Recursive workflows (A calls B calls A) — detect and reject at validation time
- Parallel workflow invocation (run two child workflows simultaneously)
- Conditional workflow selection at runtime (use a branch step before a workflow step instead)
- Shared state between parent and child workflows (child gets its own state file, parent doesn't read child's intermediate outputs)
- Passing parameters or arguments to child workflows
- Workflow step type in v1 does not support `context_from` passing data into the child — the child runs independently

## Target Users

- **Workflow authors** who want to compose pipelines from reusable building blocks
- **Agents** creating workflows dynamically via `/wheel-create` that reference existing workflows
- **Plugin developers** maintaining shared workflow libraries

## Core User Stories

### US-1: Compose Workflows
As a workflow author, I want to reference another workflow as a step so that I can reuse tested workflows without duplicating their steps.

**Example**:
```json
{
  "id": "full-sync",
  "type": "workflow",
  "workflow": "shelf-full-sync"
}
```

### US-2: Reduce Duplication
As a workflow maintainer, I want to update `shelf-full-sync` in one place and have all workflows that reference it automatically use the updated version.

### US-3: Build Complex Pipelines
As an agent, I want to compose multi-workflow pipelines (e.g., report issue → sync → update dashboard) by chaining workflow steps, each referencing a smaller tested workflow.

## Functional Requirements

### Workflow Step Schema

- **FR-001**: A `workflow` step must have: `id` (string), `type: "workflow"`, `workflow` (string — name of the workflow to invoke). The `workflow` field references a workflow by name, resolved to `workflows/<name>.json`.
- **FR-002**: Optional fields: `terminal` (boolean), `next` (step ID). A workflow step does NOT support `context_from`, `command`, `instruction`, `output`, `condition`, or other fields from other step types.

### Validation

- **FR-003**: During `workflow_load`, validate that every `workflow` step references a workflow file that exists at `workflows/<name>.json`. If the file doesn't exist, fail validation with: `ERROR: workflow step '<id>' references missing workflow: <name>`.
- **FR-004**: Detect circular references. If workflow A contains a step that invokes workflow B, and workflow B contains a step that invokes workflow A (directly or transitively), fail validation with: `ERROR: circular workflow reference detected: A -> B -> A`. Use depth-first traversal with a visited set.
- **FR-005**: Validate the referenced child workflow itself (call `workflow_load` recursively). If the child is invalid, the parent is invalid.
- **FR-006**: Cap nesting depth at 5 levels. If a workflow step would exceed this depth, fail validation with: `ERROR: workflow nesting depth exceeds maximum (5)`.

### Execution

- **FR-007**: When the engine cursor reaches a `workflow` step, activate the child workflow. The child gets its own state file with its own cursor, step statuses, and ownership fields. The child's `owner_session_id` and `owner_agent_id` match the parent's.
- **FR-008**: The parent workflow's step status transitions to `working` when the child is activated. The parent's cursor does NOT advance — it stays on the workflow step until the child completes.
- **FR-009**: When the child workflow's terminal step completes (child state archived to `history/success/`), the parent's workflow step is marked `done` and the parent cursor advances to the next step (or completes if the workflow step is terminal).
- **FR-010**: If the child workflow fails or is stopped, the parent's workflow step remains in `working` status. The parent does not advance. Stopping the parent also stops any active child.

### Hook Integration

- **FR-011**: The PostToolUse hook must be able to distinguish parent and child state files. Both exist simultaneously in `.wheel/` while the child is running. Use the existing `owner_session_id` + `owner_agent_id` content-based matching to route events to the correct state file.
- **FR-012**: When a child workflow completes (terminal step done), the hook must detect that this child is referenced by a parent workflow step, mark the parent's step as `done`, and advance the parent's cursor. This is the "fan-in" from child to parent.
- **FR-013**: The hook identifies the parent-child relationship by checking: does any other state file in `.wheel/` have a step of type `workflow` with status `working` and the same `owner_session_id`/`owner_agent_id`? If so, that's the parent.

### Kickstart Integration

- **FR-014**: Workflow steps are NOT kickstartable — they require hook interception to manage the child lifecycle. During kickstart, if the cursor lands on a `workflow` step, stop kickstarting and leave the step in `pending` status for the hook to handle.
- **FR-015**: However, the child workflow's own kickstart logic applies normally. When the child is activated, its command/loop/branch steps kickstart as usual.

### State Management

- **FR-016**: The child state file includes a `parent_workflow` field containing the parent state file path. This enables the fan-in detection in FR-012/FR-013.
- **FR-017**: When the child completes, its state file is archived to `history/success/` as normal. The `parent_workflow` field is preserved in the archived state for audit trail.
- **FR-018**: If the parent is stopped (via `/wheel-stop`), any active child state files with matching ownership are also stopped and archived to `history/stopped/`.

## Absolute Musts

1. **Tech stack**: Bash 5.x + jq (no new dependencies)
2. Existing workflows must continue to work without modification
3. Circular reference detection at validation time — never at runtime
4. Child completion must reliably trigger parent advancement

## Tech Stack

Inherited from wheel plugin — no additions needed:
- Bash 5.x (engine libs)
- jq (JSON parsing)
- Existing hook infrastructure

## Impact on Existing Features

- **engine.sh**: Add routing for `workflow` step type — activate child workflow instead of dispatching to command/agent/branch/loop
- **dispatch.sh**: New `dispatch_workflow()` function to handle child activation and completion detection
- **workflow.sh**: Extended validation for `workflow` step references, circular detection, nesting depth
- **guard.sh**: No changes — content-based ownership already handles multiple state files
- **post-tool-use.sh**: Add fan-in logic — detect child completion, find parent, mark parent step done
- **Existing step types**: No changes — command, agent, branch, loop are unaffected
- **Existing workflows**: No changes — they don't use the `workflow` type and validation is additive

## Success Metrics

1. `report-issue-and-sync` reduced from 12 steps to 3 using a `workflow` step referencing `shelf-full-sync`
2. Child workflow runs to completion and parent advances automatically — no manual intervention
3. All 6 existing workflows continue to pass validation and run correctly
4. Circular reference detected and rejected at validation time, not runtime

## Risks / Unknowns

- **Two state files simultaneously**: The hook must correctly route events when both parent and child state files exist in `.wheel/`. Mitigated by existing content-based ownership matching — each event is routed to the state file whose `owner_session_id`/`owner_agent_id` matches the hook input.
- **Child completion detection timing**: The hook archives the child state file to `history/success/` — at that point, it needs to find and update the parent. If the archive happens before the parent lookup, the parent won't be found. Mitigation: update parent BEFORE archiving child.
- **Nesting depth performance**: Deeply nested workflows (5 levels) mean 5 simultaneous state files. This is bounded and manageable, but validation should warn at depth 3+.

## Assumptions

- One child workflow per parent step (no fan-out from a single workflow step)
- Child workflows are always resolved by name from `workflows/` directory at activation time (not cached at validation time)
- The child workflow runs in the same session/agent context as the parent — no new agents spawned

## Open Questions

- Should the child's outputs be accessible to subsequent parent steps via `context_from`? (Leaning no for v1 — keep it simple, add data passing in v2 if needed.)
- Should `/wheel-status` show the parent-child relationship? (Leaning yes — indent child under parent.)
