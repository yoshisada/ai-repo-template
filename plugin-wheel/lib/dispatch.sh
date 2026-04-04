#!/usr/bin/env bash
# dispatch.sh — Step type dispatcher
# FR-003/019/024/025/026: Routes to the correct handler based on step type

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
  step_type=$(echo "$step_json" | jq -r '.type')

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
      fi
      local context
      context=$(context_build "$step_json" "$state" "$WORKFLOW")
      jq -n --arg msg "$context" '{"decision": "block", "reason": $msg}'
      ;;
    teammate_idle)
      # Gate agent with its task instruction
      if [[ "$step_status" == "working" ]]; then
        local instruction
        instruction=$(echo "$step_json" | jq -r '.instruction // empty')
        jq -n --arg msg "$instruction" '{"decision": "block", "reason": $msg}'
      else
        jq -n '{"decision": "approve"}'
      fi
      ;;
    subagent_stop)
      # Agent finished — mark step done, advance
      state_set_step_status "$state_file" "$step_index" "done"
      # Capture output if step defines an output key
      local output_key
      output_key=$(echo "$step_json" | jq -r '.output // empty')
      if [[ -n "$output_key" ]]; then
        context_capture_output "$state_file" "$step_index" "$output_key"
      fi
      # Advance cursor
      local next_index=$((step_index + 1))
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
  command=$(echo "$step_json" | jq -r '.command // empty')
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

  # Record step output
  local output_key
  output_key=$(echo "$step_json" | jq -r '.output // empty')
  if [[ -n "$output_key" ]]; then
    context_capture_output "$state_file" "$step_index" "$truncated_output"
  fi

  # Mark step done (or failed if non-zero exit)
  if [[ "$cmd_exit_code" -eq 0 ]]; then
    state_set_step_status "$state_file" "$step_index" "done"
  else
    state_set_step_status "$state_file" "$step_index" "failed"
  fi

  # Advance cursor
  local next_index=$((step_index + 1))
  state_set_cursor "$state_file" "$next_index"

  # FR-020: Check if next step is also a command — chain via re-exec
  local state
  state=$(state_read "$state_file") || return 0
  local total_steps
  total_steps=$(echo "$WORKFLOW" | jq '.steps | length')
  if [[ "$next_index" -lt "$total_steps" ]]; then
    local next_step_type
    next_step_type=$(echo "$WORKFLOW" | jq -r --argjson idx "$next_index" '.steps[$idx].type')
    if [[ "$next_step_type" == "command" ]]; then
      # Chain: re-exec the hook to handle the next command step without LLM round-trip
      exec "$WHEEL_HOOK_SCRIPT" <<< "$WHEEL_HOOK_INPUT"
    else
      # Next step is not a command — dispatch to its handler (e.g., agent → block with instruction)
      local next_step_json
      next_step_json=$(echo "$WORKFLOW" | jq --argjson idx "$next_index" '.steps[$idx]')
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
        agents=$(echo "$step_json" | jq -r '.agents[]')
        while IFS= read -r agent; do
          [[ -z "$agent" ]] && continue
          state_set_agent_status "$state_file" "$step_index" "$agent" "pending"
        done <<< "$agents"
      fi
      local instruction
      instruction=$(echo "$step_json" | jq -r '.instruction // "Spawn parallel agents for this step."')
      local agent_list
      agent_list=$(echo "$step_json" | jq -r '.agents | join(", ")')
      jq -n --arg msg "Spawn these agents in parallel: ${agent_list}. ${instruction}" \
        '{"decision": "block", "reason": $msg}'
      ;;
    teammate_idle)
      # Gate specific agent with its instruction
      local agent_type
      agent_type=$(echo "$hook_input_json" | jq -r '.agent_type // empty')
      if [[ -n "$agent_type" ]]; then
        local agent_status
        agent_status=$(state_get_agent_status "$state" "$step_index" "$agent_type" 2>/dev/null)
        if [[ "$agent_status" == "pending" || "$agent_status" == "idle" ]]; then
          state_set_agent_status "$state_file" "$step_index" "$agent_type" "working"
          local agent_instruction
          agent_instruction=$(echo "$step_json" | jq -r --arg agent "$agent_type" '.agent_instructions[$agent] // .instruction // empty')
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
      agent_type=$(echo "$hook_input_json" | jq -r '.agent_type // empty')
      if [[ -n "$agent_type" ]]; then
        state_set_agent_status "$state_file" "$step_index" "$agent_type" "done"
      fi
      # FR-010: Check if all agents are done (fan-in)
      state=$(state_read "$state_file") || return 1
      local all_done
      all_done=$(echo "$state" | jq --argjson idx "$step_index" '
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
      message=$(echo "$step_json" | jq -r '.message // "Approval required to continue."')
      jq -n --arg msg "APPROVAL GATE: ${message} — Waiting for approval via TeammateIdle." \
        '{"decision": "block", "reason": $msg}'
      ;;
    teammate_idle)
      # User/agent approves by sending idle with approval context
      local approval
      approval=$(echo "$hook_input_json" | jq -r '.approval // empty')
      if [[ "$approval" == "approved" ]]; then
        state_set_step_status "$state_file" "$step_index" "done"
        local next_index=$((step_index + 1))
        state_set_cursor "$state_file" "$next_index"
        jq -n '{"decision": "approve"}'
      else
        local message
        message=$(echo "$step_json" | jq -r '.message // "Approval required to continue."')
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
  condition=$(echo "$step_json" | jq -r '.condition // empty')
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
    target_id=$(echo "$step_json" | jq -r '.if_zero // empty')
  else
    target_id=$(echo "$step_json" | jq -r '.if_nonzero // empty')
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

  # Record the branch decision in command log for auditability
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  state_append_command_log "$state_file" "$step_index" "branch: condition='${condition}' exit=${cond_exit} target=${target_id}" "$cond_exit" "$now"
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
  max_iterations=$(echo "$step_json" | jq -r '.max_iterations // 10')
  local on_exhaustion
  on_exhaustion=$(echo "$step_json" | jq -r '.on_exhaustion // "fail"')
  local condition
  condition=$(echo "$step_json" | jq -r '.condition // empty')

  # Get current iteration count
  state=$(state_read "$state_file") || return 1
  local current_iteration
  current_iteration=$(echo "$state" | jq --argjson idx "$step_index" '.steps[$idx].loop_iteration // 0')

  # Check max iterations
  if [[ "$current_iteration" -ge "$max_iterations" ]]; then
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    state_append_command_log "$state_file" "$step_index" "loop: exhausted after ${current_iteration} iterations" 1 "$now"
    if [[ "$on_exhaustion" == "continue" ]]; then
      state_set_step_status "$state_file" "$step_index" "done"
      local next_index=$((step_index + 1))
      state_set_cursor "$state_file" "$next_index"
      jq -n '{"decision": "approve"}'
      return 0
    else
      state_set_step_status "$state_file" "$step_index" "failed"
      # Update workflow status to failed
      state=$(state_read "$state_file") || return 1
      local updated
      updated=$(echo "$state" | jq '.status = "failed"')
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
      jq -n '{"decision": "approve"}'
      return 0
    fi
  fi

  # Increment iteration counter
  state=$(state_read "$state_file") || return 1
  local updated
  updated=$(echo "$state" | jq --argjson idx "$step_index" --argjson iter "$((current_iteration + 1))" \
    '.steps[$idx].loop_iteration = $iter')
  state_write "$state_file" "$updated"

  # Execute substep
  local substep
  substep=$(echo "$step_json" | jq '.substep // empty')
  if [[ -z "$substep" || "$substep" == "null" ]]; then
    echo "ERROR: loop step missing 'substep' field" >&2
    state_set_step_status "$state_file" "$step_index" "failed"
    return 1
  fi

  local substep_type
  substep_type=$(echo "$substep" | jq -r '.type')

  case "$substep_type" in
    command)
      # Execute the command substep directly
      local command
      command=$(echo "$substep" | jq -r '.command // empty')
      local output
      local cmd_exit_code
      output=$(eval "$command" 2>&1) || true
      cmd_exit_code=${PIPESTATUS[0]:-$?}
      local now
      now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
      state_append_command_log "$state_file" "$step_index" "$command" "$cmd_exit_code" "$now"

      # After substep execution, re-dispatch the loop to check condition again
      # Use re-exec to avoid recursion
      exec "$WHEEL_HOOK_SCRIPT" <<< "$WHEEL_HOOK_INPUT"
      ;;
    agent)
      # Return instruction for the agent substep
      local instruction
      instruction=$(echo "$substep" | jq -r '.instruction // empty')
      jq -n --arg msg "Loop iteration $((current_iteration + 1))/${max_iterations}: ${instruction}" \
        '{"decision": "block", "reason": $msg}'
      ;;
    *)
      echo "ERROR: unsupported substep type: $substep_type" >&2
      return 1
      ;;
  esac
}
