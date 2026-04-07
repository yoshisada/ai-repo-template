# Research: Wheel Workflow Composition

## R-001: How existing step types are dispatched

**Decision**: Follow the existing pattern in `dispatch_step()` — add a `workflow)` case to the case statement that calls `dispatch_workflow()`.

**Rationale**: Every step type (agent, command, parallel, approval, branch, loop) follows this exact pattern. The dispatch function receives `step_json`, `hook_type`, `hook_input_json`, `state_file`, and `step_index`. Adding a new case is the expected extension point.

**Alternatives considered**: Creating a separate hook script for workflow steps — rejected because the existing architecture routes all step types through the same dispatch mechanism.

## R-002: How child state files coexist with parent state files

**Decision**: Use the existing content-based ownership matching in `guard.sh`. Both parent and child state files will have the same `owner_session_id` and `owner_agent_id`. The hook's `resolve_state_file()` returns the first match — this creates a routing challenge since both files match.

**Rationale**: The child must have matching ownership so the same agent/session's hook events route to it. The fan-in detection must happen BEFORE the child is archived, because after archiving the child state file is moved to `history/` and the parent would be unreachable.

**Key insight**: When a child workflow is active, `resolve_state_file()` will match the child's state file (since it iterates `.wheel/state_*.json` and the child was created more recently). This is actually correct behavior — the child is the "active" workflow for this agent. When the child completes, the fan-in logic in `dispatch_workflow()` or `handle_terminal_step()` must find and update the parent before archiving the child.

**Alternatives considered**: Using a different ownership scheme for children — rejected because it would require changes to the guard system and all hook scripts.

## R-003: Fan-in mechanism (child completion → parent advancement)

**Decision**: Modify `handle_terminal_step()` in dispatch.sh. After the terminal step archives, check if the completed state file has a `parent_workflow` field. If so, read the parent state file, find the workflow step in `working` status, mark it `done`, and advance the parent cursor. This must happen BEFORE the child is archived (moved out of `.wheel/`).

**Rationale**: The `handle_terminal_step()` function is already called by every dispatch handler when a step is terminal. Adding parent advancement here centralizes the fan-in logic in one place rather than duplicating it across dispatch_agent, dispatch_command, etc.

**Order of operations**:
1. Child's terminal step completes
2. `handle_terminal_step()` is called for the child
3. Before archiving, check child's `parent_workflow` field
4. If parent exists: mark parent's workflow step as `done`, advance parent cursor
5. Archive child state file to `history/success/`
6. Parent's next step can now proceed via normal hook dispatch

**Alternatives considered**: Adding fan-in to the PostToolUse hook script — rejected because `handle_terminal_step()` is the existing convergence point for all step completions.

## R-004: Circular reference detection algorithm

**Decision**: Depth-first traversal with a visited set during `workflow_load`. New function `workflow_validate_workflow_refs()` that:
1. Collects all `workflow` steps from the current workflow
2. For each, checks if the referenced workflow name is in the visited set (circular)
3. If not, loads the child workflow and recurses with the visited set + current name
4. Tracks depth and fails at >5

**Rationale**: DFS with visited set is the standard cycle detection algorithm. Running it at validation time (inside `workflow_load`) catches all circular references before execution, satisfying the PRD requirement that detection is never at runtime.

**Alternatives considered**: Topological sort — rejected as more complex and not needed since we only need to detect cycles, not compute an ordering.

## R-005: How to activate a child workflow from a workflow step

**Decision**: In `dispatch_workflow()`, directly call `state_init()` to create the child state file, then call `engine_kickstart()` on the child. This mirrors what the PostToolUse hook does when intercepting `activate.sh`, but without the shell command interception.

**Rationale**: The existing activation path (`activate.sh` → hook intercept → `state_init` → `engine_kickstart`) requires a Bash tool call. For workflow steps, the engine is already running inside a hook, so we can call the state/kickstart functions directly.

**Key detail**: The child state file must include:
- `parent_workflow`: path to parent state file
- `owner_session_id`: same as parent
- `owner_agent_id`: same as parent
- Its own cursor, step statuses, etc.

## R-006: Cascading stop for parent→child

**Decision**: Modify the `deactivate.sh` interception block in `post-tool-use.sh`. When stopping a workflow, after finding the target state file, check if any other state files have a `parent_workflow` pointing to the stopped file. Archive those children too.

**Rationale**: The existing deactivate logic already iterates state files. Adding a child-detection pass is a natural extension.

**Alternatives considered**: Having each workflow step track its child state file path — rejected because the parent doesn't need to know which specific file the child uses; the `parent_workflow` field in the child is sufficient for reverse lookups.
