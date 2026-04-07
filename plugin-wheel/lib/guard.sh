#!/usr/bin/env bash
# guard.sh — Per-agent state file resolver for wheel workflows
# FR-004/005: Resolves the correct state file from hook input session_id + agent_id

# FR-004/005: Resolve the state file for the current hook invocation.
# Constructs expected filename from session_id + agent_id in hook input.
# Checks for state_{session_id}_{agent_id}.json first, falls back to state_{session_id}.json.
#
# Params:
#   $1 = state_dir (string) — path to .wheel directory
#   $2 = hook_input_json (string) — raw JSON from hook stdin
#
# Output (stdout): resolved state file path
# Exit codes:
#   0 = state file found (path printed to stdout) — caller should proceed
#   1 = no state file found — caller should pass through
resolve_state_file() {
  local state_dir="$1"
  local hook_input_json="$2"

  # FR-004: Extract session_id from hook input — if missing, pass through
  local hook_session_id
  hook_session_id=$(printf '%s\n' "$hook_input_json" | jq -r '.session_id // empty')
  if [[ -z "$hook_session_id" ]]; then
    return 1
  fi

  # Extract agent_id from hook input (may be empty for main orchestrator)
  local hook_agent_id
  hook_agent_id=$(printf '%s\n' "$hook_input_json" | jq -r '.agent_id // empty')

  # FR-004: Check for agent-specific state file first
  if [[ -n "$hook_agent_id" ]]; then
    local agent_file="${state_dir}/state_${hook_session_id}_${hook_agent_id}.json"
    if [[ -f "$agent_file" ]]; then
      printf '%s\n' "$agent_file"
      return 0
    fi
  fi

  # FR-004: Fall back to session-only state file (main orchestrator)
  local session_file="${state_dir}/state_${hook_session_id}.json"
  if [[ -f "$session_file" ]]; then
    printf '%s\n' "$session_file"
    return 0
  fi

  # No state file for this agent — pass through
  return 1
}
