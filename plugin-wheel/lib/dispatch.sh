#!/usr/bin/env bash
# dispatch.sh — Step type dispatcher
# FR-003/019/024/025/026: Routes to the correct handler based on step type

# Advance cursor past any "skipped" steps, returning the next actionable index.
# Params: $1 = state file path, $2 = starting index, $3 = workflow JSON
# Output (stdout): the next non-skipped step index (may be >= total steps if all remaining are skipped)
# Exit: 0
advance_past_skipped() {
  local state_file="$1"
  local idx="$2"
  local workflow_json="$3"
  local total_steps
  total_steps=$(printf '%s\n' "$workflow_json" | jq '.steps | length')
  local state
  state=$(state_read "$state_file") || return 1
  while [[ "$idx" -lt "$total_steps" ]]; do
    local step_st
    step_st=$(printf '%s\n' "$state" | jq -r --argjson i "$idx" '.steps[$i].status')
    if [[ "$step_st" == "skipped" ]]; then
      idx=$((idx + 1))
    else
      break
    fi
  done
  echo "$idx"
}

# FR-001/FR-002/FR-003: Resolve the next step index after a step completes.
# If step has a `next` field, resolve it to the target step index.
# If step has no `next` field, default to step_index + 1.
# If the resolved index >= total_steps, the workflow ends.
# Params: $1 = step JSON (string), $2 = step index (int), $3 = workflow JSON (string)
# Output (stdout): integer — the next step index
# Exit: 0 on success, 1 if next field references nonexistent step
resolve_next_index() {
  local step_json="$1"
  local step_index="$2"
  local workflow_json="$3"

  local next_id
  next_id=$(printf '%s\n' "$step_json" | jq -r '.next // empty')

  if [[ -n "$next_id" ]]; then
    # FR-001: Resolve next field to target step index
    local target_index
    target_index=$(workflow_get_step_index "$workflow_json" "$next_id")
    if [[ $? -ne 0 ]]; then
      echo "ERROR: next field references nonexistent step: $next_id" >&2
      return 1
    fi
    echo "$target_index"
  else
    # FR-002: Default to step_index + 1
    echo "$((step_index + 1))"
  fi
}

# FR-008/FR-009/FR-010: Handle terminal step cleanup.
# Archives state.json to .wheel/history/success/ or .wheel/history/failure/
# based on step ID, then removes state.json.
# Params: $1 = state file path, $2 = step JSON (string)
# Output: none
# Exit: 0 on success, 1 on archive failure
# Chain to the parent workflow's new current step after a child archives.
# Called immediately after handle_terminal_step returns success, when we know
# the child has been archived and the parent cursor has advanced. This keeps
# the parent's next step dispatched in the SAME hook call so the workflow
# doesn't stall waiting for an unrelated hook event to fire.
#
# Params:
#   $1 = parent_state_file  (captured BEFORE handle_terminal_step)
#   $2 = hook_type          (stop | post_tool_use | teammate_idle | subagent_stop)
#   $3 = hook_input_json    (raw JSON from hook stdin)
#
# Output (stdout): JSON hook response
# Exit: 0 on success
#
# Preconditions: $1 must be a captured snapshot — once handle_terminal_step
# archives the child, the child's state_file is gone so we cannot read its
# parent_workflow field anymore.
_chain_parent_after_archive() {
  local parent_state_path="$1"
  local _orig_hook_type="$2"
  local hook_input_json="$3"
  # Always dispatch the parent's next step with "stop" semantics so that
  # agent steps transition pending→working and return a block with their
  # instruction. Other hook_types (post_tool_use, teammate_idle) would skip
  # that transition and leave the parent orphaned.
  local hook_type="stop"

  declare -f wheel_log >/dev/null 2>&1 && \
    wheel_log "chain_parent_enter" "parent_snap=${parent_state_path} orig_hook=${_orig_hook_type}"

  if [[ -z "$parent_state_path" ]]; then
    declare -f wheel_log >/dev/null 2>&1 && \
      wheel_log "chain_parent_exit" "reason=no_parent_snap"
    jq -n '{"decision": "approve"}'
    return 0
  fi
  if [[ ! -f "$parent_state_path" ]]; then
    declare -f wheel_log >/dev/null 2>&1 && \
      wheel_log "chain_parent_exit" "reason=parent_file_missing path=${parent_state_path}"
    jq -n '{"decision": "approve"}'
    return 0
  fi

  local parent_wf_file
  parent_wf_file=$(jq -r '.workflow_file // empty' "$parent_state_path" 2>/dev/null)
  if [[ -z "$parent_wf_file" || ! -f "$parent_wf_file" ]]; then
    declare -f wheel_log >/dev/null 2>&1 && \
      wheel_log "chain_parent_exit" "reason=no_wf_file parent_wf_file=${parent_wf_file}"
    jq -n '{"decision": "approve"}'
    return 0
  fi

  local parent_wf_json
  parent_wf_json=$(workflow_load "$parent_wf_file" 2>/dev/null) || {
    declare -f wheel_log >/dev/null 2>&1 && \
      wheel_log "chain_parent_exit" "reason=workflow_load_failed file=${parent_wf_file}"
    jq -n '{"decision": "approve"}'
    return 0
  }
  if [[ -z "$parent_wf_json" ]]; then
    declare -f wheel_log >/dev/null 2>&1 && \
      wheel_log "chain_parent_exit" "reason=empty_wf_json file=${parent_wf_file}"
    jq -n '{"decision": "approve"}'
    return 0
  fi

  local parent_cursor parent_total
  parent_cursor=$(jq -r '.cursor // 0' "$parent_state_path")
  parent_total=$(printf '%s\n' "$parent_wf_json" | jq '.steps | length')

  declare -f wheel_log >/dev/null 2>&1 && \
    wheel_log "chain_parent_loaded" "cursor=${parent_cursor} total=${parent_total} wf_file=${parent_wf_file}"

  if [[ "$parent_cursor" -ge "$parent_total" ]]; then
    declare -f wheel_log >/dev/null 2>&1 && \
      wheel_log "chain_parent_exit" "reason=cursor_past_end cursor=${parent_cursor} total=${parent_total}"
    jq -n '{"decision": "approve"}'
    return 0
  fi

  local parent_step_json
  parent_step_json=$(printf '%s\n' "$parent_wf_json" | jq -c --argjson idx "$parent_cursor" '.steps[$idx]')
  local _parsed_id
  _parsed_id=$(printf '%s\n' "$parent_step_json" | jq -r '.id // "?"')

  # Swap WORKFLOW/STATE_FILE context to parent for the nested dispatch
  local _saved_wf="${WORKFLOW:-}"
  local _saved_sf="${STATE_FILE:-}"
  WORKFLOW="$parent_wf_json"
  STATE_FILE="$parent_state_path"
  declare -f wheel_log >/dev/null 2>&1 && \
    wheel_log "chain_parent_dispatch" "parent=${parent_state_path} parent_cursor=${parent_cursor}/${parent_total} step_id=${_parsed_id}"
  dispatch_step "$parent_step_json" "$hook_type" "$hook_input_json" "$parent_state_path" "$parent_cursor"
  local rc=$?
  WORKFLOW="$_saved_wf"
  STATE_FILE="$_saved_sf"
  return $rc
}

handle_terminal_step() {
  local state_file="$1"
  local step_json="$2"

  local is_terminal
  is_terminal=$(printf '%s\n' "$step_json" | jq -r '.terminal // false')
  if [[ "$is_terminal" != "true" ]]; then
    return 1
  fi
  local _sid
  _sid=$(printf '%s\n' "$step_json" | jq -r '.id // "unknown"')
  declare -f wheel_log >/dev/null 2>&1 && \
    wheel_log "handle_terminal_step" "state=${state_file} step_id=${_sid}"

  # FR-009/FR-012: Before archiving, check if this is a child workflow with a parent
  local parent_state_path
  parent_state_path=$(jq -r '.parent_workflow // empty' "$state_file" 2>/dev/null)
  if [[ -n "$parent_state_path" && -f "$parent_state_path" ]]; then
    # FR-012: Find parent's workflow step in working status and mark it done
    local parent_state
    parent_state=$(state_read "$parent_state_path") || true
    if [[ -n "$parent_state" ]]; then
      # Find the workflow step index that is in "working" status
      local parent_step_index
      parent_step_index=$(printf '%s\n' "$parent_state" | jq -r '
        [.steps | to_entries[] | select(.value.type == "workflow" and .value.status == "working") | .key] | first // empty')
      if [[ -n "$parent_step_index" ]]; then
        # Mark parent's workflow step as done
        state_set_step_status "$parent_state_path" "$parent_step_index" "done"
        declare -f wheel_log >/dev/null 2>&1 && \
          wheel_log "handle_terminal_step" "advance_parent parent=${parent_state_path} parent_idx=${parent_step_index}"

        # Resolve next index and advance parent cursor
        local parent_wf_file
        parent_wf_file=$(printf '%s\n' "$parent_state" | jq -r '.workflow_file // empty')
        if [[ -n "$parent_wf_file" && -f "$parent_wf_file" ]]; then
          local parent_workflow_json
          parent_workflow_json=$(jq -c '.' "$parent_wf_file" 2>/dev/null) || true
          if [[ -n "$parent_workflow_json" ]]; then
            local parent_step_json
            parent_step_json=$(printf '%s\n' "$parent_workflow_json" | jq --argjson idx "$parent_step_index" '.steps[$idx]')
            local raw_next
            raw_next=$(resolve_next_index "$parent_step_json" "$parent_step_index" "$parent_workflow_json") || true
            if [[ -n "$raw_next" ]]; then
              local next_index
              next_index=$(advance_past_skipped "$parent_state_path" "$raw_next" "$parent_workflow_json")
              state_set_cursor "$parent_state_path" "$next_index"

              # FR-009: If the parent's workflow step was terminal, recurse
              local parent_is_terminal
              parent_is_terminal=$(printf '%s\n' "$parent_step_json" | jq -r '.terminal // false')
              if [[ "$parent_is_terminal" == "true" ]]; then
                handle_terminal_step "$parent_state_path" "$parent_step_json"
              fi
            fi
          fi
        fi
      fi
    fi
  fi

  # FR-009: Determine archive subdirectory based on actual execution outcome.
  # Primary signal: state.status == "failed", or the terminal step's own
  # status == "failed" (command exited non-zero, loop exhausted with
  # on_exhaustion=fail, etc.). Fallback to step-id substring match for
  # legacy workflows that use "failure" in the id to indicate a failure path.
  local step_id
  step_id=$(printf '%s\n' "$step_json" | jq -r '.id // "unknown"')
  local archive_dir=".wheel/history/success"
  local _wf_status _step_status
  _wf_status=$(jq -r '.status // empty' "$state_file" 2>/dev/null || echo "")
  _step_status=$(jq -r --arg id "$step_id" \
    '[.steps[]? | select(.id == $id) | .status // empty] | .[0] // empty' \
    "$state_file" 2>/dev/null || echo "")
  if [[ "$_wf_status" == "failed" || "$_step_status" == "failed" ]]; then
    archive_dir=".wheel/history/failure"
  elif [[ "$step_id" == *"failure"* ]]; then
    archive_dir=".wheel/history/failure"
  fi

  # Archive state.json
  mkdir -p "$archive_dir"
  local workflow_name
  workflow_name=$(jq -r '.workflow_name // "workflow"' "$state_file" 2>/dev/null || echo "workflow")
  local timestamp
  timestamp=$(date -u +%Y%m%d-%H%M%S)
  if ! cp "$state_file" "${archive_dir}/${workflow_name}-${timestamp}.json"; then
    echo "ERROR: failed to archive state.json" >&2
    return 1
  fi

  # FR-010: Remove state.json
  rm -f "$state_file"
  return 0
}

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
  local step_json="$1"
  local hook_type="$2"
  local hook_input_json="$3"
  local state_file="$4"
  local step_index="$5"

  local state
  state=$(state_read "$state_file") || return 1
  local step_status
  step_status=$(state_get_step_status "$state" "$step_index")
  local _cn
  _cn=$(printf '%s\n' "$step_json" | jq -r '.workflow // empty')
  declare -f wheel_log >/dev/null 2>&1 && \
    wheel_log "dispatch_workflow" "hook=${hook_type} idx=${step_index} status=${step_status} child=${_cn}"

  case "$hook_type" in
    stop|post_tool_use)
      # Activate child workflow when step is pending (stop hook or PostToolUse after cursor advance)
      if [[ "$step_status" == "pending" ]]; then
        # Atomic check-and-set: prevent concurrent hook invocations from both
        # seeing "pending" and each creating a child state file (double dispatch).
        # mkdir-based lock per (state_file, step_index). The lock is held for the
        # lifetime of this child creation and NOT released — if the step is done,
        # working, or failed, later invocations will see that status and skip.
        local dispatch_lock_base="${STATE_DIR:-.wheel}/.locks"
        local state_basename
        state_basename="$(basename "$state_file" .json)"
        local dispatch_lock_name="workflow-dispatch-${state_basename}-${step_index}"
        if ! lock_acquire "$dispatch_lock_base" "$dispatch_lock_name"; then
          # Another invocation is already creating the child — re-read status
          # (it may have transitioned to working by now) and return a wait.
          local child_name
          child_name=$(printf '%s\n' "$step_json" | jq -r '.workflow // empty')
          declare -f wheel_log >/dev/null 2>&1 && \
            wheel_log "dispatch_workflow" "lock_contended child=${child_name} idx=${step_index}"
          jq -n --arg reason "Waiting for child workflow to activate: ${child_name}" \
            '{"decision": "block", "reason": $reason}'
          return 0
        fi
        declare -f wheel_log >/dev/null 2>&1 && \
          wheel_log "dispatch_workflow" "lock_acquired child=${_cn} idx=${step_index}"
        # Re-read status under the lock in case another caller won the race
        # before us and already transitioned the step.
        state=$(state_read "$state_file") || return 1
        step_status=$(state_get_step_status "$state" "$step_index")
        if [[ "$step_status" != "pending" ]]; then
          # Status already changed — step is working/done/failed elsewhere.
          # Fall through to the working/done branches below.
          case "$step_status" in
            working)
              local child_name
              child_name=$(printf '%s\n' "$step_json" | jq -r '.workflow // empty')
              jq -n --arg reason "Waiting for child workflow to complete: ${child_name}" \
                '{"decision": "block", "reason": $reason}'
              return 0
              ;;
            *)
              jq -n '{"decision": "approve"}'
              return 0
              ;;
          esac
        fi
        state_set_step_status "$state_file" "$step_index" "working"

        # FR-007: Load child workflow and create child state file
        local child_name
        child_name=$(printf '%s\n' "$step_json" | jq -r '.workflow // empty')
        local child_file
        if [[ "$child_name" == *":"* ]]; then
          # Plugin workflow — resolve via plugin discovery
          local plugin_name="${child_name%%:*}"
          local wf_name="${child_name#*:}"
          # Check for local override first
          if [[ -f "workflows/${wf_name}.json" ]]; then
            child_file="workflows/${wf_name}.json"
          else
            child_file=$(bash -c "source '${WHEEL_LIB_DIR}/workflow.sh' && workflow_discover_plugin_workflows" 2>/dev/null | jq -r \
              --arg plugin "$plugin_name" --arg name "$wf_name" \
              '.[] | select(.plugin == $plugin and .name == $name) | .path // empty')
            if [[ -z "$child_file" ]]; then
              echo "ERROR: Plugin workflow not found: $child_name" >&2
              return 1
            fi
          fi
        else
          child_file="workflows/${child_name}.json"
        fi

        local child_json
        child_json=$(workflow_load "$child_file") || return 1

        # Extract parent ownership for child
        local session_id agent_id
        session_id=$(printf '%s\n' "$state" | jq -r '.owner_session_id // empty')
        agent_id=$(printf '%s\n' "$state" | jq -r '.owner_agent_id // empty')

        # FR-016: Create child state file with parent_workflow reference
        # Sanitize child_name: replace / with - to avoid subdirectory creation
        local safe_child_name="${child_name//\//-}"
        local child_unique="child_${safe_child_name}_$(date +%s)_${RANDOM}"
        local child_state_file=".wheel/state_${child_unique}.json"

        state_init "$child_state_file" "$child_json" "$session_id" "$agent_id" "$child_file" "$state_file"
        declare -f wheel_log >/dev/null 2>&1 && \
          wheel_log "dispatch_workflow" "created_child state=${child_state_file} wf=${child_file}"

        # FR-015: Kickstart child workflow
        local saved_workflow="$WORKFLOW"
        WORKFLOW="$child_json"
        engine_kickstart "$child_state_file" >/dev/null 2>&1
        WORKFLOW="$saved_workflow"
        declare -f wheel_log >/dev/null 2>&1 && \
          wheel_log "dispatch_workflow" "post_kickstart child=${child_state_file}"

        # If child completed inline (command-only child), handle_terminal_step
        # already marked this parent's workflow step "done" and advanced the
        # parent cursor. Chain-dispatch the next parent step inline instead of
        # blocking — otherwise the turn ends and the next child requires a new
        # Claude turn to activate.
        if [[ ! -f "$state_file" ]]; then
          # Parent archived too (child was parent's terminal step)
          jq -n '{"decision": "approve"}'
          return 0
        fi
        local post_state post_status
        post_state=$(state_read "$state_file") || { jq -n '{"decision": "approve"}'; return 0; }
        post_status=$(state_get_step_status "$post_state" "$step_index")
        if [[ "$post_status" == "done" ]]; then
          local post_cursor total_parent_steps
          post_cursor=$(state_get_cursor "$post_state")
          total_parent_steps=$(printf '%s\n' "$WORKFLOW" | jq '.steps | length')
          declare -f wheel_log >/dev/null 2>&1 && \
            wheel_log "dispatch_workflow" "inline_chain parent_cursor=${post_cursor}/${total_parent_steps}"
          if [[ "$post_cursor" -ge "$total_parent_steps" ]]; then
            jq -n '{"decision": "approve"}'
            return 0
          fi
          local next_parent_step
          next_parent_step=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$post_cursor" '.steps[$idx]')
          # Recursively dispatch the next parent step in the same hook call.
          dispatch_step "$next_parent_step" "$hook_type" "$hook_input_json" "$state_file" "$post_cursor"
          return $?
        fi
        declare -f wheel_log >/dev/null 2>&1 && \
          wheel_log "dispatch_workflow" "return_block reason=activated_child child=${_cn}"

        jq -n --arg reason "Workflow step activated child: ${child_name}" \
          '{"decision": "block", "reason": $reason}'
      elif [[ "$step_status" == "working" ]]; then
        # Child is still running — block with status message
        local child_name
        child_name=$(printf '%s\n' "$step_json" | jq -r '.workflow // empty')
        jq -n --arg reason "Waiting for child workflow to complete: ${child_name}" \
          '{"decision": "block", "reason": $reason}'
      else
        jq -n '{"decision": "approve"}'
      fi
      ;;
    *)
      jq -n '{"decision": "approve"}'
      ;;
  esac
}

# FR-003/019/024/025/026: Dispatch a step based on its type
# Params: $1 = step JSON (string), $2 = hook_type, $3 = hook_input_json, $4 = state file path, $5 = step index
# Output (stdout): JSON hook response
# Exit: 0 on success, 1 on error
dispatch_step() {
  local step_json="$1"
  local hook_type="$2"
  local hook_input_json="$3"
  local state_file="$4"
  local step_index="$5"

  local step_type
  step_type=$(printf '%s\n' "$step_json" | jq -r '.type')
  local _sid
  _sid=$(printf '%s\n' "$step_json" | jq -r '.id // "unknown"')
  declare -f wheel_log >/dev/null 2>&1 && \
    wheel_log "dispatch_step" "hook=${hook_type} idx=${step_index} id=${_sid} type=${step_type}"

  case "$step_type" in
    agent)
      dispatch_agent "$step_json" "$hook_type" "$hook_input_json" "$state_file" "$step_index"
      ;;
    command)
      dispatch_command "$step_json" "$state_file" "$step_index"
      ;;
    parallel)
      dispatch_parallel "$step_json" "$hook_type" "$hook_input_json" "$state_file" "$step_index"
      ;;
    approval)
      dispatch_approval "$step_json" "$hook_type" "$hook_input_json" "$state_file" "$step_index"
      ;;
    branch)
      dispatch_branch "$step_json" "$state_file" "$step_index" "$WORKFLOW"
      ;;
    loop)
      dispatch_loop "$step_json" "$state_file" "$step_index" "$WORKFLOW"
      ;;
    workflow)
      # FR-001/FR-002: Dispatch workflow step to child workflow handler
      dispatch_workflow "$step_json" "$hook_type" "$hook_input_json" "$state_file" "$step_index"
      ;;
    team-create)
      # FR-001/FR-004: Dispatch team-create step
      dispatch_team_create "$step_json" "$hook_type" "$hook_input_json" "$state_file" "$step_index"
      ;;
    teammate)
      # FR-005/FR-011: Dispatch teammate step (static or dynamic via loop_from)
      dispatch_teammate "$step_json" "$hook_type" "$hook_input_json" "$state_file" "$step_index"
      ;;
    team-wait)
      # FR-015/FR-019: Dispatch team-wait step (blocks until all teammates done)
      dispatch_team_wait "$step_json" "$hook_type" "$hook_input_json" "$state_file" "$step_index"
      ;;
    team-delete)
      # FR-020/FR-023: Dispatch team-delete step (shutdown + cleanup)
      dispatch_team_delete "$step_json" "$hook_type" "$hook_input_json" "$state_file" "$step_index"
      ;;
    *)
      echo "ERROR: unknown step type: $step_type" >&2
      return 1
      ;;
  esac
}

# FR-003: Handle an agent step — build instruction injection response
# Params: $1 = step JSON, $2 = hook_type, $3 = hook_input_json, $4 = state file path, $5 = step index
# Output (stdout): JSON hook response with instruction
# Exit: 0
dispatch_agent() {
  local step_json="$1"
  local hook_type="$2"
  local hook_input_json="$3"
  local state_file="$4"
  local step_index="$5"

  local state
  state=$(state_read "$state_file") || return 1
  local step_status
  step_status=$(state_get_step_status "$state" "$step_index")

  declare -f wheel_log >/dev/null 2>&1 && \
    wheel_log "dispatch_agent" "hook=${hook_type} idx=${step_index} status=${step_status}"

  case "$hook_type" in
    stop)
      # Gate the orchestrator — inject step instruction
      if [[ "$step_status" == "pending" ]]; then
        # Delete any stale output file from a prior run. Without this, the
        # working→done transition below would auto-complete the step based
        # on a leftover file the current agent never touched.
        local _out_clear
        _out_clear=$(printf '%s\n' "$step_json" | jq -r '.output // empty')
        declare -f wheel_log >/dev/null 2>&1 && \
          wheel_log "agent_pending" "step=$(printf '%s' "$step_json" | jq -r '.id // "?"') output_key=${_out_clear} exists=$([[ -f "$_out_clear" ]] && echo yes || echo no)"
        if [[ -n "$_out_clear" && -f "$_out_clear" ]]; then
          rm -f "$_out_clear"
          declare -f wheel_log >/dev/null 2>&1 && \
            wheel_log "agent_pending" "removed_stale_output=${_out_clear}"
        fi
        state_set_step_status "$state_file" "$step_index" "working"
        local context
        context=$(context_build "$step_json" "$state" "$WORKFLOW")
        jq -n --arg msg "$context" '{"decision": "block", "reason": $msg}'
      elif [[ "$step_status" == "working" ]]; then
        # Check if the agent completed its work (output file exists)
        local output_key
        output_key=$(printf '%s\n' "$step_json" | jq -r '.output // empty')
        if [[ -n "$output_key" && -f "$output_key" ]]; then
          # Agent step is done — mark complete, capture output, advance
          state_set_step_status "$state_file" "$step_index" "done"
          context_capture_output "$state_file" "$step_index" "$output_key"
          # FR-008: Check for terminal step — archive and end workflow
          local _parent_snap
          _parent_snap=$(jq -r '.parent_workflow // empty' "$state_file" 2>/dev/null)
          if handle_terminal_step "$state_file" "$step_json"; then
            _chain_parent_after_archive "$_parent_snap" "stop" "$hook_input_json"
            return $?
          fi
          # FR-005: Resolve next index via next field or default to step_index + 1
          local raw_next
          raw_next=$(resolve_next_index "$step_json" "$step_index" "$WORKFLOW") || return 1
          local next_index
          next_index=$(advance_past_skipped "$state_file" "$raw_next" "$WORKFLOW")
          state_set_cursor "$state_file" "$next_index"
          # Dispatch next step
          local total_steps
          total_steps=$(printf '%s\n' "$WORKFLOW" | jq '.steps | length')
          if [[ "$next_index" -lt "$total_steps" ]]; then
            local next_step_json
            next_step_json=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$next_index" '.steps[$idx]')
            dispatch_step "$next_step_json" "stop" "$hook_input_json" "$state_file" "$next_index"
          else
            jq -n '{"decision": "approve"}'
          fi
        elif [[ -z "$output_key" ]]; then
          # No output file expected — agent step auto-completes on second stop
          state_set_step_status "$state_file" "$step_index" "done"
          local _parent_snap
          _parent_snap=$(jq -r '.parent_workflow // empty' "$state_file" 2>/dev/null)
          if handle_terminal_step "$state_file" "$step_json"; then
            _chain_parent_after_archive "$_parent_snap" "stop" "$hook_input_json"
            return $?
          fi
          local raw_next
          raw_next=$(resolve_next_index "$step_json" "$step_index" "$WORKFLOW") || return 1
          local next_index
          next_index=$(advance_past_skipped "$state_file" "$raw_next" "$WORKFLOW")
          state_set_cursor "$state_file" "$next_index"
          local total_steps
          total_steps=$(printf '%s\n' "$WORKFLOW" | jq '.steps | length')
          if [[ "$next_index" -lt "$total_steps" ]]; then
            local next_step_json
            next_step_json=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$next_index" '.steps[$idx]')
            dispatch_step "$next_step_json" "stop" "$hook_input_json" "$state_file" "$next_index"
          else
            jq -n '{"decision": "approve"}'
          fi
        else
          # Output file expected but not yet produced — short reminder
          local step_id
          step_id=$(printf '%s\n' "$step_json" | jq -r '.id // "current"')
          jq -n --arg msg "Step '${step_id}' is in progress. Write your output to: ${output_key}" \
            '{"decision": "block", "reason": $msg}'
        fi
      else
        jq -n '{"decision": "approve"}'
      fi
      ;;
    teammate_idle)
      # Teammates go idle between turns instead of firing Stop hooks.
      # Handle pending → working transition here (mirrors stop handler).
      if [[ "$step_status" == "pending" ]]; then
        state_set_step_status "$state_file" "$step_index" "working"
        local context
        context=$(context_build "$step_json" "$state" "$WORKFLOW")
        jq -n --arg msg "$context" '{"decision": "block", "reason": $msg}'
      elif [[ "$step_status" == "working" ]]; then
        # Check if agent completed (output file exists) — same logic as stop handler
        local output_key
        output_key=$(printf '%s\n' "$step_json" | jq -r '.output // empty')
        if [[ -n "$output_key" && -f "$output_key" ]]; then
          state_set_step_status "$state_file" "$step_index" "done"
          context_capture_output "$state_file" "$step_index" "$output_key"
          local _parent_snap
          _parent_snap=$(jq -r '.parent_workflow // empty' "$state_file" 2>/dev/null)
          if handle_terminal_step "$state_file" "$step_json"; then
            _chain_parent_after_archive "$_parent_snap" "teammate_idle" "$hook_input_json"
            return $?
          fi
          local raw_next
          raw_next=$(resolve_next_index "$step_json" "$step_index" "$WORKFLOW") || return 1
          local next_index
          next_index=$(advance_past_skipped "$state_file" "$raw_next" "$WORKFLOW")
          state_set_cursor "$state_file" "$next_index"
          local total_steps
          total_steps=$(printf '%s\n' "$WORKFLOW" | jq '.steps | length')
          if [[ "$next_index" -lt "$total_steps" ]]; then
            local next_step_json
            next_step_json=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$next_index" '.steps[$idx]')
            dispatch_step "$next_step_json" "teammate_idle" "$hook_input_json" "$state_file" "$next_index"
          else
            jq -n '{"decision": "approve"}'
          fi
        elif [[ -z "$output_key" ]]; then
          # No output file expected — agent step completes when agent goes idle after working
          state_set_step_status "$state_file" "$step_index" "done"
          local _parent_snap
          _parent_snap=$(jq -r '.parent_workflow // empty' "$state_file" 2>/dev/null)
          if handle_terminal_step "$state_file" "$step_json"; then
            _chain_parent_after_archive "$_parent_snap" "teammate_idle" "$hook_input_json"
            return $?
          fi
          local raw_next
          raw_next=$(resolve_next_index "$step_json" "$step_index" "$WORKFLOW") || return 1
          local next_index
          next_index=$(advance_past_skipped "$state_file" "$raw_next" "$WORKFLOW")
          state_set_cursor "$state_file" "$next_index"
          local total_steps
          total_steps=$(printf '%s\n' "$WORKFLOW" | jq '.steps | length')
          if [[ "$next_index" -lt "$total_steps" ]]; then
            local next_step_json
            next_step_json=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$next_index" '.steps[$idx]')
            dispatch_step "$next_step_json" "teammate_idle" "$hook_input_json" "$state_file" "$next_index"
          else
            jq -n '{"decision": "approve"}'
          fi
        else
          local step_id
          step_id=$(printf '%s\n' "$step_json" | jq -r '.id // "current"')
          jq -n --arg msg "Step '${step_id}' is in progress. Write your output to: ${output_key}" \
            '{"decision": "block", "reason": $msg}'
        fi
      else
        jq -n '{"decision": "approve"}'
      fi
      ;;
    post_tool_use)
      # FR-030: Detect when agent writes to the step's output file
      # Only triggers on Write/Edit targeting the exact output path — safe during
      # normal agent work (reads, bash, writing to other files are all ignored)
      local output_key
      output_key=$(printf '%s\n' "$step_json" | jq -r '.output // empty')
      if [[ -z "$output_key" ]]; then
        # No output expected. If already "working", auto-complete — the agent
        # has been acting on the instruction and there's no file to wait for.
        if [[ "$step_status" == "working" ]]; then
          state_set_step_status "$state_file" "$step_index" "done"
          local _parent_snap
          _parent_snap=$(jq -r '.parent_workflow // empty' "$state_file" 2>/dev/null)
          if handle_terminal_step "$state_file" "$step_json"; then
            _chain_parent_after_archive "$_parent_snap" "post_tool_use" "$hook_input_json"
            return $?
          fi
          local raw_next
          raw_next=$(resolve_next_index "$step_json" "$step_index" "$WORKFLOW") || return 1
          local next_index
          next_index=$(advance_past_skipped "$state_file" "$raw_next" "$WORKFLOW")
          state_set_cursor "$state_file" "$next_index"
          # Chain to command steps
          local total_steps
          total_steps=$(printf '%s\n' "$WORKFLOW" | jq '.steps | length')
          if [[ "$next_index" -lt "$total_steps" ]]; then
            local next_step_json
            next_step_json=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$next_index" '.steps[$idx]')
            local next_step_type
            next_step_type=$(printf '%s\n' "$next_step_json" | jq -r '.type')
            if [[ "$next_step_type" == "command" || "$next_step_type" == "loop" || "$next_step_type" == "branch" ]]; then
              export WHEEL_HOOK_SCRIPT=""
              export WHEEL_HOOK_INPUT='{}'
              dispatch_step "$next_step_json" "stop" '{}' "$state_file" "$next_index" >/dev/null 2>&1
            fi
          fi
        fi
        jq -n '{"hookEventName": "PostToolUse"}'
        return 0
      fi

      # Only match Write or Edit tools
      local tool_name
      tool_name=$(printf '%s\n' "$hook_input_json" | jq -r '.tool_name // empty')
      if [[ "$tool_name" != "Write" && "$tool_name" != "Edit" ]]; then
        jq -n '{"hookEventName": "PostToolUse"}'
        return 0
      fi

      # Compare the written file path to the step's output path
      local wrote_to
      wrote_to=$(printf '%s\n' "$hook_input_json" | jq -r '.tool_input.file_path // empty')
      local abs_output_key
      if [[ "$output_key" == /* ]]; then
        abs_output_key="$output_key"
      else
        abs_output_key="$(pwd)/$output_key"
      fi

      if [[ "$wrote_to" != "$abs_output_key" ]] || [[ ! -f "$wrote_to" ]]; then
        jq -n '{"hookEventName": "PostToolUse"}'
        return 0
      fi

      # Agent wrote to the output file — mark step done, advance
      state_set_step_status "$state_file" "$step_index" "done"
      context_capture_output "$state_file" "$step_index" "$output_key"

      # FR-008: Check for terminal step — archive and end workflow
      local _parent_snap
      _parent_snap=$(jq -r '.parent_workflow // empty' "$state_file" 2>/dev/null)
      if handle_terminal_step "$state_file" "$step_json"; then
        # Chain into the parent's new current step inline so the next step's
        # instruction is injected in this same hook call.
        _chain_parent_after_archive "$_parent_snap" "post_tool_use" "$hook_input_json"
        return $?
      fi

      # FR-005: Resolve next index and advance cursor
      local raw_next
      raw_next=$(resolve_next_index "$step_json" "$step_index" "$WORKFLOW") || return 1
      local next_index
      next_index=$(advance_past_skipped "$state_file" "$raw_next" "$WORKFLOW")
      state_set_cursor "$state_file" "$next_index"

      # Chain into auto-executable steps so workflow doesn't stall.
      # Includes command/loop/branch (always auto-exec) and agent steps without
      # output files (auto-complete — the agent acts on them naturally from context).
      local total_steps
      total_steps=$(printf '%s\n' "$WORKFLOW" | jq '.steps | length')
      if [[ "$next_index" -lt "$total_steps" ]]; then
        local next_step_json
        next_step_json=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$next_index" '.steps[$idx]')
        local next_step_type
        next_step_type=$(printf '%s\n' "$next_step_json" | jq -r '.type')
        if [[ "$next_step_type" == "command" || "$next_step_type" == "loop" || "$next_step_type" == "branch" ]]; then
          export WHEEL_HOOK_SCRIPT=""
          export WHEEL_HOOK_INPUT='{}'
          dispatch_step "$next_step_json" "stop" '{}' "$state_file" "$next_index" >/dev/null 2>&1
        elif [[ "$next_step_type" == "agent" ]]; then
          local next_output
          next_output=$(printf '%s\n' "$next_step_json" | jq -r '.output // empty')
          if [[ -z "$next_output" ]]; then
            # Agent step with no output — auto-complete and chain further
            state_set_step_status "$state_file" "$next_index" "done"
            if ! handle_terminal_step "$state_file" "$next_step_json"; then
              local raw_next2
              raw_next2=$(resolve_next_index "$next_step_json" "$next_index" "$WORKFLOW") || true
              if [[ -n "$raw_next2" ]]; then
                local next_index2
                next_index2=$(advance_past_skipped "$state_file" "$raw_next2" "$WORKFLOW")
                state_set_cursor "$state_file" "$next_index2"
                if [[ "$next_index2" -lt "$total_steps" ]]; then
                  local next_step_json2
                  next_step_json2=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$next_index2" '.steps[$idx]')
                  local next_type2
                  next_type2=$(printf '%s\n' "$next_step_json2" | jq -r '.type')
                  if [[ "$next_type2" == "command" || "$next_type2" == "loop" || "$next_type2" == "branch" ]]; then
                    export WHEEL_HOOK_SCRIPT=""
                    export WHEEL_HOOK_INPUT='{}'
                    dispatch_step "$next_step_json2" "stop" '{}' "$state_file" "$next_index2" >/dev/null 2>&1
                  fi
                fi
              fi
            fi
          fi
        fi
      fi

      jq -n '{"hookEventName": "PostToolUse"}'
      return 0
      ;;
    subagent_stop)
      # SubagentStop fires when the enclosing Task subagent exits or transitions
      # between turns. It does NOT mean "this agent step is done" — the current
      # agent step may or may not have produced its output yet. Only advance if
      # the step's declared output file exists (same gate as the stop/working
      # branch). Otherwise this is a no-op so the workflow can be resumed on
      # the next hook event.
      local output_key
      output_key=$(printf '%s\n' "$step_json" | jq -r '.output // empty')
      if [[ -n "$output_key" && -f "$output_key" ]]; then
        state_set_step_status "$state_file" "$step_index" "done"
        context_capture_output "$state_file" "$step_index" "$output_key"
        local _parent_snap
        _parent_snap=$(jq -r '.parent_workflow // empty' "$state_file" 2>/dev/null)
        if handle_terminal_step "$state_file" "$step_json"; then
          _chain_parent_after_archive "$_parent_snap" "subagent_stop" "$hook_input_json"
          return $?
        fi
        local raw_next
        raw_next=$(resolve_next_index "$step_json" "$step_index" "$WORKFLOW") || return 1
        local next_index
        next_index=$(advance_past_skipped "$state_file" "$raw_next" "$WORKFLOW")
        state_set_cursor "$state_file" "$next_index"
      fi
      jq -n '{"decision": "approve"}'
      ;;
    *)
      jq -n '{"decision": "approve"}'
      ;;
  esac
}

# FR-019/020/021: Handle a command step — execute shell command, record result, optionally chain
# Params: $1 = step JSON, $2 = state file path, $3 = step index
# Output (stdout): JSON hook response (may re-exec for chaining)
# Exit: 0 on success, exit code of command on failure
dispatch_command() {
  local step_json="$1"
  local state_file="$2"
  local step_index="$3"

  # Mark step as working
  state_set_step_status "$state_file" "$step_index" "working"

  local command
  command=$(printf '%s\n' "$step_json" | jq -r '.command // empty')
  if [[ -z "$command" ]]; then
    echo "ERROR: command step missing 'command' field" >&2
    state_set_step_status "$state_file" "$step_index" "failed"
    return 1
  fi

  # Execute the command and capture output + exit code.
  # Note: `|| true` would reset $? and PIPESTATUS[0] to 0, losing the real
  # exit code. Use a conditional assignment that preserves it.
  local output
  local cmd_exit_code
  if output=$(eval "$command" 2>&1); then
    cmd_exit_code=0
  else
    cmd_exit_code=$?
  fi
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

  # FR-021: Record output, exit code, and timestamp in state.json
  state_append_command_log "$state_file" "$step_index" "$command" "$cmd_exit_code" "$now"

  # Store output (truncate if over 10KB to keep state.json manageable)
  local truncated_output
  if [[ ${#output} -gt 10240 ]]; then
    truncated_output="${output:0:10240}... [truncated]"
  else
    truncated_output="$output"
  fi

  # Record step output in state and write to disk
  local output_key
  output_key=$(printf '%s\n' "$step_json" | jq -r '.output // empty')
  if [[ -n "$output_key" ]]; then
    # If the command produced the file itself, don't clobber it.
    # Otherwise, write captured stdout to the declared path for downstream readers.
    if [[ ! -f "$output_key" ]]; then
      mkdir -p "$(dirname "$output_key")"
      printf '%s\n' "$truncated_output" > "$output_key"
    fi
    # State's .steps[$idx].output stores the file path (consistent with other step types),
    # so loop_from and downstream readers can locate the file.
    context_capture_output "$state_file" "$step_index" "$output_key"
  fi

  # Mark step done (or failed if non-zero exit)
  if [[ "$cmd_exit_code" -eq 0 ]]; then
    state_set_step_status "$state_file" "$step_index" "done"
  else
    state_set_step_status "$state_file" "$step_index" "failed"
    # Propagate failure to workflow-level status so handle_terminal_step
    # routes the archive to failure/ instead of success/.
    local _fs
    _fs=$(state_read "$state_file") || true
    if [[ -n "$_fs" ]]; then
      state_write "$state_file" "$(printf '%s\n' "$_fs" | jq '.status = "failed"')"
    fi
  fi

  # FR-008: Check for terminal step — archive and end workflow
  if handle_terminal_step "$state_file" "$step_json"; then
    jq -n '{"decision": "approve"}'
    return 0
  fi

  # FR-004: Resolve next index via next field or default to step_index + 1
  local raw_next
  raw_next=$(resolve_next_index "$step_json" "$step_index" "$WORKFLOW") || return 1
  local next_index
  next_index=$(advance_past_skipped "$state_file" "$raw_next" "$WORKFLOW")
  state_set_cursor "$state_file" "$next_index"

  # FR-020: Check if next step is also a command — chain via re-exec
  local state
  state=$(state_read "$state_file") || return 0
  local total_steps
  total_steps=$(printf '%s\n' "$WORKFLOW" | jq '.steps | length')
  if [[ "$next_index" -lt "$total_steps" ]]; then
    local next_step_type
    next_step_type=$(printf '%s\n' "$WORKFLOW" | jq -r --argjson idx "$next_index" '.steps[$idx].type')
    if [[ "$next_step_type" == "command" ]]; then
      # Chain: re-exec the hook to handle the next command step without LLM round-trip
      if [[ -n "$WHEEL_HOOK_SCRIPT" && -x "$WHEEL_HOOK_SCRIPT" ]]; then
        exec "$WHEEL_HOOK_SCRIPT" <<< "$WHEEL_HOOK_INPUT"
      fi
      # Fallback: direct dispatch (e.g., during kickstart when no hook script)
      local next_step_json
      next_step_json=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$next_index" '.steps[$idx]')
      dispatch_step "$next_step_json" "stop" "${WHEEL_HOOK_INPUT:-{}}" "$state_file" "$next_index"
      return $?
    else
      # Next step is not a command — dispatch to its handler (e.g., agent → block with instruction)
      local next_step_json
      next_step_json=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$next_index" '.steps[$idx]')
      dispatch_step "$next_step_json" "stop" "$WHEEL_HOOK_INPUT" "$state_file" "$next_index"
      return $?
    fi
  fi

  jq -n '{"decision": "approve"}'
}

# FR-009: Handle a parallel step — fan-out agent instructions
# Params: $1 = step JSON, $2 = hook_type, $3 = hook_input_json, $4 = state file path, $5 = step index
# Output (stdout): JSON hook response
# Exit: 0
dispatch_parallel() {
  local step_json="$1"
  local hook_type="$2"
  local hook_input_json="$3"
  local state_file="$4"
  local step_index="$5"

  local state
  state=$(state_read "$state_file") || return 1
  local step_status
  step_status=$(state_get_step_status "$state" "$step_index")

  case "$hook_type" in
    stop)
      # Gate orchestrator — tell it to spawn agents
      if [[ "$step_status" == "pending" ]]; then
        state_set_step_status "$state_file" "$step_index" "working"
        # Initialize agent statuses
        local agents
        agents=$(printf '%s\n' "$step_json" | jq -r '.agents[]')
        while IFS= read -r agent; do
          [[ -z "$agent" ]] && continue
          state_set_agent_status "$state_file" "$step_index" "$agent" "pending"
        done <<< "$agents"
      fi
      local instruction
      instruction=$(printf '%s\n' "$step_json" | jq -r '.instruction // "Spawn parallel agents for this step."')
      local agent_list
      agent_list=$(printf '%s\n' "$step_json" | jq -r '.agents | join(", ")')
      jq -n --arg msg "Spawn these agents in parallel: ${agent_list}. ${instruction}" \
        '{"decision": "block", "reason": $msg}'
      ;;
    teammate_idle)
      # Gate specific agent with its instruction
      local agent_type
      agent_type=$(printf '%s\n' "$hook_input_json" | jq -r '.agent_type // empty')
      if [[ -n "$agent_type" ]]; then
        local agent_status
        agent_status=$(state_get_agent_status "$state" "$step_index" "$agent_type" 2>/dev/null)
        if [[ "$agent_status" == "pending" || "$agent_status" == "idle" ]]; then
          state_set_agent_status "$state_file" "$step_index" "$agent_type" "working"
          local agent_instruction
          agent_instruction=$(printf '%s\n' "$step_json" | jq -r --arg agent "$agent_type" '.agent_instructions[$agent] // .instruction // empty')
          jq -n --arg msg "$agent_instruction" '{"decision": "block", "reason": $msg}'
        else
          jq -n '{"decision": "approve"}'
        fi
      else
        jq -n '{"decision": "approve"}'
      fi
      ;;
    subagent_stop)
      # Mark specific agent as done, check fan-in
      local agent_type
      agent_type=$(printf '%s\n' "$hook_input_json" | jq -r '.agent_type // empty')
      if [[ -n "$agent_type" ]]; then
        state_set_agent_status "$state_file" "$step_index" "$agent_type" "done"
      fi
      # FR-010: Check if all agents are done (fan-in)
      state=$(state_read "$state_file") || return 1
      local all_done
      all_done=$(printf '%s\n' "$state" | jq --argjson idx "$step_index" '
        [.steps[$idx].agents | to_entries[] | .value.status] | all(. == "done")')
      if [[ "$all_done" == "true" ]]; then
        # FR-010: Acquire lock to prevent double-advance
        local lock_base="${STATE_DIR}/.locks"
        local lock_name="step-${step_index}-fanin"
        if lock_acquire "$lock_base" "$lock_name"; then
          state_set_step_status "$state_file" "$step_index" "done"
          local next_index=$((step_index + 1))
          state_set_cursor "$state_file" "$next_index"
        fi
      fi
      jq -n '{"decision": "approve"}'
      ;;
    *)
      jq -n '{"decision": "approve"}'
      ;;
  esac
}

# FR-013: Handle an approval step — gate until approved
# Params: $1 = step JSON, $2 = hook_type, $3 = hook_input_json, $4 = state file path, $5 = step index
# Output (stdout): JSON hook response with approval prompt
# Exit: 0
dispatch_approval() {
  local step_json="$1"
  local hook_type="$2"
  local hook_input_json="$3"
  local state_file="$4"
  local step_index="$5"

  local state
  state=$(state_read "$state_file") || return 1
  local step_status
  step_status=$(state_get_step_status "$state" "$step_index")

  case "$hook_type" in
    stop)
      if [[ "$step_status" == "pending" ]]; then
        state_set_step_status "$state_file" "$step_index" "working"
      fi
      local message
      message=$(printf '%s\n' "$step_json" | jq -r '.message // "Approval required to continue."')
      jq -n --arg msg "APPROVAL GATE: ${message} — Waiting for approval via TeammateIdle." \
        '{"decision": "block", "reason": $msg}'
      ;;
    teammate_idle)
      # User/agent approves by sending idle with approval context
      local approval
      approval=$(printf '%s\n' "$hook_input_json" | jq -r '.approval // empty')
      if [[ "$approval" == "approved" ]]; then
        state_set_step_status "$state_file" "$step_index" "done"
        local next_index=$((step_index + 1))
        state_set_cursor "$state_file" "$next_index"
        jq -n '{"decision": "approve"}'
      else
        local message
        message=$(printf '%s\n' "$step_json" | jq -r '.message // "Approval required to continue."')
        jq -n --arg msg "WAITING FOR APPROVAL: ${message}" '{"decision": "block", "reason": $msg}'
      fi
      ;;
    *)
      jq -n '{"decision": "approve"}'
      ;;
  esac
}

# FR-024: Handle a branch step — evaluate condition, jump to target
# Params: $1 = step JSON, $2 = state file path, $3 = step index, $4 = workflow JSON
# Output: none (updates state cursor directly)
# Exit: 0 on success, 1 if target step not found
dispatch_branch() {
  local step_json="$1"
  local state_file="$2"
  local step_index="$3"
  local workflow_json="$4"

  state_set_step_status "$state_file" "$step_index" "working"

  local condition
  condition=$(printf '%s\n' "$step_json" | jq -r '.condition // empty')
  if [[ -z "$condition" ]]; then
    echo "ERROR: branch step missing 'condition' field" >&2
    state_set_step_status "$state_file" "$step_index" "failed"
    return 1
  fi

  # Evaluate the condition
  local cond_exit=0
  eval "$condition" >/dev/null 2>&1 || cond_exit=$?

  local target_id
  if [[ "$cond_exit" -eq 0 ]]; then
    target_id=$(printf '%s\n' "$step_json" | jq -r '.if_zero // empty')
  else
    target_id=$(printf '%s\n' "$step_json" | jq -r '.if_nonzero // empty')
  fi

  if [[ -z "$target_id" ]]; then
    # No target — just advance linearly
    state_set_step_status "$state_file" "$step_index" "done"
    local next_index=$((step_index + 1))
    state_set_cursor "$state_file" "$next_index"
    return 0
  fi

  # Find target step index
  local target_index
  target_index=$(workflow_get_step_index "$workflow_json" "$target_id")
  if [[ $? -ne 0 ]]; then
    echo "ERROR: branch target step not found: $target_id" >&2
    state_set_step_status "$state_file" "$step_index" "failed"
    return 1
  fi

  state_set_step_status "$state_file" "$step_index" "done"
  state_set_cursor "$state_file" "$target_index"

  # Mark the other branch target as "skipped"
  local other_target_id
  if [[ "$cond_exit" -eq 0 ]]; then
    other_target_id=$(printf '%s\n' "$step_json" | jq -r '.if_nonzero // empty')
  else
    other_target_id=$(printf '%s\n' "$step_json" | jq -r '.if_zero // empty')
  fi
  if [[ -n "$other_target_id" ]]; then
    local other_index
    other_index=$(workflow_get_step_index "$workflow_json" "$other_target_id") || true
    if [[ -n "$other_index" ]]; then
      state_set_step_status "$state_file" "$other_index" "skipped"
    fi
  fi

  # Record the branch decision in command log for auditability
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  state_append_command_log "$state_file" "$step_index" "branch: condition='${condition}' exit=${cond_exit} target=${target_id}" "$cond_exit" "$now"

  # Chain into the target step so the workflow doesn't stall
  local target_step_json
  target_step_json=$(printf '%s\n' "$workflow_json" | jq --argjson idx "$target_index" '.steps[$idx]')
  dispatch_step "$target_step_json" "stop" "$WHEEL_HOOK_INPUT" "$state_file" "$target_index"
}

# FR-025/026: Handle a loop step — evaluate condition, repeat or advance
# Params: $1 = step JSON, $2 = state file path, $3 = step index, $4 = workflow JSON
# Output (stdout): JSON hook response (if substep is agent type)
# Exit: 0 on success/continue, 1 on exhaustion+fail
dispatch_loop() {
  local step_json="$1"
  local state_file="$2"
  local step_index="$3"
  local workflow_json="$4"

  local state
  state=$(state_read "$state_file") || return 1
  local step_status
  step_status=$(state_get_step_status "$state" "$step_index")

  if [[ "$step_status" == "pending" ]]; then
    state_set_step_status "$state_file" "$step_index" "working"
  fi

  local max_iterations
  max_iterations=$(printf '%s\n' "$step_json" | jq -r '.max_iterations // 10')
  local on_exhaustion
  on_exhaustion=$(printf '%s\n' "$step_json" | jq -r '.on_exhaustion // "fail"')
  local condition
  condition=$(printf '%s\n' "$step_json" | jq -r '.condition // empty')

  # Get current iteration count
  state=$(state_read "$state_file") || return 1
  local current_iteration
  current_iteration=$(printf '%s\n' "$state" | jq --argjson idx "$step_index" '.steps[$idx].loop_iteration // 0')

  # Check max iterations
  if [[ "$current_iteration" -ge "$max_iterations" ]]; then
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    state_append_command_log "$state_file" "$step_index" "loop: exhausted after ${current_iteration} iterations" 1 "$now"
    if [[ "$on_exhaustion" == "continue" ]]; then
      state_set_step_status "$state_file" "$step_index" "done"
      local next_index=$((step_index + 1))
      state_set_cursor "$state_file" "$next_index"
      # Chain into next step so workflow doesn't stall
      local total_steps
      total_steps=$(printf '%s\n' "$workflow_json" | jq '.steps | length')
      if [[ "$next_index" -lt "$total_steps" ]]; then
        local next_step_json
        next_step_json=$(printf '%s\n' "$workflow_json" | jq --argjson idx "$next_index" '.steps[$idx]')
        dispatch_step "$next_step_json" "stop" "$WHEEL_HOOK_INPUT" "$state_file" "$next_index"
        return $?
      fi
      jq -n '{"decision": "approve"}'
      return 0
    else
      state_set_step_status "$state_file" "$step_index" "failed"
      # Update workflow status to failed
      state=$(state_read "$state_file") || return 1
      local updated
      updated=$(printf '%s\n' "$state" | jq '.status = "failed"')
      state_write "$state_file" "$updated"
      jq -n '{"decision": "approve"}'
      return 1
    fi
  fi

  # Evaluate condition (if it succeeds, the loop exits)
  if [[ -n "$condition" ]]; then
    local cond_exit=0
    eval "$condition" >/dev/null 2>&1 || cond_exit=$?
    if [[ "$cond_exit" -eq 0 ]]; then
      # Condition met — loop exits, advance
      local now
      now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
      state_append_command_log "$state_file" "$step_index" "loop: condition met at iteration ${current_iteration}" 0 "$now"
      state_set_step_status "$state_file" "$step_index" "done"
      local next_index=$((step_index + 1))
      state_set_cursor "$state_file" "$next_index"
      # Chain into next step so workflow doesn't stall
      local total_steps
      total_steps=$(printf '%s\n' "$workflow_json" | jq '.steps | length')
      if [[ "$next_index" -lt "$total_steps" ]]; then
        local next_step_json
        next_step_json=$(printf '%s\n' "$workflow_json" | jq --argjson idx "$next_index" '.steps[$idx]')
        dispatch_step "$next_step_json" "stop" "$WHEEL_HOOK_INPUT" "$state_file" "$next_index"
        return $?
      fi
      jq -n '{"decision": "approve"}'
      return 0
    fi
  fi

  # Increment iteration counter
  state=$(state_read "$state_file") || return 1
  local updated
  updated=$(printf '%s\n' "$state" | jq --argjson idx "$step_index" --argjson iter "$((current_iteration + 1))" \
    '.steps[$idx].loop_iteration = $iter')
  state_write "$state_file" "$updated"

  # Execute substep
  local substep
  substep=$(printf '%s\n' "$step_json" | jq '.substep // empty')
  if [[ -z "$substep" || "$substep" == "null" ]]; then
    echo "ERROR: loop step missing 'substep' field" >&2
    state_set_step_status "$state_file" "$step_index" "failed"
    return 1
  fi

  local substep_type
  substep_type=$(printf '%s\n' "$substep" | jq -r '.type')

  case "$substep_type" in
    command)
      # Execute the command substep directly
      local command
      command=$(printf '%s\n' "$substep" | jq -r '.command // empty')
      local output
      local cmd_exit_code
      output=$(eval "$command" 2>&1) || true
      cmd_exit_code=${PIPESTATUS[0]:-$?}
      local now
      now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
      state_append_command_log "$state_file" "$step_index" "$command" "$cmd_exit_code" "$now"

      # After substep execution, re-dispatch the loop to check condition again
      if [[ -n "$WHEEL_HOOK_SCRIPT" && -x "$WHEEL_HOOK_SCRIPT" ]]; then
        exec "$WHEEL_HOOK_SCRIPT" <<< "$WHEEL_HOOK_INPUT"
      fi
      # Fallback: direct re-dispatch (e.g., during kickstart)
      dispatch_loop "$step_json" "$state_file" "$step_index" "$workflow_json"
      return $?
      ;;
    agent)
      # Return instruction for the agent substep
      local instruction
      instruction=$(printf '%s\n' "$substep" | jq -r '.instruction // empty')
      jq -n --arg msg "Loop iteration $((current_iteration + 1))/${max_iterations}: ${instruction}" \
        '{"decision": "block", "reason": $msg}'
      ;;
    *)
      echo "ERROR: unsupported substep type: $substep_type" >&2
      return 1
      ;;
  esac
}

# FR-001/FR-002/FR-003/FR-004: Handle a team-create step
# Creates a Claude Code agent team. On stop hook when pending: injects instruction
# for orchestrator to call TeamCreate. On post_tool_use: detects TeamCreate completion,
# records team in state, marks done, advances cursor.
# Params: $1 = step_json, $2 = hook_type, $3 = hook_input_json, $4 = state_file, $5 = step_index
# Output (stdout): JSON hook response
# Exit: 0
dispatch_team_create() {
  local step_json="$1"
  local hook_type="$2"
  local hook_input_json="$3"
  local state_file="$4"
  local step_index="$5"

  local state
  state=$(state_read "$state_file") || return 1
  local step_status
  step_status=$(state_get_step_status "$state" "$step_index")

  local step_id
  step_id=$(printf '%s\n' "$step_json" | jq -r '.id')

  # FR-002: Resolve team name — explicit or auto-generated
  local team_name
  team_name=$(printf '%s\n' "$step_json" | jq -r '.team_name // empty')
  if [[ -z "$team_name" ]]; then
    local wf_name
    wf_name=$(printf '%s\n' "$state" | jq -r '.workflow_name // "workflow"')
    team_name="${wf_name}-${step_id}"
  fi

  case "$hook_type" in
    stop)
      if [[ "$step_status" == "pending" ]]; then
        # FR-003: Check if team already exists in state (idempotent)
        local existing_team
        existing_team=$(printf '%s\n' "$state" | jq -r --arg sid "$step_id" '.teams[$sid].team_name // empty')
        if [[ -n "$existing_team" ]]; then
          # Team already recorded — mark done and advance
          state_set_step_status "$state_file" "$step_index" "done"
          # Advance cursor
          local raw_next
          raw_next=$(resolve_next_index "$step_json" "$step_index" "$WORKFLOW") || return 1
          local next_index
          next_index=$(advance_past_skipped "$state_file" "$raw_next" "$WORKFLOW")
          state_set_cursor "$state_file" "$next_index"
          local total_steps
          total_steps=$(printf '%s\n' "$WORKFLOW" | jq '.steps | length')
          if [[ "$next_index" -lt "$total_steps" ]]; then
            local next_step_json
            next_step_json=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$next_index" '.steps[$idx]')
            dispatch_step "$next_step_json" "stop" "$hook_input_json" "$state_file" "$next_index"
          else
            jq -n '{"decision": "approve"}'
          fi
          return 0
        fi
        state_set_step_status "$state_file" "$step_index" "working"
        # Inject instruction for orchestrator to call TeamCreate
        jq -n --arg team "$team_name" \
          '{"decision": "block", "reason": ("Create an agent team by calling TeamCreate with team_name: " + $team + ". After creating, proceed with the next tool call so I can detect completion.")}'
      elif [[ "$step_status" == "working" ]]; then
        # Waiting for TeamCreate — remind
        jq -n --arg team "$team_name" \
          '{"decision": "block", "reason": ("Still waiting for TeamCreate to be called for team: " + $team + ". Call TeamCreate now.")}'
      else
        jq -n '{"decision": "approve"}'
      fi
      ;;
    post_tool_use)
      if [[ "$step_status" == "working" ]]; then
        # Detect TeamCreate completion
        local tool_name
        tool_name=$(printf '%s\n' "$hook_input_json" | jq -r '.tool_name // empty')
        if [[ "$tool_name" == "TeamCreate" ]]; then
          # FR-004: Record team in state
          state_set_team "$state_file" "$step_id" "$team_name"
          state_set_step_status "$state_file" "$step_index" "done"
          # Handle terminal step
          if handle_terminal_step "$state_file" "$step_json"; then
            jq -n '{"hookEventName": "PostToolUse"}'
            return 0
          fi
          # Advance cursor
          local raw_next
          raw_next=$(resolve_next_index "$step_json" "$step_index" "$WORKFLOW") || return 1
          local next_index
          next_index=$(advance_past_skipped "$state_file" "$raw_next" "$WORKFLOW")
          state_set_cursor "$state_file" "$next_index"
          # Chain into auto-executable next steps
          local total_steps
          total_steps=$(printf '%s\n' "$WORKFLOW" | jq '.steps | length')
          if [[ "$next_index" -lt "$total_steps" ]]; then
            local next_step_json
            next_step_json=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$next_index" '.steps[$idx]')
            local next_step_type
            next_step_type=$(printf '%s\n' "$next_step_json" | jq -r '.type')
            if [[ "$next_step_type" == "command" || "$next_step_type" == "loop" || "$next_step_type" == "branch" ]]; then
              export WHEEL_HOOK_SCRIPT=""
              export WHEEL_HOOK_INPUT='{}'
              dispatch_step "$next_step_json" "stop" '{}' "$state_file" "$next_index" >/dev/null 2>&1
            fi
          fi
        fi
      fi
      jq -n '{"hookEventName": "PostToolUse"}'
      ;;
    *)
      jq -n '{"decision": "approve"}'
      ;;
  esac
}

# FR-005/FR-006/FR-007/FR-008/FR-009/FR-010/FR-011/FR-012/FR-013/FR-014:
# Handle a teammate step — spawn agent(s) to run sub-workflows in parallel.
# Static path: spawns a single agent with the step's assign payload.
# Dynamic path (loop_from): reads JSON array from referenced step, spawns one agent
# per entry (capped by max_agents, distributed round-robin).
# Fire-and-forget: marks done immediately after injecting spawn instructions.
# Params: $1 = step_json, $2 = hook_type, $3 = hook_input_json, $4 = state_file, $5 = step_index
# Output (stdout): JSON hook response
# Exit: 0
dispatch_teammate() {
  local step_json="$1"
  local hook_type="$2"
  local hook_input_json="$3"
  local state_file="$4"
  local step_index="$5"

  local state
  state=$(state_read "$state_file") || return 1
  local step_status
  step_status=$(state_get_step_status "$state" "$step_index")

  local step_id
  step_id=$(printf '%s\n' "$step_json" | jq -r '.id')

  case "$hook_type" in
    stop)
      if [[ "$step_status" == "pending" ]]; then
        state_set_step_status "$state_file" "$step_index" "working"

        # Resolve team name from state via team field
        local team_ref
        team_ref=$(printf '%s\n' "$step_json" | jq -r '.team // empty')
        local team_name
        team_name=$(printf '%s\n' "$state" | jq -r --arg tid "$team_ref" '.teams[$tid].team_name // empty')
        if [[ -z "$team_name" ]]; then
          echo "ERROR: teammate step '$step_id' references unknown team: $team_ref" >&2
          state_set_step_status "$state_file" "$step_index" "failed"
          return 1
        fi

        # Resolve sub-workflow name
        local sub_workflow
        sub_workflow=$(printf '%s\n' "$step_json" | jq -r '.workflow // empty')

        # FR-029/FR-030: Read context_from and assign
        local context_from_json
        context_from_json=$(printf '%s\n' "$step_json" | jq -c '.context_from // []')
        local assign_json
        assign_json=$(printf '%s\n' "$step_json" | jq -c '.assign // {}')

        # Check for loop_from (dynamic spawning)
        local loop_from
        loop_from=$(printf '%s\n' "$step_json" | jq -r '.loop_from // empty')

        if [[ -n "$loop_from" ]]; then
          # FR-011/FR-012/FR-013/FR-014: Dynamic spawning path
          local loop_step_index
          loop_step_index=$(printf '%s\n' "$WORKFLOW" | jq --arg id "$loop_from" '[.steps[].id] | index($id)')
          if [[ "$loop_step_index" == "null" || -z "$loop_step_index" ]]; then
            echo "ERROR: teammate step '$step_id': loop_from references unknown step: $loop_from" >&2
            state_set_step_status "$state_file" "$step_index" "failed"
            return 1
          fi
          local loop_output
          loop_output=$(printf '%s\n' "$state" | jq -r --argjson idx "$loop_step_index" '.steps[$idx].output // empty')

          if [[ -z "$loop_output" ]]; then
            echo "ERROR: teammate step '$step_id': loop_from step '$loop_from' has no output" >&2
            state_set_step_status "$state_file" "$step_index" "failed"
            return 1
          fi
          if [[ -f "$loop_output" ]]; then
            loop_output=$(cat "$loop_output")
          fi
          local is_array
          is_array=$(printf '%s\n' "$loop_output" | jq -e 'type == "array"' 2>/dev/null || echo "false")
          if [[ "$is_array" != "true" ]]; then
            echo "ERROR: teammate step '$step_id': loop_from output is not a JSON array" >&2
            state_set_step_status "$state_file" "$step_index" "failed"
            return 1
          fi

          local item_count
          item_count=$(printf '%s\n' "$loop_output" | jq 'length')

          # FR-023 edge case: empty array — spawn 0 agents, mark done immediately
          if [[ "$item_count" -eq 0 ]]; then
            state_set_step_status "$state_file" "$step_index" "done"
            _teammate_chain_next "$step_json" "$step_index" "$hook_input_json" "$state_file"
            return $?
          fi

          # FR-013: Apply max_agents cap (default 5)
          local max_agents
          max_agents=$(printf '%s\n' "$step_json" | jq -r '.max_agents // empty')
          if [[ -z "$max_agents" || "$max_agents" -le 0 ]] 2>/dev/null; then
            max_agents=5
          fi
          local agent_count="$max_agents"
          if [[ "$item_count" -lt "$agent_count" ]]; then
            agent_count="$item_count"
          fi

          # FR-013: Distribute items round-robin across agents
          local base_name
          base_name=$(printf '%s\n' "$step_json" | jq -r '.name // empty')
          if [[ -z "$base_name" ]]; then
            base_name="$step_id"
          fi

          local i
          for ((i=0; i<agent_count; i++)); do
            local agent_name="${base_name}-${i}"
            local output_dir=".wheel/outputs/team-${team_name}/${agent_name}"
            rm -rf "$output_dir"
            mkdir -p "$output_dir"

            local agent_assign
            agent_assign=$(printf '%s\n' "$loop_output" | jq -c --argjson idx "$i" --argjson cnt "$agent_count" \
              '[to_entries[] | select(.key % $cnt == $idx) | .value]')

            context_write_teammate_files "$output_dir" "$state" "$WORKFLOW" "$context_from_json" "$agent_assign"

            state_add_teammate "$state_file" "$team_ref" "$agent_name" "" "" "$output_dir" "$agent_assign"
          done

          # FR-008: Fire-and-forget — mark done, chain to next step
          state_set_step_status "$state_file" "$step_index" "done"
          _teammate_chain_next "$step_json" "$step_index" "$hook_input_json" "$state_file" "$team_ref" "$sub_workflow"
          return $?
        else
          # Static teammate spawning path (FR-005/FR-006/FR-009)
          local agent_name
          agent_name=$(printf '%s\n' "$step_json" | jq -r '.name // empty')
          if [[ -z "$agent_name" ]]; then
            agent_name="$step_id"
          fi

          local output_dir=".wheel/outputs/team-${team_name}/${agent_name}"
          rm -rf "$output_dir"
          mkdir -p "$output_dir"

          context_write_teammate_files "$output_dir" "$state" "$WORKFLOW" "$context_from_json" "$assign_json"
          state_add_teammate "$state_file" "$team_ref" "$agent_name" "" "" "$output_dir" "$assign_json"

          # FR-008: Fire-and-forget — mark done, chain to next step
          state_set_step_status "$state_file" "$step_index" "done"
          _teammate_chain_next "$step_json" "$step_index" "$hook_input_json" "$state_file" "$team_ref" "$sub_workflow"
          return $?
        fi
      elif [[ "$step_status" == "working" || "$step_status" == "done" ]]; then
        # Already processed — chain forward
        jq -n '{"decision": "approve"}'
      else
        jq -n '{"decision": "approve"}'
      fi
      ;;
    post_tool_use)
      # FR-008: Fire-and-forget — detect Agent/TaskCreate calls to update teammate IDs
      if [[ "$step_status" == "done" || "$step_status" == "working" ]]; then
        local tool_name
        tool_name=$(printf '%s\n' "$hook_input_json" | jq -r '.tool_name // empty')
        if [[ "$tool_name" == "TaskCreate" ]]; then
          local task_subject
          task_subject=$(printf '%s\n' "$hook_input_json" | jq -r '.tool_input.subject // empty')
          local team_ref
          team_ref=$(printf '%s\n' "$step_json" | jq -r '.team // empty')
          if [[ -n "$task_subject" && -n "$team_ref" ]]; then
            local task_id
            task_id=$(printf '%s\n' "$hook_input_json" | jq -r '.tool_result.taskId // .tool_result.id // empty')
            if [[ -n "$task_id" ]]; then
              local teammates_json
              teammates_json=$(state_read "$state_file" | jq -c --arg tid "$team_ref" '.teams[$tid].teammates // {}') 2>/dev/null
              local matched_name
              matched_name=$(printf '%s\n' "$teammates_json" | jq -r --arg subj "$task_subject" \
                'to_entries[] | select(.key == $subj or (.key | contains($subj)) or ($subj | contains(.key))) | .key' | head -1)
              if [[ -n "$matched_name" ]]; then
                local cur_state
                cur_state=$(state_read "$state_file") || true
                local now
                now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
                local updated
                updated=$(printf '%s\n' "$cur_state" | jq \
                  --arg tid "$team_ref" --arg name "$matched_name" --arg taskid "$task_id" --arg now "$now" \
                  '.teams[$tid].teammates[$name].task_id = $taskid | .updated_at = $now')
                state_write "$state_file" "$updated"
              fi
            fi
          fi
        fi
      fi
      jq -n '{"hookEventName": "PostToolUse"}'
      ;;
    *)
      jq -n '{"decision": "approve"}'
      ;;
  esac
}

# Internal helper: Chain from a completed teammate step to the next step.
# If the next step is another teammate, dispatches it directly (no block).
# If the next step is NOT a teammate, reads all registered teammates from state
# and emits a single block with spawn instructions for all of them.
# Params: $1=step_json $2=step_index $3=hook_input_json $4=state_file $5=team_ref $6=sub_workflow
_teammate_chain_next() {
  local step_json="$1"
  local step_index="$2"
  local hook_input_json="$3"
  local state_file="$4"
  local team_ref="$5"
  local sub_workflow="$6"

  local raw_next
  raw_next=$(resolve_next_index "$step_json" "$step_index" "$WORKFLOW") || return 1
  local next_index
  next_index=$(advance_past_skipped "$state_file" "$raw_next" "$WORKFLOW")
  state_set_cursor "$state_file" "$next_index"

  local total_steps
  total_steps=$(printf '%s\n' "$WORKFLOW" | jq '.steps | length')
  if [[ "$next_index" -ge "$total_steps" ]]; then
    _teammate_flush_from_state "$state_file" "$team_ref" "$sub_workflow"
    return $?
  fi

  local next_step_json
  next_step_json=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$next_index" '.steps[$idx]')
  local next_type
  next_type=$(printf '%s\n' "$next_step_json" | jq -r '.type')

  if [[ "$next_type" == "teammate" ]]; then
    # Next step is also a teammate — chain directly (no block)
    dispatch_step "$next_step_json" "stop" "$hook_input_json" "$state_file" "$next_index"
  else
    # Next step is NOT a teammate — emit spawn instructions for all registered teammates
    _teammate_flush_from_state "$state_file" "$team_ref" "$sub_workflow"
  fi
}

# Internal helper: Read all registered teammates from state and emit a single
# block with spawn instructions. No temp files — reads directly from state.
# Params: $1=state_file $2=team_ref $3=default_sub_workflow
_teammate_flush_from_state() {
  local state_file="$1"
  local team_ref="$2"
  local default_sub_workflow="$3"

  local state
  state=$(state_read "$state_file") || return 1

  local team_name
  team_name=$(printf '%s\n' "$state" | jq -r --arg tid "$team_ref" '.teams[$tid].team_name // "unknown"')

  local teammates_json
  teammates_json=$(printf '%s\n' "$state" | jq -c --arg tid "$team_ref" '.teams[$tid].teammates // {}')

  local count
  count=$(printf '%s\n' "$teammates_json" | jq 'length')
  if [[ "$count" -eq 0 ]]; then
    jq -n '{"decision": "approve"}'
    return 0
  fi

  # Build spawn list from state — each teammate has output_dir recorded
  # Resolve sub-workflow from the teammate steps in the workflow definition
  local spawn_list=""
  local names
  names=$(printf '%s\n' "$teammates_json" | jq -r 'keys[]')
  while IFS= read -r agent_name; do
    [[ -z "$agent_name" ]] && continue
    local outdir
    outdir=$(printf '%s\n' "$teammates_json" | jq -r --arg n "$agent_name" '.[$n].output_dir // empty')

    # Find the sub-workflow for this teammate from the workflow steps
    local wf
    wf=$(printf '%s\n' "$WORKFLOW" | jq -r --arg aid "$agent_name" \
      '[.steps[] | select(.type == "teammate" and (.id == $aid or .name == $aid))] | .[0].workflow // empty')
    if [[ -z "$wf" ]]; then
      wf="$default_sub_workflow"
    fi

    spawn_list="${spawn_list}
- Agent '${agent_name}' on team '${team_name}': MUST run /wheel-run ${wf} first. Assignment: ${outdir}/assignment.json, Context: ${outdir}/context.json, Output to: ${outdir}/"
  done <<< "$names"

  jq -n --arg msg "Spawn ${count} teammate agent(s) with run_in_background: true and mode: bypassPermissions. Each agent MUST run /wheel-run <workflow> to activate its sub-workflow.${spawn_list}

Spawn ALL agents in parallel (single message with multiple Agent tool calls). Create a TaskCreate entry for each. After spawning all, proceed — the team-wait step will handle completion tracking." \
    '{"decision": "block", "reason": $msg}'
}

# FR-015/FR-016/FR-017/FR-018/FR-019/FR-022:
# Handle a team-wait step — blocks the parent workflow until all teammates complete.
# On stop hook when pending: marks working. On each stop hook while working: reads
# teammate statuses from state. If all done/failed: writes summary, copies outputs
# if collect_to set, marks done, advances cursor. If not all done: returns block
# with progress status.
# Params: $1 = step_json, $2 = hook_type, $3 = hook_input_json, $4 = state_file, $5 = step_index
# Output (stdout): JSON hook response
# Exit: 0
dispatch_team_wait() {
  local step_json="$1"
  local hook_type="$2"
  local hook_input_json="$3"
  local state_file="$4"
  local step_index="$5"

  local state
  state=$(state_read "$state_file") || return 1
  local step_status
  step_status=$(state_get_step_status "$state" "$step_index")

  local step_id
  step_id=$(printf '%s\n' "$step_json" | jq -r '.id')

  # Resolve team reference
  local team_ref
  team_ref=$(printf '%s\n' "$step_json" | jq -r '.team // empty')

  case "$hook_type" in
    stop)
      if [[ "$step_status" == "pending" ]]; then
        state_set_step_status "$state_file" "$step_index" "working"
        state=$(state_read "$state_file") || return 1
      fi

      if [[ "$step_status" == "pending" || "$step_status" == "working" ]]; then
        # FR-017: Check teammate statuses
        local teammates_json
        teammates_json=$(printf '%s\n' "$state" | jq -c --arg tid "$team_ref" '.teams[$tid].teammates // {}')

        local total completed failed
        total=$(printf '%s\n' "$teammates_json" | jq 'length')
        completed=$(printf '%s\n' "$teammates_json" | jq '[.[] | select(.status == "completed")] | length')
        failed=$(printf '%s\n' "$teammates_json" | jq '[.[] | select(.status == "failed")] | length')

        local done_count=$((completed + failed))

        # FR-022 edge case: 0 teammates — immediately complete
        if [[ "$total" -eq 0 ]]; then
          _team_wait_complete "$step_json" "$state_file" "$step_index" "$team_ref" "$hook_input_json"
          return $?
        fi

        if [[ "$done_count" -ge "$total" ]]; then
          _team_wait_complete "$step_json" "$state_file" "$step_index" "$team_ref" "$hook_input_json"
          return $?
        fi

        # Not all done — approve so the lead goes idle and waits.
        # Lead wakes up when teammates send messages back.
        jq -n '{"decision": "approve"}'
      else
        jq -n '{"decision": "approve"}'
      fi
      ;;
    post_tool_use)
      # Capture agent_id even when pending — Agent spawns happen before Stop transitions to working
      local tool_name
      tool_name=$(printf '%s\n' "$hook_input_json" | jq -r '.tool_name // empty')

      if [[ "$tool_name" == "Agent" ]]; then
        local spawned_name
        spawned_name=$(printf '%s\n' "$hook_input_json" | jq -r '.tool_input.name // empty')
        if [[ -n "$spawned_name" ]]; then
          local cur_state
          cur_state=$(state_read "$state_file") || true
          local has_teammate
          has_teammate=$(printf '%s\n' "$cur_state" | jq -r --arg tid "$team_ref" --arg n "$spawned_name" \
            '.teams[$tid].teammates[$n] // empty')
          if [[ -n "$has_teammate" ]]; then
            # Construct agent_id from name@team_name — don't rely on tool_result
            # which may not be a structured JSON object in PostToolUse hook input
            local team_name_resolved
            team_name_resolved=$(printf '%s\n' "$cur_state" | jq -r --arg tid "$team_ref" '.teams[$tid].team_name // empty')
            local spawned_aid="${spawned_name}@${team_name_resolved}"
            local now
            now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
            local updated
            updated=$(printf '%s\n' "$cur_state" | jq \
              --arg tid "$team_ref" --arg n "$spawned_name" --arg aid "$spawned_aid" --arg now "$now" \
              '.teams[$tid].teammates[$n].agent_id = $aid | .teams[$tid].teammates[$n].status = "running" | .teams[$tid].teammates[$n].started_at = $now | .updated_at = $now')
            state_write "$state_file" "$updated"
          fi
        fi
      fi

      # Detect TaskUpdate marking a teammate's task completed
      if [[ "$tool_name" == "TaskUpdate" ]]; then
        local task_status
        task_status=$(printf '%s\n' "$hook_input_json" | jq -r '.tool_input.status // empty')
        if [[ "$task_status" == "completed" ]]; then
          local task_subject
          task_subject=$(printf '%s\n' "$hook_input_json" | jq -r '.tool_input.subject // empty')
          # Also try to get the task subject from tool_result if not in input
          if [[ -z "$task_subject" ]]; then
            task_subject=$(printf '%s\n' "$hook_input_json" | jq -r '.tool_result.subject // empty')
          fi
          # Match task subject/id to a teammate name
          local cur_state
          cur_state=$(state_read "$state_file") || true
          local teammate_names
          teammate_names=$(printf '%s\n' "$cur_state" | jq -r --arg tid "$team_ref" '.teams[$tid].teammates // {} | keys[]')
          while IFS= read -r tname; do
            [[ -z "$tname" ]] && continue
            # Match by name appearing in subject, or exact match
            if [[ "$task_subject" == *"$tname"* || "$tname" == *"$task_subject"* ]]; then
              state_update_teammate_status "$state_file" "$team_ref" "$tname" "completed"
              break
            fi
          done <<< "$teammate_names"
        fi
      fi

      # Check if all teammates are now done
      if [[ "$step_status" == "pending" || "$step_status" == "working" ]]; then
        state=$(state_read "$state_file") || return 1
        local teammates_json
        teammates_json=$(printf '%s\n' "$state" | jq -c --arg tid "$team_ref" '.teams[$tid].teammates // {}')
        local total
        total=$(printf '%s\n' "$teammates_json" | jq 'length')
        local completed failed done_count
        completed=$(printf '%s\n' "$teammates_json" | jq '[.[] | select(.status == "completed")] | length')
        failed=$(printf '%s\n' "$teammates_json" | jq '[.[] | select(.status == "failed")] | length')
        done_count=$((completed + failed))

        if [[ "$total" -gt 0 && "$done_count" -ge "$total" ]]; then
          _team_wait_complete "$step_json" "$state_file" "$step_index" "$team_ref" "$hook_input_json"
          return $?
        fi
      fi
      jq -n '{"hookEventName": "PostToolUse"}'
      ;;
    subagent_stop)
      # A teammate agent stopped — mark it completed, check if all done
      local stopped_name
      stopped_name=$(printf '%s\n' "$hook_input_json" | jq -r '.name // .teammate_name // empty')
      if [[ -z "$stopped_name" ]]; then
        stopped_name=$(printf '%s\n' "$hook_input_json" | jq -r '.agent_id // empty')
        # Try to match agent_id to a teammate name
        if [[ -n "$stopped_name" ]]; then
          local match
          match=$(printf '%s\n' "$state" | jq -r --arg tid "$team_ref" --arg aid "$stopped_name" \
            '.teams[$tid].teammates // {} | to_entries[] | select(.value.agent_id == $aid) | .key' | head -1)
          [[ -n "$match" ]] && stopped_name="$match"
        fi
      fi

      if [[ -n "$stopped_name" ]]; then
        local tm_status
        tm_status=$(printf '%s\n' "$state" | jq -r --arg tid "$team_ref" --arg n "$stopped_name" \
          '.teams[$tid].teammates[$n].status // empty')
        if [[ -n "$tm_status" && "$tm_status" != "completed" && "$tm_status" != "failed" ]]; then
          state_update_teammate_status "$state_file" "$team_ref" "$stopped_name" "completed"
        fi
      fi

      # Check if all teammates are now done
      state=$(state_read "$state_file") || return 1
      local teammates_json
      teammates_json=$(printf '%s\n' "$state" | jq -c --arg tid "$team_ref" '.teams[$tid].teammates // {}')
      local total completed failed done_count
      total=$(printf '%s\n' "$teammates_json" | jq 'length')
      completed=$(printf '%s\n' "$teammates_json" | jq '[.[] | select(.status == "completed")] | length')
      failed=$(printf '%s\n' "$teammates_json" | jq '[.[] | select(.status == "failed")] | length')
      done_count=$((completed + failed))

      if [[ "$total" -gt 0 && "$done_count" -ge "$total" ]]; then
        _team_wait_complete "$step_json" "$state_file" "$step_index" "$team_ref" "$hook_input_json"
        return $?
      fi
      jq -n '{"decision": "approve"}'
      ;;
    teammate_idle)
      # Teammate went idle. Check if their sub-workflow state file was archived
      # (terminal step completed) — if so, mark them completed in the parent.
      # TeammateIdle hook input has teammate_name (not agent_id).
      local idle_name
      idle_name=$(printf '%s\n' "$hook_input_json" | jq -r '.teammate_name // empty')
      local idle_agent_id
      idle_agent_id=$(printf '%s\n' "$hook_input_json" | jq -r '.agent_id // empty')

      if [[ -n "$idle_name" ]]; then
        # Check if this teammate's sub-workflow state file still exists
        # Construct team-format ID if not already in hook input
        if [[ -z "$idle_agent_id" || "$idle_agent_id" != *"@"* ]]; then
          local _tname
          _tname=$(printf '%s\n' "$hook_input_json" | jq -r '.team_name // empty')
          [[ -n "$_tname" ]] && idle_agent_id="${idle_name}@${_tname}"
        fi

        local _found_state=false
        if [[ -n "$idle_agent_id" ]]; then
          local _sf
          for _sf in .wheel/state_*.json; do
            [[ -f "$_sf" ]] || continue
            local _alt
            _alt=$(jq -r '.alternate_agent_id // empty' "$_sf" 2>/dev/null) || continue
            if [[ "$_alt" == "$idle_agent_id" ]]; then
              _found_state=true
              break
            fi
          done
        fi

        if [[ "$_found_state" == false ]]; then
          # Sub-workflow state archived — teammate is done
          local tm_st
          tm_st=$(printf '%s\n' "$state" | jq -r --arg tid "$team_ref" --arg n "$idle_name" \
            '.teams[$tid].teammates[$n].status // empty')
          if [[ -n "$tm_st" && "$tm_st" != "completed" && "$tm_st" != "failed" ]]; then
            state_update_teammate_status "$state_file" "$team_ref" "$idle_name" "completed"
          fi
          # Check if all teammates done
          state=$(state_read "$state_file") || return 1
          local teammates_json
          teammates_json=$(printf '%s\n' "$state" | jq -c --arg tid "$team_ref" '.teams[$tid].teammates // {}')
          local total completed failed done_count
          total=$(printf '%s\n' "$teammates_json" | jq 'length')
          completed=$(printf '%s\n' "$teammates_json" | jq '[.[] | select(.status == "completed")] | length')
          failed=$(printf '%s\n' "$teammates_json" | jq '[.[] | select(.status == "failed")] | length')
          done_count=$((completed + failed))
          if [[ "$total" -gt 0 && "$done_count" -ge "$total" ]]; then
            _team_wait_complete "$step_json" "$state_file" "$step_index" "$team_ref" "$hook_input_json"
            return $?
          fi
        fi
      fi
      jq -n '{"decision": "approve"}'
      ;;
    *)
      jq -n '{"decision": "approve"}'
      ;;
  esac
}

# FR-018/FR-019: Internal helper — finalize team-wait step
# Writes summary, copies outputs if collect_to set, marks done, advances cursor.
# Params: $1 = step_json, $2 = state_file, $3 = step_index, $4 = team_ref, $5 = hook_input_json
# Output (stdout): JSON hook response
# Exit: 0
_team_wait_complete() {
  local step_json="$1"
  local state_file="$2"
  local step_index="$3"
  local team_ref="$4"
  local hook_input_json="$5"

  local state
  state=$(state_read "$state_file") || return 1

  local team_name
  team_name=$(printf '%s\n' "$state" | jq -r --arg tid "$team_ref" '.teams[$tid].team_name // "unknown"')
  local teammates_json
  teammates_json=$(printf '%s\n' "$state" | jq -c --arg tid "$team_ref" '.teams[$tid].teammates // {}')

  local total completed failed
  total=$(printf '%s\n' "$teammates_json" | jq 'length')
  completed=$(printf '%s\n' "$teammates_json" | jq '[.[] | select(.status == "completed")] | length')
  failed=$(printf '%s\n' "$teammates_json" | jq '[.[] | select(.status == "failed")] | length')

  # FR-018: Build per-teammate details
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  local teammate_details
  teammate_details=$(printf '%s\n' "$teammates_json" | jq --arg now "$now" '[
    to_entries[] | {
      name: .key,
      status: .value.status,
      output_dir: .value.output_dir,
      duration_seconds: (
        if .value.started_at != null and .value.completed_at != null then
          ((.value.completed_at | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) - (.value.started_at | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601))
        elif .value.started_at != null then
          (($now | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) - (.value.started_at | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601))
        else 0 end
      )
    }
  ]')

  # FR-018: Write summary
  local summary
  summary=$(jq -n \
    --arg team "$team_name" \
    --argjson total "$total" \
    --argjson completed "$completed" \
    --argjson failed "$failed" \
    --argjson teammates "$teammate_details" \
    '{
      team_name: $team,
      total: $total,
      completed: $completed,
      failed: $failed,
      teammates: $teammates
    }')

  # Write summary to output path
  local output_key
  output_key=$(printf '%s\n' "$step_json" | jq -r '.output // empty')
  if [[ -n "$output_key" ]]; then
    mkdir -p "$(dirname "$output_key")"
    printf '%s\n' "$summary" > "$output_key"
    context_capture_output "$state_file" "$step_index" "$output_key"
  else
    # Write to default location
    local summary_path=".wheel/outputs/team-${team_name}/summary.json"
    mkdir -p "$(dirname "$summary_path")"
    printf '%s\n' "$summary" > "$summary_path"
    context_capture_output "$state_file" "$step_index" "$summary_path"
  fi

  # FR-016: Copy outputs to collect_to if set
  local collect_to
  collect_to=$(printf '%s\n' "$step_json" | jq -r '.collect_to // empty')
  if [[ -n "$collect_to" ]]; then
    mkdir -p "$collect_to"
    # Copy each teammate's output directory
    printf '%s\n' "$teammates_json" | jq -r '.[] | .output_dir // empty' | while IFS= read -r out_dir; do
      [[ -z "$out_dir" || ! -d "$out_dir" ]] && continue
      local agent_dir_name
      agent_dir_name=$(basename "$out_dir")
      cp -r "$out_dir" "${collect_to}/${agent_dir_name}" 2>/dev/null || true
    done
  fi

  # FR-019: Mark done (never fails, even with partial results)
  state_set_step_status "$state_file" "$step_index" "done"

  # Handle terminal step
  if handle_terminal_step "$state_file" "$step_json"; then
    jq -n --arg reason "All teammates done — team-wait complete." \
      '{"continue": false, "stopReason": $reason}'
    return 0
  fi

  # Advance cursor
  local raw_next
  raw_next=$(resolve_next_index "$step_json" "$step_index" "$WORKFLOW") || return 1
  local next_index
  next_index=$(advance_past_skipped "$state_file" "$raw_next" "$WORKFLOW")
  state_set_cursor "$state_file" "$next_index"

  # Chain into next step (for state updates) then stop this teammate
  local total_steps
  total_steps=$(printf '%s\n' "$WORKFLOW" | jq '.steps | length')
  if [[ "$next_index" -lt "$total_steps" ]]; then
    local next_step_json
    next_step_json=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$next_index" '.steps[$idx]')
    local next_step_type
    next_step_type=$(printf '%s\n' "$next_step_json" | jq -r '.type')
    # Only chain command steps inline (they execute silently).
    # Other step types (team-delete, agent) are handled by the lead's Stop hook.
    if [[ "$next_step_type" == "command" ]]; then
      dispatch_step "$next_step_json" "stop" "$hook_input_json" "$state_file" "$next_index" >/dev/null 2>&1
    fi
  fi
  jq -n --arg reason "All teammates done — team-wait complete." \
    '{"continue": false, "stopReason": $reason}'
}

# FR-020/FR-021/FR-022/FR-023: Handle a team-delete step
# Gracefully shuts down all agents on a team and cleans up.
# On stop hook when pending: injects instruction to send shutdown to all teammates
# and call TeamDelete. On post_tool_use: detects TeamDelete completion, removes
# team from state, marks done, advances cursor.
# Params: $1 = step_json, $2 = hook_type, $3 = hook_input_json, $4 = state_file, $5 = step_index
# Output (stdout): JSON hook response
# Exit: 0
dispatch_team_delete() {
  local step_json="$1"
  local hook_type="$2"
  local hook_input_json="$3"
  local state_file="$4"
  local step_index="$5"

  local state
  state=$(state_read "$state_file") || return 1
  local step_status
  step_status=$(state_get_step_status "$state" "$step_index")

  local step_id
  step_id=$(printf '%s\n' "$step_json" | jq -r '.id')

  # FR-022: Resolve team reference
  local team_ref
  team_ref=$(printf '%s\n' "$step_json" | jq -r '.team // empty')
  local team_name
  team_name=$(printf '%s\n' "$state" | jq -r --arg tid "$team_ref" '.teams[$tid].team_name // empty')

  case "$hook_type" in
    stop)
      if [[ "$step_status" == "pending" ]]; then
        # FR-019 idempotency: If team doesn't exist in state, it's already been deleted — no-op
        if [[ -z "$team_name" ]]; then
          state_set_step_status "$state_file" "$step_index" "done"
          local raw_next
          raw_next=$(resolve_next_index "$step_json" "$step_index" "$WORKFLOW") || return 1
          local next_index
          next_index=$(advance_past_skipped "$state_file" "$raw_next" "$WORKFLOW")
          state_set_cursor "$state_file" "$next_index"
          local total_steps
          total_steps=$(printf '%s\n' "$WORKFLOW" | jq '.steps | length')
          if [[ "$next_index" -lt "$total_steps" ]]; then
            local next_step_json
            next_step_json=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$next_index" '.steps[$idx]')
            dispatch_step "$next_step_json" "stop" "$hook_input_json" "$state_file" "$next_index"
          else
            jq -n '{"decision": "approve"}'
          fi
          return 0
        fi

        state_set_step_status "$state_file" "$step_index" "working"

        # FR-023: Check if any teammates are still running
        local teammates_json
        teammates_json=$(printf '%s\n' "$state" | jq -c --arg tid "$team_ref" '.teams[$tid].teammates // {}')
        local running_agents
        running_agents=$(printf '%s\n' "$teammates_json" | jq -r '[to_entries[] | select(.value.status == "running" or .value.status == "pending") | .key] | join(", ")')

        local force_msg=""
        if [[ -n "$running_agents" ]]; then
          force_msg=" WARNING: These teammates are still active and must be force-terminated first: ${running_agents}. Send shutdown requests to them before calling TeamDelete."
        fi

        # FR-021: Inject instruction to shut down agents and delete team
        jq -n --arg team "$team_name" --arg force "$force_msg" \
          '{"decision": "block", "reason": ("Delete team '"'"'" + $team + "'"'"'. Send shutdown to all teammates, then call TeamDelete to remove the team." + $force)}'
      elif [[ "$step_status" == "working" ]]; then
        # Waiting for TeamDelete
        jq -n --arg team "$team_name" \
          '{"decision": "block", "reason": ("Still waiting for TeamDelete to be called for team: " + $team + ". Complete the deletion.")}'
      else
        jq -n '{"decision": "approve"}'
      fi
      ;;
    post_tool_use)
      if [[ "$step_status" == "working" ]]; then
        local tool_name
        tool_name=$(printf '%s\n' "$hook_input_json" | jq -r '.tool_name // empty')
        if [[ "$tool_name" == "TeamDelete" ]]; then
          # Remove team from state
          if [[ -n "$team_ref" ]]; then
            state_remove_team "$state_file" "$team_ref"
          fi
          state_set_step_status "$state_file" "$step_index" "done"

          # Handle terminal step
          if handle_terminal_step "$state_file" "$step_json"; then
            jq -n '{"hookEventName": "PostToolUse"}'
            return 0
          fi

          # Advance cursor
          local raw_next
          raw_next=$(resolve_next_index "$step_json" "$step_index" "$WORKFLOW") || return 1
          local next_index
          next_index=$(advance_past_skipped "$state_file" "$raw_next" "$WORKFLOW")
          state_set_cursor "$state_file" "$next_index"

          # Chain into auto-executable next steps
          local total_steps
          total_steps=$(printf '%s\n' "$WORKFLOW" | jq '.steps | length')
          if [[ "$next_index" -lt "$total_steps" ]]; then
            local next_step_json
            next_step_json=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$next_index" '.steps[$idx]')
            local next_step_type
            next_step_type=$(printf '%s\n' "$next_step_json" | jq -r '.type')
            if [[ "$next_step_type" == "command" || "$next_step_type" == "loop" || "$next_step_type" == "branch" ]]; then
              export WHEEL_HOOK_SCRIPT=""
              export WHEEL_HOOK_INPUT='{}'
              dispatch_step "$next_step_json" "stop" '{}' "$state_file" "$next_index" >/dev/null 2>&1
            fi
          fi
        fi
      fi
      jq -n '{"hookEventName": "PostToolUse"}'
      ;;
    *)
      jq -n '{"decision": "approve"}'
      ;;
  esac
}
