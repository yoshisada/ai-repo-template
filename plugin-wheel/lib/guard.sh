#!/usr/bin/env bash
# guard.sh — Session guard for wheel workflow ownership
# FR-006: Shared guard function to prevent non-owner agents from advancing workflows

# FR-002/003/004/007: Check if the current hook event comes from the workflow owner.
# If ownership is not yet stamped (empty), stamps it from hook input (first-hook stamping).
#
# Params:
#   $1 = state_file (string) — path to .wheel/state.json
#   $2 = hook_input_json (string) — raw JSON from hook stdin
#
# Output (stdout): none on allow (return 0), none on pass-through (return 1)
# Side effects: May write to state_file (first-hook stamping only)
#
# Exit codes:
#   0 = owner match (or first-hook stamp) — caller should proceed with hook logic
#   1 = non-owner or unidentifiable — caller should output pass-through JSON and exit
guard_check() {
  local state_file="$1"
  local hook_input_json="$2"

  # FR-007: Extract session_id from hook input — if missing, pass through
  local hook_session_id
  hook_session_id=$(printf '%s\n' "$hook_input_json" | jq -r '.session_id // empty')
  if [[ -z "$hook_session_id" ]]; then
    return 1
  fi

  # Extract agent_id from hook input (may be empty for main orchestrator)
  local hook_agent_id
  hook_agent_id=$(printf '%s\n' "$hook_input_json" | jq -r '.agent_id // empty')

  # Read owner fields from state.json
  local owner_session_id owner_agent_id
  owner_session_id=$(jq -r '.owner_session_id // empty' "$state_file")
  owner_agent_id=$(jq -r '.owner_agent_id // empty' "$state_file")

  # FR-004: First-hook stamping — if owner fields are empty, stamp them
  if [[ -z "$owner_session_id" ]]; then
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    local state
    state=$(cat "$state_file")
    local updated
    updated=$(printf '%s\n' "$state" | jq \
      --arg sid "$hook_session_id" \
      --arg aid "$hook_agent_id" \
      --arg now "$now" \
      '.owner_session_id = $sid | .owner_agent_id = $aid | .updated_at = $now')
    printf '%s\n' "$updated" > "$state_file"
    return 0
  fi

  # FR-003: Match session_id first
  if [[ "$hook_session_id" != "$owner_session_id" ]]; then
    return 1
  fi

  # FR-003: If owner_agent_id is set, additionally match agent_id
  if [[ -n "$owner_agent_id" && "$hook_agent_id" != "$owner_agent_id" ]]; then
    return 1
  fi

  # Owner match — allow
  return 0
}
