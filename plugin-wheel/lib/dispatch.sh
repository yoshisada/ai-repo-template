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
handle_terminal_step() {
  local state_file="$1"
  local step_json="$2"

  local is_terminal
  is_terminal=$(printf '%s\n' "$step_json" | jq -r '.terminal // false')
  if [[ "$is_terminal" != "true" ]]; then
    return 1
  fi

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

  # FR-009: Determine archive subdirectory based on step ID
  local step_id
  step_id=$(printf '%s\n' "$step_json" | jq -r '.id // "unknown"')
  local archive_dir=".wheel/history/success"
  if [[ "$step_id" == *"failure"* ]]; then
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

  case "$hook_type" in
    stop)
      # FR-008: On stop hook, if step is pending, activate child workflow
      if [[ "$step_status" == "pending" ]]; then
        state_set_step_status "$state_file" "$step_index" "working"

        # FR-007: Load child workflow and create child state file
        local child_name
        child_name=$(printf '%s\n' "$step_json" | jq -r '.workflow // empty')
        local child_file="workflows/${child_name}.json"

        local child_json
        child_json=$(workflow_load "$child_file") || return 1

        # Extract parent ownership for child
        local session_id agent_id
        session_id=$(printf '%s\n' "$state" | jq -r '.owner_session_id // empty')
        agent_id=$(printf '%s\n' "$state" | jq -r '.owner_agent_id // empty')

        # FR-016: Create child state file with parent_workflow reference
        local child_unique="child_${child_name}_$(date +%s)_${RANDOM}"
        local child_state_file=".wheel/state_${child_unique}.json"

        state_init "$child_state_file" "$child_json" "$session_id" "$agent_id" "$child_file" "$state_file"

        # FR-015: Kickstart child workflow
        local saved_workflow="$WORKFLOW"
        WORKFLOW="$child_json"
        engine_kickstart "$child_state_file" >/dev/null 2>&1
        WORKFLOW="$saved_workflow"

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
    post_tool_use)
      # No special action needed — fan-in is handled in handle_terminal_step
      jq -n '{"hookEventName": "PostToolUse"}'
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

  case "$hook_type" in
    stop)
      # Gate the orchestrator — inject step instruction
      if [[ "$step_status" == "pending" ]]; then
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
          if handle_terminal_step "$state_file" "$step_json"; then
            jq -n '{"decision": "approve"}'
            return 0
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
        else
          # Output not yet produced — re-inject instruction
          local context
          context=$(context_build "$step_json" "$state" "$WORKFLOW")
          jq -n --arg msg "$context" '{"decision": "block", "reason": $msg}'
        fi
      else
        jq -n '{"decision": "approve"}'
      fi
      ;;
    teammate_idle)
      # Gate agent with its task instruction
      if [[ "$step_status" == "working" ]]; then
        local instruction
        instruction=$(printf '%s\n' "$step_json" | jq -r '.instruction // empty')
        jq -n --arg msg "$instruction" '{"decision": "block", "reason": $msg}'
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
      if handle_terminal_step "$state_file" "$step_json"; then
        jq -n '{"hookEventName": "PostToolUse"}'
        return 0
      fi

      # FR-005: Resolve next index and advance cursor
      local raw_next
      raw_next=$(resolve_next_index "$step_json" "$step_index" "$WORKFLOW") || return 1
      local next_index
      next_index=$(advance_past_skipped "$state_file" "$raw_next" "$WORKFLOW")
      state_set_cursor "$state_file" "$next_index"

      # Chain into auto-executable steps (command/loop/branch) so workflow doesn't stall
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

      jq -n '{"hookEventName": "PostToolUse"}'
      return 0
      ;;
    subagent_stop)
      # Agent finished — mark step done, advance
      state_set_step_status "$state_file" "$step_index" "done"
      # Capture output if step defines an output key
      local output_key
      output_key=$(printf '%s\n' "$step_json" | jq -r '.output // empty')
      if [[ -n "$output_key" ]]; then
        context_capture_output "$state_file" "$step_index" "$output_key"
      fi
      # FR-008: Check for terminal step — archive and end workflow
      if handle_terminal_step "$state_file" "$step_json"; then
        jq -n '{"decision": "approve"}'
        return 0
      fi
      # FR-005: Resolve next index via next field or default to step_index + 1
      local raw_next
      raw_next=$(resolve_next_index "$step_json" "$step_index" "$WORKFLOW") || return 1
      local next_index
      next_index=$(advance_past_skipped "$state_file" "$raw_next" "$WORKFLOW")
      state_set_cursor "$state_file" "$next_index"
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

  # Execute the command and capture output + exit code
  local output
  local cmd_exit_code
  output=$(eval "$command" 2>&1) || true
  cmd_exit_code=${PIPESTATUS[0]:-$?}
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
    context_capture_output "$state_file" "$step_index" "$truncated_output"
    # Write output to the file path so branch conditions and other steps can read it
    mkdir -p "$(dirname "$output_key")"
    printf '%s\n' "$truncated_output" > "$output_key"
  fi

  # Mark step done (or failed if non-zero exit)
  if [[ "$cmd_exit_code" -eq 0 ]]; then
    state_set_step_status "$state_file" "$step_index" "done"
  else
    state_set_step_status "$state_file" "$step_index" "failed"
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
