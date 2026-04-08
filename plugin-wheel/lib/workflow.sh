#!/usr/bin/env bash
# workflow.sh — Workflow definition parser and validator
# FR-012: Load, validate, and query workflow JSON files
# FR-029: Discover workflows from installed plugin manifests

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
  # FR-003/FR-004/FR-005/FR-006: Validate workflow step references
  if ! workflow_validate_workflow_refs "$content" "" 0; then
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

# FR-003/FR-004/FR-005/FR-006: Validate workflow step references, detect circular
# references, enforce nesting depth, and recursively validate child workflows.
#
# Params:
#   $1 = workflow_json (string) — validated workflow JSON
#   $2 = visited (string) — comma-separated list of workflow names already in the call chain (for cycle detection)
#   $3 = depth (integer) — current nesting depth (starts at 0)
#
# Output (stderr): error messages if validation fails
# Exit: 0 if all workflow references valid, 1 if any validation fails
workflow_validate_workflow_refs() {
  local workflow_json="$1"
  local visited="$2"
  local depth="$3"

  # FR-006: Cap nesting depth at 5 levels
  if [[ "$depth" -gt 5 ]]; then
    echo "ERROR: workflow nesting depth exceeds maximum (5)" >&2
    return 1
  fi

  # Get current workflow name for cycle detection
  local current_name
  current_name=$(printf '%s\n' "$workflow_json" | jq -r '.name // "unknown"')

  # Collect all workflow steps
  local workflow_steps
  workflow_steps=$(printf '%s\n' "$workflow_json" | jq -r '.steps[] | select(.type == "workflow") | .id + ":" + .workflow')

  if [[ -z "$workflow_steps" ]]; then
    return 0
  fi

  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    local step_id="${entry%%:*}"
    local child_name="${entry#*:}"

    # FR-003: Validate that the referenced workflow file exists
    local child_file="workflows/${child_name}.json"
    if [[ ! -f "$child_file" ]]; then
      echo "ERROR: workflow step '${step_id}' references missing workflow: ${child_name}" >&2
      return 1
    fi

    # FR-004: Detect circular references via visited set
    local chain
    if [[ -n "$visited" ]]; then
      chain="${visited},${current_name}"
    else
      chain="${current_name}"
    fi
    if [[ "$current_name" == "$child_name" ]]; then
      local display_chain="${chain} -> ${child_name}"
      display_chain=$(printf '%s\n' "$display_chain" | sed 's/,/ -> /g')
      echo "ERROR: circular workflow reference detected: ${display_chain}" >&2
      return 1
    fi
    if [[ -n "$visited" ]]; then
      local IFS_OLD="$IFS"
      IFS=','
      for v in $visited; do
        if [[ "$v" == "$child_name" ]]; then
          local display_chain="${chain} -> ${child_name}"
          display_chain=$(printf '%s\n' "$display_chain" | sed 's/,/ -> /g')
          echo "ERROR: circular workflow reference detected: ${display_chain}" >&2
          IFS="$IFS_OLD"
          return 1
        fi
      done
      IFS="$IFS_OLD"
    fi

    # FR-005: Recursively validate child workflow
    local child_json
    if ! child_json=$(jq -c '.' "$child_file" 2>/dev/null); then
      echo "ERROR: invalid JSON in child workflow: ${child_name}" >&2
      return 1
    fi

    # Build visited chain for recursion
    local new_visited
    if [[ -n "$visited" ]]; then
      new_visited="${visited},${current_name}"
    else
      new_visited="${current_name}"
    fi

    if ! workflow_validate_workflow_refs "$child_json" "$new_visited" $((depth + 1)); then
      return 1
    fi
  done <<< "$workflow_steps"

  return 0
}

# FR-029: Discover workflows declared in installed plugin manifests
# Reads ~/.claude/plugins/installed_plugins.json, follows each plugin's installPath,
# reads .claude-plugin/plugin.json for a "workflows" field, and resolves each entry
# to an absolute path.
# Params: none
# Output (stdout): JSON array of plugin workflow descriptors
#   [{"name": "workflow-name", "plugin": "plugin-name", "path": "/abs/path/to/workflow.json", "readonly": true}, ...]
# Exit: 0 on success (empty array if no plugins found), 1 on parse error
workflow_discover_plugin_workflows() {
  local installed_plugins_file="${HOME}/.claude/plugins/installed_plugins.json"
  if [[ ! -f "$installed_plugins_file" ]]; then
    echo '[]'
    return 0
  fi

  local installed_json
  if ! installed_json=$(jq -c '.' "$installed_plugins_file" 2>/dev/null); then
    echo "ERROR: invalid JSON in installed_plugins.json" >&2
    return 1
  fi

  local result='[]'

  # Extract all installPath values from installed_plugins.json
  local install_paths
  install_paths=$(printf '%s\n' "$installed_json" | jq -r '
    .plugins // {} | to_entries[] | .value[] | .installPath // empty')

  if [[ -z "$install_paths" ]]; then
    echo '[]'
    return 0
  fi

  while IFS= read -r install_path; do
    [[ -z "$install_path" ]] && continue
    local manifest="${install_path}/.claude-plugin/plugin.json"
    [[ ! -f "$manifest" ]] && continue

    local manifest_json
    if ! manifest_json=$(jq -c '.' "$manifest" 2>/dev/null); then
      continue
    fi

    local plugin_name
    plugin_name=$(printf '%s\n' "$manifest_json" | jq -r '.name // empty')
    [[ -z "$plugin_name" ]] && continue

    local workflows_field
    workflows_field=$(printf '%s\n' "$manifest_json" | jq -c '.workflows // empty')
    [[ -z "$workflows_field" || "$workflows_field" == "null" ]] && continue

    local wf_count
    wf_count=$(printf '%s\n' "$workflows_field" | jq 'length')
    [[ "$wf_count" -eq 0 ]] && continue

    # Iterate over each workflow path in the manifest
    local wf_entries
    wf_entries=$(printf '%s\n' "$workflows_field" | jq -r '.[]')

    while IFS= read -r wf_rel_path; do
      [[ -z "$wf_rel_path" ]] && continue
      local wf_abs_path="${install_path}/${wf_rel_path}"
      [[ ! -f "$wf_abs_path" ]] && continue

      # Derive workflow name from filename (strip .json extension)
      local wf_name
      wf_name=$(basename "$wf_rel_path" .json)

      result=$(printf '%s\n' "$result" | jq --arg name "$wf_name" \
        --arg plugin "$plugin_name" \
        --arg path "$wf_abs_path" \
        '. + [{"name": $name, "plugin": $plugin, "path": $path, "readonly": true}]')
    done <<< "$wf_entries"
  done <<< "$install_paths"

  printf '%s\n' "$result"
  return 0
}
