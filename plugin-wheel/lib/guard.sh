#!/usr/bin/env bash
# guard.sh — Per-agent state file resolver for wheel workflows
# FR-004/005: Resolves the correct state file by matching owner fields inside state JSON

# FR-004/005: Resolve the state file for the current hook invocation.
# Scans all state files in the state directory and matches on owner_session_id
# and owner_agent_id stored inside the JSON. This decouples ownership from
# filename, preventing leaks between agents sharing a session_id.
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

  # Extract session_id and agent_id from hook input
  local hook_session_id
  hook_session_id=$(printf '%s\n' "$hook_input_json" | jq -r '.session_id // empty')
  if [[ -z "$hook_session_id" ]]; then
    return 1
  fi

  local hook_agent_id
  hook_agent_id=$(printf '%s\n' "$hook_input_json" | jq -r '.agent_id // empty')

  # Scan state files and match on owner fields
  # FR-011/FR-013: When parent and child share the same ownership (workflow composition),
  # prefer the deepest child (has parent_workflow set) since it's the active one.
  local sf
  local matched_file=""
  local matched_is_child=false
  for sf in "${state_dir}"/state_*.json; do
    [[ -f "$sf" ]] || continue
    local owner_sid owner_aid
    owner_sid=$(jq -r '.owner_session_id // empty' "$sf" 2>/dev/null) || continue
    owner_aid=$(jq -r '.owner_agent_id // empty' "$sf" 2>/dev/null) || continue

    if [[ "$owner_sid" == "$hook_session_id" && "$owner_aid" == "$hook_agent_id" ]]; then
      local has_parent
      has_parent=$(jq -r '.parent_workflow // empty' "$sf" 2>/dev/null)
      if [[ -n "$has_parent" ]]; then
        # Child state file — always prefer over parent
        matched_file="$sf"
        matched_is_child=true
      elif [[ "$matched_is_child" == false ]]; then
        # Parent state file — only use if no child found yet
        matched_file="$sf"
      fi
    fi

    # Fallback: For teammate agents, the hook receives a team-format ID
    # (e.g., "worker-1@test-static-team") but the state file stores the raw
    # Claude agent ID. Check the alternate_agent_id field for a match.
    if [[ -z "$matched_file" || "$matched_is_child" == false ]]; then
      local alt_aid
      alt_aid=$(jq -r '.alternate_agent_id // empty' "$sf" 2>/dev/null) || true
      if [[ -n "$alt_aid" && "$owner_sid" == "$hook_session_id" && "$alt_aid" == "$hook_agent_id" ]]; then
        local has_parent
        has_parent=$(jq -r '.parent_workflow // empty' "$sf" 2>/dev/null)
        if [[ -n "$has_parent" ]]; then
          matched_file="$sf"
          matched_is_child=true
        elif [[ "$matched_is_child" == false ]]; then
          matched_file="$sf"
        fi
      fi
    fi
  done

  if [[ -n "$matched_file" ]]; then
    printf '%s\n' "$matched_file"
    return 0
  fi

  # No state file for this agent — pass through
  return 1
}
