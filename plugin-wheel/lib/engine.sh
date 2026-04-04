#!/usr/bin/env bash
# engine.sh — Core state machine engine for Wheel
# FR-001: Sources all lib modules, provides main dispatch loop

# Resolve the directory this script lives in
WHEEL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all library modules
# shellcheck source=state.sh
source "${WHEEL_LIB_DIR}/state.sh"
# shellcheck source=workflow.sh
source "${WHEEL_LIB_DIR}/workflow.sh"
# shellcheck source=dispatch.sh
source "${WHEEL_LIB_DIR}/dispatch.sh"
# shellcheck source=lock.sh
source "${WHEEL_LIB_DIR}/lock.sh"
# shellcheck source=context.sh
source "${WHEEL_LIB_DIR}/context.sh"

# Globals set by engine_init
WORKFLOW=""
STATE_DIR=""
STATE_FILE=""

# FR-001: Initialize engine — load workflow definition, load or create state.json
# Sources lib/state.sh, lib/workflow.sh, lib/dispatch.sh, lib/lock.sh, lib/context.sh
# Params: $1 = workflow file path, $2 = state directory path (default: .wheel)
# Output: none (sets global variables: WORKFLOW, STATE_DIR, STATE_FILE)
# Exit: 0 on success, 1 if workflow file missing or invalid
engine_init() {
  local workflow_file="$1"
  local state_dir="${2:-.wheel}"

  STATE_DIR="$state_dir"
  STATE_FILE="${STATE_DIR}/state.json"

  # Load and validate workflow
  WORKFLOW=$(workflow_load "$workflow_file") || return 1

  # Initialize state if it doesn't exist
  if [[ ! -f "$STATE_FILE" ]]; then
    mkdir -p "$STATE_DIR"
    state_init "$STATE_FILE" "$WORKFLOW" || return 1
    # Clean any stale locks on fresh start
    lock_clean_all "${STATE_DIR}/.locks"
  fi

  return 0
}

# Kickstart the workflow by dispatching the first step inline.
# Called by /wheel-run after state_init. For command/loop/branch steps,
# this executes them immediately so the workflow doesn't stall waiting
# for a hook event. For agent steps, returns the instruction as context.
# Params: $1 = state file path (default: .wheel/state.json)
# Output (stdout): For agent steps, prints the step instruction for the LLM.
#                  For command steps, executes silently (output goes to files).
# Exit: 0
engine_kickstart() {
  local state_file="${1:-.wheel/state.json}"

  local state
  state=$(state_read "$state_file") || return 1
  local cursor
  cursor=$(state_get_cursor "$state")
  local total_steps
  total_steps=$(printf '%s\n' "$WORKFLOW" | jq '.steps | length')

  if [[ "$cursor" -ge "$total_steps" ]]; then
    return 0
  fi

  local first_step
  first_step=$(printf '%s\n' "$WORKFLOW" | jq --argjson idx "$cursor" '.steps[$idx]')
  local step_type
  step_type=$(printf '%s\n' "$first_step" | jq -r '.type')

  case "$step_type" in
    command|loop|branch)
      # Execute inline — these don't need LLM interaction
      export WHEEL_HOOK_SCRIPT=""
      export WHEEL_HOOK_INPUT='{}'
      dispatch_step "$first_step" "stop" '{}' "$state_file" "$cursor" >/dev/null 2>&1
      ;;
    agent)
      # Return the instruction so the skill can display it
      local instruction
      instruction=$(printf '%s\n' "$first_step" | jq -r '.instruction // empty')
      if [[ -n "$instruction" ]]; then
        echo "$instruction"
      fi
      ;;
  esac

  return 0
}

# FR-001: Determine the current step and return its definition
# Params: none (uses globals set by engine_init)
# Output (stdout): JSON object — the current step definition from the workflow, or empty if workflow complete
# Exit: 0 if step found, 2 if workflow complete, 1 on error
engine_current_step() {
  local state
  state=$(state_read "$STATE_FILE") || return 1
  local cursor
  cursor=$(state_get_cursor "$state")
  local total_steps
  total_steps=$(workflow_step_count "$WORKFLOW")

  if [[ "$cursor" -ge "$total_steps" ]]; then
    # Workflow complete
    return 2
  fi

  workflow_get_step "$WORKFLOW" "$cursor"
}

# FR-003/019/024/025: Execute the next action based on step type
# Delegates to dispatch_step() and handles the result
# Params: $1 = hook_type (stop|teammate_idle|subagent_start|subagent_stop|post_tool_use)
#          $2 = hook_input_json (the raw JSON from Claude Code hook stdin)
# Output (stdout): JSON hook response (for Claude Code to consume)
# Exit: 0 on success, 1 on error
engine_handle_hook() {
  local hook_type="$1"
  local hook_input_json="$2"

  # Check if workflow is complete
  local state
  state=$(state_read "$STATE_FILE") || return 1
  local wf_status
  wf_status=$(printf '%s\n' "$state" | jq -r '.status')

  if [[ "$wf_status" == "completed" || "$wf_status" == "failed" ]]; then
    jq -n '{"decision": "approve"}'
    return 0
  fi

  # Get current step (|| true to prevent set -e from killing us on exit 2)
  local current_step
  local step_exit
  current_step=$(engine_current_step) && step_exit=0 || step_exit=$?

  if [[ "$step_exit" -eq 2 ]]; then
    # Workflow complete — mark it and allow
    local updated
    updated=$(printf '%s\n' "$state" | jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" \
      '.status = "completed" | .updated_at = $now')
    state_write "$STATE_FILE" "$updated"
    jq -n '{"decision": "approve"}'
    return 0
  elif [[ "$step_exit" -ne 0 ]]; then
    jq -n '{"decision": "approve"}'
    return 1
  fi

  # Get step index
  local cursor
  cursor=$(state_get_cursor "$state")

  # Handle special hook types that don't dispatch to step handlers
  case "$hook_type" in
    post_tool_use)
      # FR-022: Log bash commands to command_log
      local tool_name
      tool_name=$(printf '%s\n' "$hook_input_json" | jq -r '.tool_name // empty')
      if [[ "$tool_name" == "Bash" ]]; then
        local command_text
        command_text=$(printf '%s\n' "$hook_input_json" | jq -r '.tool_input.command // empty')
        local exit_code
        exit_code=$(printf '%s\n' "$hook_input_json" | jq -r '.tool_output.exit_code // 0')
        local now
        now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
        state_append_command_log "$STATE_FILE" "$cursor" "$command_text" "$exit_code" "$now"
      fi
      jq -n '{"hookEventName": "PostToolUse"}'
      return 0
      ;;
    session_start)
      # FR-008: Resume — inject context about where we left off
      local step_id
      step_id=$(printf '%s\n' "$current_step" | jq -r '.id')
      local step_status
      step_status=$(state_get_step_status "$state" "$cursor")
      local cmd_log
      cmd_log=$(state_get_command_log "$state" "$cursor")
      local resume_msg="Resuming workflow. Current step: ${step_id} (status: ${step_status}, index: ${cursor})."
      if [[ "$cmd_log" != "[]" ]]; then
        resume_msg="${resume_msg} Previous command log for this step is available in state.json."
      fi
      # If step was working, note it needs re-run
      if [[ "$step_status" == "working" ]]; then
        resume_msg="${resume_msg} Step was in progress when session ended — re-running from the beginning of this step."
      fi
      jq -n --arg msg "$resume_msg" '{"decision": "approve", "additionalContext": $msg}'
      return 0
      ;;
  esac

  # Dispatch to the appropriate step handler
  dispatch_step "$current_step" "$hook_type" "$hook_input_json" "$STATE_FILE" "$cursor"
}
