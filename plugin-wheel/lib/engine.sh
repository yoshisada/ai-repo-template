#!/usr/bin/env bash
# engine.sh — Core state machine engine for Wheel
# FR-001: Sources all lib modules, provides main dispatch loop

# Resolve the directory this script lives in.
# If WHEEL_LIB_DIR is already set (libs sourced individually), skip re-sourcing.
if [[ -z "${WHEEL_LIB_DIR:-}" ]] || ! declare -f workflow_load &>/dev/null; then
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
  # shellcheck source=guard.sh
  source "${WHEEL_LIB_DIR}/guard.sh"
fi

# Always source registry.sh + resolve.sh — they have their own re-source
# guards (WHEEL_REGISTRY_SH_LOADED / WHEEL_RESOLVE_SH_LOADED) so this is a
# no-op if already loaded. We can't put these inside the workflow_load gate
# because callers may have sourced workflow.sh directly, leaving registry
# and resolve unloaded.
# shellcheck source=registry.sh
source "${WHEEL_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/registry.sh"
# shellcheck source=resolve.sh
source "${WHEEL_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/resolve.sh"

# engine_preflight_resolve — Run the cross-plugin pre-flight phase
# (specs/cross-plugin-resolver-and-preflight-registry FR-F1 + FR-F3).
#
# Builds the session registry, runs the workflow's requires_plugins
# validation, and on failure writes a diagnostic snapshot to
# .wheel/state/registry-failed-<timestamp>.json for post-mortem.
#
# Args: $1 = workflow JSON (string, output of workflow_load)
# Stdout: registry JSON (single-line envelope) on success — caller may
#         capture and pass to the preprocessor (Theme F4).
# Stderr: documented FR-F3-3 error text on failure.
# Exit:   0 on success, 1 on registry build OR resolver failure.
#
# T031: MUST run BEFORE state_init or any other state mutation. Contract
#       I-V-1 mandates "no side effects on resolver failure."
engine_preflight_resolve() {
  local workflow_json="$1"

  if [[ -z "$workflow_json" ]]; then
    echo "engine_preflight_resolve: empty workflow_json argument" >&2
    return 1
  fi

  local registry_json
  if ! registry_json=$(build_session_registry); then
    echo "engine_preflight_resolve: failed to build session registry" >&2
    return 1
  fi

  if ! resolve_workflow_dependencies "$workflow_json" "$registry_json"; then
    # T032: Diagnostic snapshot retained on failure.
    if [[ -d .wheel ]]; then
      mkdir -p .wheel/state
      local snap_path
      snap_path=".wheel/state/registry-failed-$(date -u +%Y%m%dT%H%M%SZ).json"
      printf '%s\n' "$registry_json" >"$snap_path" 2>/dev/null || true
      echo "engine_preflight_resolve: diagnostic snapshot written to ${snap_path}" >&2
    fi
    return 1
  fi

  printf '%s\n' "$registry_json"
  return 0
}

# Globals set by engine_init — only initialize if not already set
# (hooks may set STATE_FILE before sourcing engine.sh)
WORKFLOW="${WORKFLOW:-}"
STATE_DIR="${STATE_DIR:-}"
STATE_FILE="${STATE_FILE:-}"

# FR-010: Initialize engine — load workflow definition, use provided state file.
# No longer hardcodes STATE_FILE. Receives the resolved state file path.
#
# Params:
#   $1 = workflow_file (string) — path to workflow JSON file
#   $2 = state_file (string) — resolved state file path (from resolve_state_file or skill)
#
# Output: none (sets global variables: WORKFLOW, STATE_DIR, STATE_FILE)
# Exit: 0 on success, 1 if workflow file missing or invalid
#
# CHANGED FROM: engine_init(workflow_file, state_dir)
# CHANGED TO:   engine_init(workflow_file, state_file)
engine_init() {
  local workflow_file="$1"
  local state_file="$2"

  STATE_FILE="$state_file"
  STATE_DIR="$(dirname "$state_file")"

  # Load and validate workflow
  WORKFLOW=$(workflow_load "$workflow_file") || return 1

  return 0
}

# Kickstart the workflow by dispatching the first step inline.
# Called by /wheel:wheel-run after state_init. For command/loop/branch steps,
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
      # Set step to pending so the Stop hook knows to inject the instruction
      state_set_step_status "$state_file" "$cursor" "pending"
      # Return the instruction so the skill can display it
      local instruction
      instruction=$(printf '%s\n' "$first_step" | jq -r '.instruction // empty')
      if [[ -n "$instruction" ]]; then
        echo "$instruction"
      fi
      ;;
    workflow)
      # FR-014: Workflow steps are NOT kickstartable — leave in pending for hook to handle
      # FR-015: Child workflow kickstart happens inside dispatch_workflow()
      ;;
    team-create|teammate|team-delete)
      # FR-024: Team steps inject instructions via stop hook — set to pending
      state_set_step_status "$state_file" "$cursor" "pending"
      ;;
    team-wait)
      # FR-026: team-wait is NOT kickstartable — needs polling via hook
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
      # FR-030: Detect agent step output file written via Write/Edit
      local step_type
      step_type=$(printf '%s\n' "$current_step" | jq -r '.type')
      if [[ "$step_type" == "agent" ]]; then
        local step_status
        step_status=$(state_get_step_status "$state" "$cursor")
        if [[ "$step_status" == "working" || "$step_status" == "pending" ]]; then
          # Allow both "working" and "pending" — the agent may write the output
          # file before the stop hook transitions the step to "working"
          # (e.g., when PostToolUse advances cursor to a new agent step and the
          # agent writes that step's output in the same turn)
          if [[ "$step_status" == "pending" ]]; then
            state_set_step_status "$STATE_FILE" "$cursor" "working"
          fi
          dispatch_agent "$current_step" "post_tool_use" "$hook_input_json" "$STATE_FILE" "$cursor"
          return $?
        fi
      elif [[ "$step_type" == "workflow" ]]; then
        # Dispatch workflow steps from PostToolUse — creates child state file
        # when cursor advances to a workflow step after a previous step completes
        dispatch_workflow "$current_step" "post_tool_use" "$hook_input_json" "$STATE_FILE" "$cursor"
        return $?
      elif [[ "$step_type" == "team-create" || "$step_type" == "teammate" || "$step_type" == "team-delete" ]]; then
        # FR-024: Route team step types to their dispatch handlers via PostToolUse
        dispatch_step "$current_step" "post_tool_use" "$hook_input_json" "$STATE_FILE" "$cursor"
        return $?
      elif [[ "$step_type" == "team-wait" ]]; then
        # FR-026: team-wait polls teammate status on each PostToolUse invocation
        dispatch_step "$current_step" "post_tool_use" "$hook_input_json" "$STATE_FILE" "$cursor"
        return $?
      elif [[ "$step_type" == "command" || "$step_type" == "loop" || "$step_type" == "branch" ]]; then
        # Command steps reached via cursor advancement (e.g., after agent step
        # auto-complete) — execute inline so the workflow doesn't stall.
        local step_status
        step_status=$(state_get_step_status "$state" "$cursor")
        if [[ "$step_status" == "pending" ]]; then
          dispatch_step "$current_step" "stop" "$hook_input_json" "$STATE_FILE" "$cursor" >/dev/null 2>&1
        fi
      fi
      jq -n '{"hookEventName": "PostToolUse"}'
      return 0
      ;;
    teammate_idle)
      # Handle teammate going idle — route to appropriate step handler
      local step_type
      step_type=$(printf '%s\n' "$current_step" | jq -r '.type')
      if [[ "$step_type" == "team-wait" || "$step_type" == "agent" ]]; then
        dispatch_step "$current_step" "teammate_idle" "$hook_input_json" "$STATE_FILE" "$cursor"
        return $?
      fi
      jq -n '{"decision": "approve"}'
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
