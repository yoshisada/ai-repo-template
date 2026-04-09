# Interface Contracts: Wheel Team Primitives

All functions are Bash. Parameters are positional. Output is stdout unless noted. Exit codes: 0 = success, 1 = error, 2 = workflow complete.

---

## dispatch.sh — New Functions

### dispatch_team_create

Handles a `team-create` step. On `stop` hook when pending: injects instruction telling the orchestrator to call TeamCreate. On `post_tool_use`: detects TeamCreate completion, records team in state, marks step done, advances cursor.

```bash
# Params:
#   $1 = step_json (string) — the team-create step JSON
#   $2 = hook_type (string) — stop|post_tool_use
#   $3 = hook_input_json (string) — raw JSON from hook stdin
#   $4 = state_file (string) — state file path
#   $5 = step_index (integer) — step index
#
# Output (stdout): JSON hook response
# Exit: 0
dispatch_team_create()
```

### dispatch_teammate

Handles a `teammate` step. On `stop` hook when pending: reads `loop_from` if present (parses JSON array, distributes with max_agents cap), writes context.json and assignment.json, injects instruction to spawn Agent(s) with run_in_background. Marks step done after all spawns are initiated (fire-and-forget). Advances cursor.

```bash
# Params:
#   $1 = step_json (string) — the teammate step JSON
#   $2 = hook_type (string) — stop|post_tool_use
#   $3 = hook_input_json (string) — raw JSON from hook stdin
#   $4 = state_file (string) — state file path
#   $5 = step_index (integer) — step index
#
# Output (stdout): JSON hook response
# Exit: 0
dispatch_teammate()
```

### dispatch_team_wait

Handles a `team-wait` step. On `stop` hook when pending: marks working. On each `stop` invocation while working: checks teammate statuses via state file. If all done/failed: writes summary, copies outputs if collect_to set, marks done, advances cursor. If not all done: returns block with status.

```bash
# Params:
#   $1 = step_json (string) — the team-wait step JSON
#   $2 = hook_type (string) — stop|post_tool_use
#   $3 = hook_input_json (string) — raw JSON from hook stdin
#   $4 = state_file (string) — state file path
#   $5 = step_index (integer) — step index
#
# Output (stdout): JSON hook response
# Exit: 0
dispatch_team_wait()
```

### dispatch_team_delete

Handles a `team-delete` step. On `stop` hook when pending: injects instruction to send shutdown to all teammates and call TeamDelete. On `post_tool_use`: detects TeamDelete completion, cleans up state, marks done, advances cursor.

```bash
# Params:
#   $1 = step_json (string) — the team-delete step JSON
#   $2 = hook_type (string) — stop|post_tool_use
#   $3 = hook_input_json (string) — raw JSON from hook stdin
#   $4 = state_file (string) — state file path
#   $5 = step_index (integer) — step index
#
# Output (stdout): JSON hook response
# Exit: 0
dispatch_team_delete()
```

---

## dispatch.sh — Modified Functions

### dispatch_step (modified)

Add four new case branches to the existing case/esac:

```bash
case "$step_type" in
    # ... existing types ...
    team-create)
      dispatch_team_create "$step_json" "$hook_type" "$hook_input_json" "$state_file" "$step_index"
      ;;
    teammate)
      dispatch_teammate "$step_json" "$hook_type" "$hook_input_json" "$state_file" "$step_index"
      ;;
    team-wait)
      dispatch_team_wait "$step_json" "$hook_type" "$hook_input_json" "$state_file" "$step_index"
      ;;
    team-delete)
      dispatch_team_delete "$step_json" "$hook_type" "$hook_input_json" "$state_file" "$step_index"
      ;;
    # ... existing default ...
esac
```

---

## state.sh — New Functions

### state_set_team

Records a team in the workflow state under `teams.{step_id}`.

```bash
# Params:
#   $1 = state_file (string) — state file path
#   $2 = step_id (string) — the team-create step ID (used as key)
#   $3 = team_name (string) — the Claude Code team name
#
# Output: none (updates state file)
# Exit: 0 on success, 1 on failure
state_set_team()
```

### state_get_team

Reads team metadata from state.

```bash
# Params:
#   $1 = state_json (string) — state JSON
#   $2 = step_id (string) — the team-create step ID
#
# Output (stdout): JSON object with team_name, teammates
# Exit: 0 if found, 1 if not found
state_get_team()
```

### state_add_teammate

Adds a teammate entry to a team's teammates map.

```bash
# Params:
#   $1 = state_file (string) — state file path
#   $2 = team_step_id (string) — the team-create step ID
#   $3 = agent_name (string) — teammate agent name
#   $4 = task_id (string) — TaskCreate task ID
#   $5 = agent_id (string) — Claude Code agent ID
#   $6 = output_dir (string) — output directory path
#   $7 = assign_json (string) — assignment payload JSON (may be empty)
#
# Output: none (updates state file)
# Exit: 0 on success, 1 on failure
state_add_teammate()
```

### state_update_teammate_status

Updates a teammate's status in the state file.

```bash
# Params:
#   $1 = state_file (string) — state file path
#   $2 = team_step_id (string) — the team-create step ID
#   $3 = agent_name (string) — teammate agent name
#   $4 = new_status (string) — pending|running|completed|failed
#
# Output: none (updates state file)
# Exit: 0 on success, 1 on failure
state_update_teammate_status()
```

### state_get_teammates

Returns all teammate entries for a team.

```bash
# Params:
#   $1 = state_json (string) — state JSON
#   $2 = team_step_id (string) — the team-create step ID
#
# Output (stdout): JSON object of teammates map
# Exit: 0 if found, 1 if not found
state_get_teammates()
```

### state_remove_team

Removes a team from the state file (called by team-delete).

```bash
# Params:
#   $1 = state_file (string) — state file path
#   $2 = step_id (string) — the team-create step ID
#
# Output: none (updates state file)
# Exit: 0 on success, 1 on failure
state_remove_team()
```

---

## context.sh — New Functions

### context_write_teammate_files

Writes context.json and assignment.json for a teammate before spawning.

```bash
# Params:
#   $1 = output_dir (string) — teammate output directory
#   $2 = state_json (string) — parent workflow state
#   $3 = workflow_json (string) — parent workflow definition
#   $4 = context_from_json (string) — JSON array of step IDs (may be "[]")
#   $5 = assign_json (string) — assignment payload JSON (may be "{}")
#
# Output: none (writes files to output_dir)
# Exit: 0 on success, 1 on failure
context_write_teammate_files()
```

### context_resolve_synthetic

Resolves synthetic step IDs `_context` and `_assignment` for sub-workflows. Called by `context_build()` when it encounters these special IDs.

```bash
# Params:
#   $1 = synthetic_id (string) — "_context" or "_assignment"
#   $2 = state_json (string) — sub-workflow state JSON
#
# Output (stdout): file contents of the referenced file
# Exit: 0 if found, 1 if not found
context_resolve_synthetic()
```

---

## engine.sh — Modified Functions

### engine_kickstart (modified)

Add team types to the case statement:

```bash
case "$step_type" in
    # ... existing types ...
    team-create|teammate|team-delete)
      # These inject instructions — set to pending for stop hook
      state_set_step_status "$state_file" "$cursor" "pending"
      ;;
    team-wait)
      # Not kickstartable — needs polling
      ;;
esac
```

### engine_handle_hook (modified)

Add team types to the `post_tool_use` handler, alongside existing agent and workflow type handling:

```bash
# In the post_tool_use case, after existing agent/workflow checks:
elif [[ "$step_type" == "team-create" || "$step_type" == "teammate" || "$step_type" == "team-delete" ]]; then
  dispatch_step "$current_step" "post_tool_use" "$hook_input_json" "$state_file" "$cursor"
  return $?
elif [[ "$step_type" == "team-wait" ]]; then
  dispatch_team_wait "$current_step" "post_tool_use" "$hook_input_json" "$state_file" "$cursor"
  return $?
fi
```

---

## workflow.sh — Modified Functions

### workflow_validate_references (modified)

Add validation for team step references:

```bash
# After existing branch target validation:
# Validate teammate/team-wait/team-delete `team` field references valid team-create step
# Validate teammate `loop_from` field references existing step ID
```

---

## post-tool-use.sh — Modified Sections

### Cascade stop for teams (in deactivate.sh handler)

After stopping parent workflows and cascade-stopping child workflows, also clean up team agents:

```bash
# For each stopped state file that had a teams key:
#   Read teams.{step-id}.teammates
#   For each teammate with status "running":
#     Send shutdown via SendMessage (instruction in agent cleanup)
#   Clean up team output directories if requested
```

---

## File Ownership Summary

| File | Owner | Changes |
|------|-------|---------|
| `plugin-wheel/lib/dispatch.sh` | impl-step-types | 4 new functions + 4 case branches |
| `plugin-wheel/lib/state.sh` | impl-engine | 6 new functions |
| `plugin-wheel/lib/engine.sh` | impl-engine | 2 modified functions (kickstart + handle_hook) |
| `plugin-wheel/lib/context.sh` | impl-engine | 2 new functions |
| `plugin-wheel/lib/workflow.sh` | impl-engine | 1 modified function (validate_references) |
| `plugin-wheel/hooks/post-tool-use.sh` | impl-engine | 1 modified section (deactivate handler) |
