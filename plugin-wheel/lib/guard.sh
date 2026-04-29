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
  # resolve to the deepest descendant by walking the parent_workflow chain — the leaf
  # is the active workflow. A single-level preference (has parent vs not) is not enough
  # because a grandchild and its child both have parent_workflow set, and glob ordering
  # is nondeterministic (filenames embed ${date}_${RANDOM}).
  local sf
  local -a candidates=()
  for sf in "${state_dir}"/state_*.json; do
    [[ -f "$sf" ]] || continue
    local owner_sid owner_aid
    owner_sid=$(jq -r '.owner_session_id // empty' "$sf" 2>/dev/null) || continue
    owner_aid=$(jq -r '.owner_agent_id // empty' "$sf" 2>/dev/null) || continue

    # Match by owner_agent_id or alternate_agent_id (for teammate agents
    # where the hook receives a team-format ID like "worker-1@team" but the
    # state file stores the raw Claude agent ID).
    local id_match=false
    if [[ "$owner_sid" == "$hook_session_id" && "$owner_aid" == "$hook_agent_id" ]]; then
      id_match=true
    elif [[ "$owner_sid" == "$hook_session_id" && "$hook_agent_id" == *"@"* ]]; then
      local alt_aid
      alt_aid=$(jq -r '.alternate_agent_id // empty' "$sf" 2>/dev/null) || true
      [[ -n "$alt_aid" && "$alt_aid" == "$hook_agent_id" ]] && id_match=true
    elif [[ "$owner_sid" == "$hook_session_id" ]]; then
      # Fallback: check alternate_agent_id even when hook_agent_id has no @.
      # This catches teammate agents where the stop hook receives the raw UUID
      # instead of the team-format ID — the second branch above would skip
      # because it requires "@", but the state file still carries the match.
      local alt_aid
      alt_aid=$(jq -r '.alternate_agent_id // empty' "$sf" 2>/dev/null) || true
      [[ -n "$alt_aid" && "$alt_aid" == "$hook_agent_id" ]] && id_match=true
    fi

    if [[ "$id_match" == true ]]; then
      candidates+=("$sf")
    fi
  done

  if [[ ${#candidates[@]} -eq 0 ]]; then
    return 1
  fi

  # Pick the leaf: a candidate whose path is not referenced as parent_workflow by
  # any other candidate. In a well-formed chain there is exactly one leaf.
  local c1 c2 c2_parent is_leaf
  for c1 in "${candidates[@]}"; do
    is_leaf=true
    for c2 in "${candidates[@]}"; do
      [[ "$c1" == "$c2" ]] && continue
      c2_parent=$(jq -r '.parent_workflow // empty' "$c2" 2>/dev/null) || true
      if [[ "$c2_parent" == "$c1" ]]; then
        is_leaf=false
        break
      fi
    done
    if [[ "$is_leaf" == true ]]; then
      printf '%s\n' "$c1"
      return 0
    fi
  done

  # Fallback — no leaf found (should not happen for well-formed state). Return the
  # deepest-by-chain-walk candidate instead of silently passing through.
  printf '%s\n' "${candidates[-1]}"
  return 0
}

# FR-005/FR-006 (wheel-user-input): Resolve the active state file from CWD
# context WITHOUT hook input. Used by CLI tools (e.g.
# `wheel-flag-needs-input`) invoked from inside an agent's bash turn, where no
# hook-style session_id/agent_id is available.
#
# Strategy: scan `<state_dir>/state_*.json` for workflows with
# status=="running", then pick the leaf (a candidate whose path is not
# referenced as `parent_workflow` by any other candidate). On well-formed
# state this uniquely identifies the deepest active workflow.
#
# Params:
#   $1 = state_dir (string) — path to .wheel directory (default ".wheel")
#
# Output (stdout): resolved state file path
# Exit:
#   0 = state file found (path printed)
#   1 = no active running state file found
resolve_active_state_file_nohook() {
  local state_dir="${1:-.wheel}"
  local sf
  local -a candidates=()
  for sf in "${state_dir}"/state_*.json; do
    [[ -f "$sf" ]] || continue
    local status
    status=$(jq -r '.status // empty' "$sf" 2>/dev/null) || continue
    if [[ "$status" == "running" ]]; then
      candidates+=("$sf")
    fi
  done

  if [[ ${#candidates[@]} -eq 0 ]]; then
    return 1
  fi

  if [[ ${#candidates[@]} -eq 1 ]]; then
    printf '%s\n' "${candidates[0]}"
    return 0
  fi

  # Multiple candidates — pick the leaf.
  local c1 c2 c2_parent is_leaf
  for c1 in "${candidates[@]}"; do
    is_leaf=true
    for c2 in "${candidates[@]}"; do
      [[ "$c1" == "$c2" ]] && continue
      c2_parent=$(jq -r '.parent_workflow // empty' "$c2" 2>/dev/null) || true
      if [[ "$c2_parent" == "$c1" ]]; then
        is_leaf=false
        break
      fi
    done
    if [[ "$is_leaf" == true ]]; then
      printf '%s\n' "$c1"
      return 0
    fi
  done

  # Fallback — no leaf found (malformed chain); return last candidate.
  printf '%s\n' "${candidates[-1]}"
  return 0
}
