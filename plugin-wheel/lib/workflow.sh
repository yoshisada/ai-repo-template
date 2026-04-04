#!/usr/bin/env bash
# workflow.sh — Workflow definition parser and validator
# FR-012: Load, validate, and query workflow JSON files

# FR-012: Load and validate a workflow JSON file
# Params: $1 = workflow file path
# Output (stdout): validated workflow JSON
# Exit: 0 on valid, 1 on invalid (with error message on stderr)
workflow_load() {
  local workflow_file="$1"
  if [[ ! -f "$workflow_file" ]]; then
    echo "ERROR: workflow file not found: $workflow_file" >&2
    return 1
  fi
  if ! jq empty "$workflow_file" 2>/dev/null; then
    echo "ERROR: invalid JSON in workflow file: $workflow_file" >&2
    return 1
  fi
  # Validate required fields (read directly from file to avoid echo/pipe corruption)
  local name steps_count
  name=$(jq -r '.name // empty' "$workflow_file")
  steps_count=$(jq '.steps | length' "$workflow_file")
  if [[ -z "$name" ]]; then
    echo "ERROR: workflow missing required field: name" >&2
    return 1
  fi
  if [[ "$steps_count" -eq 0 ]]; then
    echo "ERROR: workflow has no steps" >&2
    return 1
  fi
  # Validate each step has required fields
  local invalid_steps
  invalid_steps=$(jq -r '[.steps[] | select(.id == null or .type == null)] | length' "$workflow_file")
  if [[ "$invalid_steps" -gt 0 ]]; then
    echo "ERROR: $invalid_steps step(s) missing required id or type field" >&2
    return 1
  fi
  # Validate branch targets
  local content
  content=$(jq -c '.' "$workflow_file")
  if ! workflow_validate_references "$content"; then
    return 1
  fi
  printf '%s\n' "$content"
}

# FR-006 (wheel-skill-activation): Validate that all step IDs in a workflow are unique
# Params: $1 = workflow JSON (string)
# Output (stderr): error message listing duplicate IDs if found
# Exit: 0 if all IDs unique, 1 if duplicates found
workflow_validate_unique_ids() {
  local workflow_json="$1"
  local duplicates
  duplicates=$(printf '%s\n' "$workflow_json" | jq -r '
    [.steps[].id] | group_by(.) | map(select(length > 1)) | map(.[0]) | .[]')
  if [[ -n "$duplicates" ]]; then
    echo "ERROR: duplicate step IDs found: $duplicates" >&2
    return 1
  fi
  return 0
}

# FR-012: Get the list of steps from a workflow
# Params: $1 = workflow JSON (string)
# Output (stdout): JSON array of step objects
# Exit: 0
workflow_get_steps() {
  local workflow_json="$1"
  printf '%s\n' "$workflow_json" | jq '.steps'
}

# FR-012: Get a specific step by index
# Params: $1 = workflow JSON (string), $2 = step index
# Output (stdout): JSON step object
# Exit: 0 if found, 1 if index out of range
workflow_get_step() {
  local workflow_json="$1"
  local step_index="$2"
  local step_count
  step_count=$(printf '%s\n' "$workflow_json" | jq '.steps | length')
  if [[ "$step_index" -ge "$step_count" || "$step_index" -lt 0 ]]; then
    echo "ERROR: step index out of range: $step_index (total: $step_count)" >&2
    return 1
  fi
  printf '%s\n' "$workflow_json" | jq --argjson idx "$step_index" '.steps[$idx]'
}

# FR-012: Get a specific step by ID
# Params: $1 = workflow JSON (string), $2 = step ID string
# Output (stdout): JSON step object
# Exit: 0 if found, 1 if not found
workflow_get_step_by_id() {
  local workflow_json="$1"
  local step_id="$2"
  local result
  result=$(printf '%s\n' "$workflow_json" | jq --arg id "$step_id" '.steps[] | select(.id == $id)')
  if [[ -z "$result" ]]; then
    echo "ERROR: step not found with id: $step_id" >&2
    return 1
  fi
  printf '%s\n' "$result"
}

# FR-012: Get the index of a step by its ID
# Params: $1 = workflow JSON (string), $2 = step ID string
# Output (stdout): integer step index (0-based)
# Exit: 0 if found, 1 if not found
workflow_get_step_index() {
  local workflow_json="$1"
  local step_id="$2"
  local index
  index=$(printf '%s\n' "$workflow_json" | jq --arg id "$step_id" '[.steps[].id] | index($id)')
  if [[ "$index" == "null" || -z "$index" ]]; then
    echo "ERROR: step not found with id: $step_id" >&2
    return 1
  fi
  printf '%s\n' "$index"
}

# FR-012: Get the total number of steps
# Params: $1 = workflow JSON (string)
# Output (stdout): integer count
# Exit: 0
workflow_step_count() {
  local workflow_json="$1"
  printf '%s\n' "$workflow_json" | jq '.steps | length'
}

# FR-012: Validate that all branch targets reference existing step IDs
# Params: $1 = workflow JSON (string)
# Output: none on success, error details on stderr on failure
# Exit: 0 if valid, 1 if invalid references found
workflow_validate_references() {
  local workflow_json="$1"
  local all_ids
  all_ids=$(printf '%s\n' "$workflow_json" | jq -r '[.steps[].id] | @json')
  # Check branch step targets
  local invalid_refs
  invalid_refs=$(printf '%s\n' "$workflow_json" | jq --argjson ids "$all_ids" -r '
    [.steps[] | select(.type == "branch") |
      (if .if_zero != null and (.if_zero | IN($ids[])) == false then "branch step \(.id): if_zero target \(.if_zero) not found" else empty end),
      (if .if_nonzero != null and (.if_nonzero | IN($ids[])) == false then "branch step \(.id): if_nonzero target \(.if_nonzero) not found" else empty end)
    ] | .[]')
  if [[ -n "$invalid_refs" ]]; then
    echo "ERROR: invalid step references:" >&2
    printf '%s\n' "$invalid_refs" >&2
    return 1
  fi
  # FR-007: Validate next field references on ALL step types
  local invalid_next
  invalid_next=$(printf '%s\n' "$workflow_json" | jq --argjson ids "$all_ids" -r '
    [.steps[] | select(.next != null) |
      (if (.next | IN($ids[])) == false then "step \(.id): next target \(.next) not found" else empty end)
    ] | .[]')
  if [[ -n "$invalid_next" ]]; then
    echo "ERROR: invalid next field references:" >&2
    printf '%s\n' "$invalid_next" >&2
    return 1
  fi
  return 0
}
