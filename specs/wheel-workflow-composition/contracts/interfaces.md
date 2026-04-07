# Interface Contracts: Wheel Workflow Composition

## New Functions

### workflow.sh

#### `workflow_validate_workflow_refs`
```bash
# FR-003/FR-004/FR-005/FR-006: Validate workflow step references, detect circular
# references, enforce nesting depth, and recursively validate child workflows.
#
# Params:
#   $1 = workflow_json (string) — validated workflow JSON
#   $2 = visited (string) — comma-separated list of workflow names already in the call chain (for cycle detection)
#   $3 = depth (integer) — current nesting depth (starts at 0)
#
# Output (stderr): error messages if validation fails
# Exit: 0 if all workflow references valid, 1 if any validation fails
workflow_validate_workflow_refs() {
```

### dispatch.sh

#### `dispatch_workflow`
```bash
# FR-007/FR-008/FR-009/FR-010/FR-012/FR-013: Handle a workflow step — activate child
# workflow, detect child completion, perform fan-in to parent.
#
# Params:
#   $1 = step_json (string) — the workflow step JSON
#   $2 = hook_type (string) — stop|post_tool_use
#   $3 = hook_input_json (string) — raw JSON from hook stdin
#   $4 = state_file (string) — parent state file path
#   $5 = step_index (integer) — parent step index
#
# Output (stdout): JSON hook response
# Exit: 0 on success, 1 on error
dispatch_workflow() {
```

## Modified Functions

### workflow.sh

#### `workflow_load` (MODIFIED)
```bash
# FR-012: Load and validate a workflow JSON file
# MODIFICATION: After existing validation, call workflow_validate_workflow_refs()
# to validate workflow step references, detect circular refs, and enforce nesting depth.
#
# Params: $1 = workflow file path (UNCHANGED)
# Output (stdout): validated workflow JSON (UNCHANGED)
# Exit: 0 on valid, 1 on invalid (UNCHANGED — new validation errors added)
workflow_load() {
```

### dispatch.sh

#### `dispatch_step` (MODIFIED)
```bash
# FR-003/019/024/025/026: Dispatch a step based on its type
# MODIFICATION: Add `workflow)` case to the case statement that calls dispatch_workflow().
#
# Params: UNCHANGED ($1=step_json, $2=hook_type, $3=hook_input_json, $4=state_file, $5=step_index)
# Output: UNCHANGED (JSON hook response)
# Exit: UNCHANGED (0 on success, 1 on error)
dispatch_step() {
```

#### `handle_terminal_step` (MODIFIED)
```bash
# FR-008/FR-009/FR-010: Handle terminal step cleanup.
# MODIFICATION: Before archiving, check if the state file has a `parent_workflow` field.
# If so, find the parent state file, mark the parent's workflow step as `done`,
# and advance the parent cursor. Then archive as normal.
#
# Params: UNCHANGED ($1=state_file, $2=step_json)
# Output: UNCHANGED
# Exit: UNCHANGED (0 on success, 1 on archive failure)
handle_terminal_step() {
```

### state.sh

#### `state_init` (MODIFIED)
```bash
# FR-011: Initialize a new state file from a workflow definition.
# MODIFICATION: Add optional $6 parameter for parent_workflow path. When provided,
# include `parent_workflow` field in the state JSON.
#
# Params:
#   $1 = state_file (string) — full path to the state file to create
#   $2 = workflow_json (string) — validated workflow JSON
#   $3 = session_id (string) — owner session ID
#   $4 = agent_id (string) — owner agent ID (may be empty)
#   $5 = workflow_file (string, optional) — path to workflow file
#   $6 = parent_workflow (string, optional) — path to parent state file (NEW)
#
# Output: UNCHANGED
# Exit: UNCHANGED
state_init() {
```

### engine.sh

#### `engine_kickstart` (MODIFIED)
```bash
# Kickstart the workflow by dispatching the first step inline.
# MODIFICATION: Add `workflow` to the case statement — when cursor lands on a
# workflow step, do NOT dispatch (leave in pending for hook to handle).
#
# Params: UNCHANGED ($1=state file path)
# Output: UNCHANGED
# Exit: UNCHANGED
engine_kickstart() {
```

### hooks/post-tool-use.sh (MODIFIED)

The hook script is not a function but a shell script. Modifications:

1. **Fan-in logic**: After `handle_terminal_step()` archives a child state file, the parent is already updated (handled inside `handle_terminal_step`). No additional hook logic needed for fan-in — it happens inside the dispatch layer.

2. **Cascading stop** (deactivate.sh interception): After stopping a workflow and before the `exit 0`, scan remaining state files for any that have `parent_workflow` matching the stopped file's path. Archive those children to `history/stopped/` as well.

3. **Child state file routing**: The existing `resolve_state_file()` in guard.sh already handles multiple state files with the same ownership by returning the first match. When a child is active, it will typically be matched. When the child completes and is archived, the parent becomes the match again. No changes needed to guard.sh.

## Unchanged Functions

The following functions are NOT modified:
- `state_read()`, `state_write()`, `state_get_cursor()`, `state_set_cursor()`
- `state_get_step_status()`, `state_set_step_status()`
- `state_get_agent_status()`, `state_set_agent_status()`
- `state_set_step_output()`, `state_get_step_output()`
- `state_append_command_log()`, `state_get_command_log()`
- `resolve_state_file()` (guard.sh)
- `lock_acquire()`, `lock_release()`, `lock_clean_all()` (lock.sh)
- `context_build()`, `context_capture_output()`, `context_subagent_start()` (context.sh)
- `dispatch_agent()`, `dispatch_command()`, `dispatch_parallel()`, `dispatch_approval()`, `dispatch_branch()`, `dispatch_loop()`
- `workflow_get_steps()`, `workflow_get_step()`, `workflow_get_step_by_id()`, `workflow_get_step_index()`, `workflow_step_count()`, `workflow_validate_references()`, `workflow_validate_unique_ids()`
- `engine_init()`, `engine_current_step()`, `engine_handle_hook()`
- `advance_past_skipped()`, `resolve_next_index()`
