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
  # FR-001/FR-002 (wheel-user-input): Validate allow_user_input permission
  if ! workflow_validate_allow_user_input "$content"; then
    return 1
  fi
  # FR-F2-3 (specs/cross-plugin-resolver-and-preflight-registry): shape-only
  # validation of `requires_plugins`. Registry-aware checks (resolver match)
  # belong to resolve.sh; here we only enforce the JSON shape contract from
  # contracts/interfaces.md §4 so a malformed manifest is caught at load time
  # rather than at activation time.
  if ! workflow_validate_requires_plugins "$content"; then
    return 1
  fi

  # FR-G1-4 (specs/wheel-step-input-output-schema): shape-only validation of
  # the optional `inputs:` and `output_schema:` step fields per
  # contracts/interfaces.md §5. Sources resolve_inputs.sh for the single
  # source-of-truth grammar parser (I-PJ-3 / I-WV-1 dual-gate pattern).
  if ! workflow_validate_inputs_outputs "$content"; then
    return 1
  fi

  printf '%s\n' "$content"
}

# FR-G1-4 (specs/wheel-step-input-output-schema): shape-only load-time
# validation of the optional `inputs:` and `output_schema:` step fields per
# contracts/interfaces.md §5. Implements all 8 validation rules:
#
#   1. `inputs:` only appears on `agent` step types (OQ-G-3 deferral).
#   2. Each var name matches ^[A-Z][A-Z0-9_]*$.
#   3. Each input expression parses via `_parse_jsonpath_expr` (I-PJ-3 single
#      source of truth — workflow-load and runtime resolver share the same
#      grammar function so error strings stay byte-identical).
#   4. `$.steps.<id>.output.<field>` must reference a step appearing BEFORE
#      this step in `.steps[]`.
#   5. The referenced upstream step MUST declare `output_schema`, AND the
#      referenced `<field>` MUST appear in that schema.
#   6. `$plugin(<name>)` references must have `<name>` in `requires_plugins:`
#      (or be `wheel` itself — implicit per spec §FR-G2-3).
#   7. Each `output_schema:` field's extract directive parses (regex:<pattern>,
#      jq:<expr>, or a JSON-path string starting with `$.`).
#   8. `$config()` references are NOT allowlist-checked here — that's runtime
#      resolver behavior (I-WV-2).
#
# Pure shape check — does not read config files, does not query the registry
# (those are runtime concerns). First-error-wins per I-WV-3.
#
# Defense-in-depth (I-WV-1): error strings deliberately mirror runtime resolver
# errors (resolve_inputs.sh) byte-for-byte so the NFR-G-2 silent-failure
# tripwires (`resolve-inputs-error-shapes`) keep firing on the documented
# strings regardless of which gate caught the bug.
#
# Params: $1 = workflow JSON (string, validated JSON post-required-fields)
# Output (stderr): one error line on first offending issue
# Exit:   0 if all `inputs:` + `output_schema:` declarations are well-formed
#         (or fields absent), 1 otherwise
workflow_validate_inputs_outputs() {
  local workflow_json="$1"

  # Lazy source of resolve_inputs.sh — re-source guard prevents duplicate work.
  # Self-discover WHEEL_LIB_DIR if not exported (mirrors engine.sh:25-35
  # registry/resolve/preprocess pattern for standalone-source paths).
  # shellcheck source=resolve_inputs.sh
  source "${WHEEL_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/resolve_inputs.sh"

  local name
  name=$(printf '%s\n' "$workflow_json" | jq -r '.name // "<unknown>"')

  # Pre-extract requires_plugins for $plugin(<name>) validation. Rule 6
  # treats `wheel` as implicit (allowed without declaration). The calling
  # plugin is also implicit at runtime, but workflow_load doesn't know which
  # plugin owns this workflow — rule 6 enforces only the explicit declaration
  # path; runtime resolver covers the implicit calling-plugin case.
  local requires_plugins_json
  requires_plugins_json=$(printf '%s\n' "$workflow_json" | jq -c '.requires_plugins // []')

  # Iterate steps. We need both the step object and its index (for "appears
  # before this step" rule 4 — the reference set is .steps[0..<this-idx>-1]).
  local steps_count
  steps_count=$(printf '%s\n' "$workflow_json" | jq '.steps | length')

  local i
  for ((i = 0; i < steps_count; i++)); do
    local step_json step_id step_type step_inputs step_output_schema
    step_json=$(printf '%s\n' "$workflow_json" | jq -c --argjson i "$i" '.steps[$i]')
    step_id=$(printf '%s\n' "$step_json" | jq -r '.id // "?"')
    step_type=$(printf '%s\n' "$step_json" | jq -r '.type // "?"')
    step_inputs=$(printf '%s\n' "$step_json" | jq -c '.inputs // {}')
    step_output_schema=$(printf '%s\n' "$step_json" | jq -c '.output_schema // {}')

    # Rule 1: `inputs:` only on `agent` step types.
    if [[ "$step_inputs" != "{}" && "$step_type" != "agent" ]]; then
      printf "Workflow '%s' step '%s' (type: %s) declares 'inputs:' but type 'agent' is required.\n" \
        "$name" "$step_id" "$step_type" >&2
      return 1
    fi

    # Rule 7: validate output_schema directives (independent of inputs:).
    if [[ "$step_output_schema" != "{}" ]]; then
      if ! _validate_output_schema_directives "$name" "$step_id" "$step_output_schema"; then
        return 1
      fi
    fi

    # Skip the per-input loop when there are no inputs.
    if [[ "$step_inputs" == "{}" ]]; then
      continue
    fi

    # Iterate inputs in the order the author wrote them (keys_unsorted).
    local var_names
    var_names=$(printf '%s\n' "$step_inputs" | jq -r 'keys_unsorted[]')

    local var_name
    while IFS= read -r var_name; do
      [[ -z "$var_name" ]] && continue

      # Rule 2: var name shape.
      if ! [[ "$var_name" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
        printf "Workflow '%s' step '%s' input '%s' has invalid var name (must match ^[A-Z][A-Z0-9_]*\$).\n" \
          "$name" "$step_id" "$var_name" >&2
        return 1
      fi

      local expr
      expr=$(printf '%s\n' "$step_inputs" | jq -r --arg k "$var_name" '.[$k]')

      # Rule 3: expression parses via _parse_jsonpath_expr (single source of
      # truth — I-PJ-3). Error string mirrors resolve_inputs.sh contract §2.
      if ! _parse_jsonpath_expr "$expr"; then
        printf "Workflow '%s' step '%s' input '%s' uses unsupported expression: '%s'. Supported: \$.steps.<id>.output.<field>, \$config(<file>:<key>), \$plugin(<name>), \$step(<id>).\n" \
          "$name" "$step_id" "$var_name" "$expr" >&2
        return 1
      fi

      case "$_PARSED_KIND" in
        dollar_steps)
          local upstream_id="$_PARSED_ARG1"
          local upstream_field="$_PARSED_ARG2"

          # Rule 4: upstream must appear BEFORE this step. Build the reference
          # set as `.steps[0..i-1].id` and check membership.
          local upstream_idx
          upstream_idx=$(printf '%s\n' "$workflow_json" | jq --argjson n "$i" --arg id "$upstream_id" \
            '[.steps[0:$n][].id] | index($id)')
          if [[ "$upstream_idx" == "null" || -z "$upstream_idx" ]]; then
            printf "Workflow '%s' step '%s' input '%s' references upstream step '%s' that does not appear before this step.\n" \
              "$name" "$step_id" "$var_name" "$upstream_id" >&2
            return 1
          fi

          # Rule 5: upstream must declare output_schema AND <field> must be
          # in that schema. Look up the upstream step by ID (the upstream_idx
          # above is the index into the slice — not the absolute step index).
          local upstream_step upstream_schema
          upstream_step=$(printf '%s\n' "$workflow_json" | jq -c --arg id "$upstream_id" \
            '.steps[] | select(.id == $id)')
          upstream_schema=$(printf '%s\n' "$upstream_step" | jq -c '.output_schema // null')
          if [[ "$upstream_schema" == "null" ]]; then
            printf "Workflow '%s' step '%s' input '%s' references field '%s' of step '%s' but that step has no output_schema declaration.\n" \
              "$name" "$step_id" "$var_name" "$upstream_field" "$upstream_id" >&2
            return 1
          fi
          local field_present
          field_present=$(printf '%s\n' "$upstream_schema" | jq --arg f "$upstream_field" 'has($f)')
          if [[ "$field_present" != "true" ]]; then
            printf "Workflow '%s' step '%s' input '%s' references field '%s' of step '%s' but that field is not declared in that step's output_schema.\n" \
              "$name" "$step_id" "$var_name" "$upstream_field" "$upstream_id" >&2
            return 1
          fi
          ;;

        dollar_plugin)
          # Rule 6: name must be in requires_plugins or be `wheel` (implicit).
          local plugin_name="$_PARSED_ARG1"
          if [[ "$plugin_name" == "wheel" ]]; then
            : # implicit — always allowed.
          else
            local in_requires
            in_requires=$(printf '%s\n' "$requires_plugins_json" | jq --arg n "$plugin_name" \
              '[.[]] | index($n)')
            if [[ "$in_requires" == "null" || -z "$in_requires" ]]; then
              printf "Workflow '%s' step '%s' input '%s' resolves \$plugin('%s') but '%s' is not in requires_plugins (declare it explicitly).\n" \
                "$name" "$step_id" "$var_name" "$plugin_name" "$plugin_name" >&2
              return 1
            fi
          fi
          ;;

        dollar_step)
          # `$step(<id>)` — same upstream-existence rule as $.steps.* but
          # the field-in-schema requirement does not apply (it returns the
          # raw output file path as an escape hatch).
          local upstream_id="$_PARSED_ARG1"
          local upstream_idx
          upstream_idx=$(printf '%s\n' "$workflow_json" | jq --argjson n "$i" --arg id "$upstream_id" \
            '[.steps[0:$n][].id] | index($id)')
          if [[ "$upstream_idx" == "null" || -z "$upstream_idx" ]]; then
            printf "Workflow '%s' step '%s' input '%s' references upstream step '%s' that does not appear before this step.\n" \
              "$name" "$step_id" "$var_name" "$upstream_id" >&2
            return 1
          fi
          ;;

        dollar_config)
          # Rule 8: $config() references are NOT allowlist-checked at load
          # time — runtime resolver enforces NFR-G-7. Workflow-load only
          # validates shape (already done by _parse_jsonpath_expr).
          :
          ;;
      esac
    done <<< "$var_names"
  done

  return 0
}

# FR-G1-2 (specs/wheel-step-input-output-schema): validate output_schema
# extract directives per contracts/interfaces.md §6. Helper for
# workflow_validate_inputs_outputs (rule 7).
#
# Each field value is one of:
#   - String starting with `$.`         (direct JSON path)
#   - Object {"extract": "regex:..."}   (text-mode regex extraction)
#   - Object {"extract": "jq:..."}      (JSON-mode jq extraction)
#
# Anything else fails with the contract §5 documented error.
#
# Params:
#   $1  workflow_name      — for error message scope
#   $2  step_id            — for error message scope
#   $3  output_schema_json — single-line JSON, the step's output_schema field
#
# Output (stderr): one line on first malformed directive
# Exit: 0 if all directives valid, 1 on first offender
_validate_output_schema_directives() {
  local wf_name="$1"
  local step_id="$2"
  local schema_json="$3"

  local field_names
  field_names=$(printf '%s\n' "$schema_json" | jq -r 'keys_unsorted[]')

  local field
  while IFS= read -r field; do
    [[ -z "$field" ]] && continue

    local directive directive_type
    directive=$(printf '%s\n' "$schema_json" | jq -c --arg f "$field" '.[$f]')
    directive_type=$(printf '%s\n' "$directive" | jq -r 'type')

    case "$directive_type" in
      string)
        # Must start with `$.` (JSON-path form).
        local path_str
        path_str=$(printf '%s\n' "$directive" | jq -r '.')
        if [[ "$path_str" != \$.* ]]; then
          printf "Workflow '%s' step '%s' output_schema field '%s' has malformed extract directive: '%s'. Supported: regex:<pattern>, jq:<expr>, or a JSON-path string starting with \$.\n" \
            "$wf_name" "$step_id" "$field" "$path_str" >&2
          return 1
        fi
        ;;
      object)
        local extract_directive
        extract_directive=$(printf '%s\n' "$directive" | jq -r '.extract // ""')
        if [[ -z "$extract_directive" ]]; then
          printf "Workflow '%s' step '%s' output_schema field '%s' has malformed extract directive: '%s'. Supported: regex:<pattern>, jq:<expr>, or a JSON-path string starting with \$.\n" \
            "$wf_name" "$step_id" "$field" "$(printf '%s' "$directive")" >&2
          return 1
        fi
        if [[ "$extract_directive" != regex:* && "$extract_directive" != jq:* ]]; then
          printf "Workflow '%s' step '%s' output_schema field '%s' has malformed extract directive: '%s'. Supported: regex:<pattern>, jq:<expr>, or a JSON-path string starting with \$.\n" \
            "$wf_name" "$step_id" "$field" "$extract_directive" >&2
          return 1
        fi
        ;;
      *)
        printf "Workflow '%s' step '%s' output_schema field '%s' has malformed extract directive: '%s'. Supported: regex:<pattern>, jq:<expr>, or a JSON-path string starting with \$.\n" \
          "$wf_name" "$step_id" "$field" "$(printf '%s' "$directive")" >&2
        return 1
        ;;
    esac
  done <<< "$field_names"

  return 0
}

# FR-F2-3 (specs/cross-plugin-resolver-and-preflight-registry): shape-only
# validation of the optional `requires_plugins` array per contracts/interfaces.md §4.
#
# Rules:
#   - Field is OPTIONAL. Absence == [].
#   - When present, MUST be a JSON array.
#   - Each entry MUST be a non-empty string matching `[a-zA-Z0-9_-]+`.
#   - Duplicates are rejected.
#
# Error text matches `resolve.sh::resolve_workflow_dependencies` byte-for-byte
# so the NFR-F-2 silent-failure tripwires (`resolve-error-shapes`) keep firing
# on the documented strings regardless of whether the early gate (this fn) or
# the late gate (resolve.sh) catches the bug.
#
# Params: $1 = workflow JSON (string, validated JSON)
# Output (stderr): one error line on first offending entry
# Exit:   0 if shape is well-formed (or field absent), 1 otherwise
workflow_validate_requires_plugins() {
  local workflow_json="$1"
  local name
  name=$(printf '%s\n' "$workflow_json" | jq -r '.name // "<unknown>"')

  # If the field is absent, nothing to validate (NFR-F-5 byte-identical
  # backward-compat path).
  local has_field
  has_field=$(printf '%s\n' "$workflow_json" | jq 'has("requires_plugins")')
  if [[ "$has_field" != "true" ]]; then
    return 0
  fi

  local req_field
  req_field=$(printf '%s\n' "$workflow_json" | jq -c '.requires_plugins')

  local req_type
  req_type=$(printf '%s\n' "$req_field" | jq -r 'type')
  if [[ "$req_type" != "array" ]]; then
    echo "Workflow '${name}' has malformed requires_plugins entry: top-level must be a JSON array, got ${req_type}." >&2
    return 1
  fi

  local entries_count
  entries_count=$(printf '%s\n' "$req_field" | jq 'length')

  local i entry entry_type seen
  seen=""
  for ((i = 0; i < entries_count; i++)); do
    entry_type=$(printf '%s\n' "$req_field" | jq -r --argjson i "$i" '.[$i] | type')
    if [[ "$entry_type" != "string" ]]; then
      echo "Workflow '${name}' has malformed requires_plugins entry: non-string at index ${i}." >&2
      return 1
    fi
    entry=$(printf '%s\n' "$req_field" | jq -r --argjson i "$i" '.[$i]')
    if [[ -z "$entry" ]]; then
      echo "Workflow '${name}' has malformed requires_plugins entry: empty string at index ${i}." >&2
      return 1
    fi
    if ! [[ "$entry" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo "Workflow '${name}' has malformed requires_plugins entry: invalid name '${entry}' at index ${i} (must match [a-zA-Z0-9_-]+)." >&2
      return 1
    fi
    # Duplicate scan — `seen` is a space-delimited list with sentinel spaces
    # so substring matches don't false-positive on prefix collisions.
    if [[ " ${seen} " == *" ${entry} "* ]]; then
      echo "Workflow '${name}' has malformed requires_plugins entry: duplicate name '${entry}'." >&2
      return 1
    fi
    seen="${seen} ${entry}"
  done

  return 0
}

# FR-001/FR-002 (wheel-user-input): Validate that `allow_user_input: true` only
# appears on step types in {agent, loop, branch}. Any other step type (notably
# `command`) that sets `allow_user_input: true` is a hard workflow error —
# `command` steps execute inline with no agent turn, so "pausing" is
# meaningless.
#
# Params: $1 = workflow JSON (string, validated JSON)
# Output (stderr): one error line per offending step (id + type + field)
# Exit: 0 if all steps pass, 1 if any step violates
workflow_validate_allow_user_input() {
  local workflow_json="$1"
  # jq emits one "id|type" row per offending step; bash does the final
  # single-quoted formatting (avoids embedding apostrophes in the jq string
  # which breaks bash single-quoted filters).
  local offenders
  offenders=$(printf '%s\n' "$workflow_json" | jq -r '
    [.steps[]
      | select(.allow_user_input == true)
      | select((.type // "") as $t | ($t == "agent" or $t == "loop" or $t == "branch") | not)
      | "\(.id // "?")|\(.type // "?")"
    ] | .[]')
  if [[ -n "$offenders" ]]; then
    echo "ERROR: invalid allow_user_input on step(s):" >&2
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local off_id="${line%%|*}"
      local off_type="${line#*|}"
      echo "ERROR: step '${off_id}' (type: ${off_type}) sets allow_user_input: true but only type in {agent, loop, branch} may pause for user input" >&2
    done <<< "$offenders"
    return 1
  fi
  return 0
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

  # FR-024: Validate team step references
  # Collect all team-create step IDs
  local team_create_ids
  team_create_ids=$(printf '%s\n' "$workflow_json" | jq -r '[.steps[] | select(.type == "team-create") | .id] | @json')

  # Validate teammate/team-wait/team-delete `team` field references a valid team-create step ID
  local invalid_team_refs
  invalid_team_refs=$(printf '%s\n' "$workflow_json" | jq --argjson team_ids "$team_create_ids" -r '
    [.steps[] | select(.type == "teammate" or .type == "team-wait" or .type == "team-delete") |
      (if .team == null then "step \(.id): missing required team field" else empty end),
      (if .team != null and (.team | IN($team_ids[])) == false then "step \(.id): team field \(.team) does not reference a team-create step" else empty end)
    ] | .[]')
  if [[ -n "$invalid_team_refs" ]]; then
    echo "ERROR: invalid team step references:" >&2
    printf '%s\n' "$invalid_team_refs" >&2
    return 1
  fi

  # Validate teammate `loop_from` field references an existing step ID
  local invalid_loop_from
  invalid_loop_from=$(printf '%s\n' "$workflow_json" | jq --argjson ids "$all_ids" -r '
    [.steps[] | select(.type == "teammate" and .loop_from != null) |
      (if (.loop_from | IN($ids[])) == false then "step \(.id): loop_from target \(.loop_from) not found" else empty end)
    ] | .[]')
  if [[ -n "$invalid_loop_from" ]]; then
    echo "ERROR: invalid loop_from references:" >&2
    printf '%s\n' "$invalid_loop_from" >&2
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
    local child_file
    if [[ "$child_name" == *":"* ]]; then
      # Plugin workflow — resolve via discovery
      local plugin_name_ref="${child_name%%:*}"
      local wf_name_ref="${child_name#*:}"
      # Check for local override first
      if [[ -f "workflows/${wf_name_ref}.json" ]]; then
        child_file="workflows/${wf_name_ref}.json"
      else
        child_file=$(bash -c "source '${WHEEL_LIB_DIR}/workflow.sh' && workflow_discover_plugin_workflows" 2>/dev/null | jq -r \
          --arg plugin "$plugin_name_ref" --arg name "$wf_name_ref" \
          '.[] | select(.plugin == $plugin and .name == $name) | .path // empty')
        if [[ -z "$child_file" ]]; then
          echo "ERROR: workflow step '${step_id}' references missing plugin workflow: ${child_name}" >&2
          return 1
        fi
      fi
    else
      child_file="workflows/${child_name}.json"
      if [[ ! -f "$child_file" ]]; then
        echo "ERROR: workflow step '${step_id}' references missing workflow: ${child_name}" >&2
        return 1
      fi
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
  # Run in a subshell with tracing disabled to prevent shell environment
  # from leaking variable assignments to stdout (breaks jq parsing)
  (
    set +x 2>/dev/null

    local installed_plugins_file="${HOME}/.claude/plugins/installed_plugins.json"
    if [[ ! -f "$installed_plugins_file" ]]; then
      echo '[]'
      return 0
    fi

    local installed_json
    if ! installed_json=$(jq -c '.' "$installed_plugins_file" 2>/dev/null); then
      echo '[]'
      return 0
    fi

    local result='[]'

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

      local seen_names=""

      local workflows_field
      workflows_field=$(printf '%s\n' "$manifest_json" | jq -c '.workflows // empty')

      # Source 1: Explicit manifest entries
      if [[ -n "$workflows_field" && "$workflows_field" != "null" ]]; then
        local wf_entries
        wf_entries=$(printf '%s\n' "$workflows_field" | jq -r '.[]')

        while IFS= read -r wf_rel_path; do
          [[ -z "$wf_rel_path" ]] && continue
          local wf_abs_path="${install_path}/${wf_rel_path}"
          [[ ! -f "$wf_abs_path" ]] && continue

          local wf_name
          wf_name=$(basename "$wf_rel_path" .json)
          seen_names="${seen_names} ${wf_name} "

          result=$(printf '%s\n' "$result" | jq --arg name "$wf_name" \
            --arg plugin "$plugin_name" \
            --arg path "$wf_abs_path" \
            '. + [{"name": $name, "plugin": $plugin, "path": $path, "readonly": true}]')
        done <<< "$wf_entries"
      fi

      # Source 2: Auto-scan workflows/ directory
      local wf_dir="${install_path}/workflows"
      if [[ -d "$wf_dir" ]]; then
        for wf_file in "${wf_dir}"/*.json; do
          [[ ! -f "$wf_file" ]] && continue
          local wf_name
          wf_name=$(basename "$wf_file" .json)

          if [[ "$seen_names" == *" ${wf_name} "* ]]; then
            continue
          fi

          if jq -e '.name and .steps' "$wf_file" >/dev/null 2>&1; then
            result=$(printf '%s\n' "$result" | jq --arg name "$wf_name" \
              --arg plugin "$plugin_name" \
              --arg path "$wf_file" \
              '. + [{"name": $name, "plugin": $plugin, "path": $path, "readonly": true}]')
          fi
        done
      fi
    done <<< "$install_paths"

    printf '%s\n' "$result"
  )
}

# §1 (specs/wheel-typed-schema-locality contracts/interfaces.md): Runtime
# output-side validator. Validates that an agent step's `output_file` content
# has top-level keys matching the declared `output_schema:`. Distinct from
# the load-time `workflow_validate_inputs_outputs` shape check above.
#
# Three exit codes per contract §1:
#   0 — pass (or skipped because output_schema absent / empty / null).
#       NO stdout, NO stderr.
#   1 — schema violation (FR-H1-2 / FR-H1-6). Stderr emits the multi-line
#       diagnostic body verbatim per FR-H1-2 shape.
#   2 — validator runtime error (FR-H1-7 / NFR-H-7). Stderr emits a single
#       line naming the underlying error class.
#
# v1 validates ONLY top-level key presence — does NOT recurse into nested
# paths. Empty `output_schema: {}` and absent / null fields are early-return
# 0 (FR-H1-8 + §7 invariants).
#
# Params:
#   $1  step_json         — agent step JSON (single-line). Must contain `.id`.
#   $2  output_file_path  — path to agent's output_file. Must exist + readable.
#
# FRs covered: FR-H1-1, FR-H1-2, FR-H1-6, FR-H1-7, FR-H1-8.
workflow_validate_output_against_schema() {
  local step_json="$1"
  local output_file_path="$2"

  local step_id
  step_id=$(printf '%s\n' "$step_json" | jq -r '.id // "?"' 2>/dev/null)

  # §7 invariants — early-return 0 silently when output_schema is absent /
  # null / empty. NFR-H-3 byte-identical back-compat.
  local schema
  schema=$(printf '%s\n' "$step_json" | jq -c '.output_schema // null' 2>/dev/null)
  if [[ "$schema" == "null" || "$schema" == "{}" || -z "$schema" ]]; then
    return 0
  fi

  # output_file existence / readability checks emit exit-2 (validator runtime
  # error, not a violation — the agent didn't write something we can't parse;
  # we can't even reach the file).
  if [[ ! -e "$output_file_path" ]]; then
    printf "Output schema validator error in step '%s': output_file not found: %s\n" \
      "$step_id" "$output_file_path" >&2
    return 2
  fi
  if [[ ! -r "$output_file_path" ]]; then
    printf "Output schema validator error in step '%s': output_file is not readable: %s\n" \
      "$step_id" "$output_file_path" >&2
    return 2
  fi

  # Read actual top-level keys from output_file. jq parse error → exit 2.
  local actual_keys_raw jq_err
  jq_err=$(jq -r 'keys_unsorted[]' "$output_file_path" 2>&1 1>/tmp/.wheel_validate_out_$$)
  local jq_rc=$?
  if [[ $jq_rc -ne 0 ]]; then
    rm -f /tmp/.wheel_validate_out_$$
    # Trim multi-line jq errors to a single line (first line is most informative).
    local jq_err_head="${jq_err%%$'\n'*}"
    printf "Output schema validator error in step '%s': output_file is not valid JSON: %s\n" \
      "$step_id" "$jq_err_head" >&2
    return 2
  fi
  actual_keys_raw=$(cat /tmp/.wheel_validate_out_$$)
  rm -f /tmp/.wheel_validate_out_$$

  # Read expected top-level keys from output_schema (single-line JSON).
  local expected_keys_raw
  expected_keys_raw=$(printf '%s' "$schema" | jq -r 'keys_unsorted[]' 2>&1) || {
    local schema_err_head="${expected_keys_raw%%$'\n'*}"
    printf "Output schema validator error in step '%s': output_schema directive malformed at field '?': %s\n" \
      "$step_id" "$schema_err_head" >&2
    return 2
  }

  # LC_ALL=C lexicographic sort for deterministic snapshot diffs (FR-H1-2).
  local expected_sorted actual_sorted
  expected_sorted=$(LC_ALL=C printf '%s\n' "$expected_keys_raw" | LC_ALL=C sort)
  actual_sorted=$(LC_ALL=C printf '%s\n' "$actual_keys_raw" | LC_ALL=C sort)

  # Compute Missing = expected - actual; Unexpected = actual - expected.
  # Use comm against sorted streams; comm requires a sorted input pair.
  local missing unexpected
  missing=$(LC_ALL=C comm -23 <(printf '%s\n' "$expected_sorted") <(printf '%s\n' "$actual_sorted"))
  unexpected=$(LC_ALL=C comm -13 <(printf '%s\n' "$expected_sorted") <(printf '%s\n' "$actual_sorted"))
  # Strip stray blank lines (sort/comm round-trip can introduce one for empty input).
  missing=$(printf '%s' "$missing" | awk 'NF')
  unexpected=$(printf '%s' "$unexpected" | awk 'NF')

  if [[ -z "$missing" && -z "$unexpected" ]]; then
    # All expected keys present, no extras — pass silently.
    return 0
  fi

  # Build comma-separated, sorted lines for the diagnostic.
  local expected_csv actual_csv missing_csv unexpected_csv
  expected_csv=$(printf '%s' "$expected_sorted" | awk 'NF' | paste -sd, -)
  actual_csv=$(printf '%s' "$actual_sorted" | awk 'NF' | paste -sd, -)
  missing_csv=$(printf '%s' "$missing" | paste -sd, -)
  unexpected_csv=$(printf '%s' "$unexpected" | paste -sd, -)

  # Emit FR-H1-2 diagnostic to stderr. Missing / Unexpected lines are
  # OMITTED entirely (not "Missing: ") when their set is empty.
  {
    printf "Output schema violation in step '%s'.\n" "$step_id"
    printf "  Expected keys (from output_schema): %s\n" "$expected_csv"
    printf "  Actual keys in %s: %s\n" "$output_file_path" "$actual_csv"
    if [[ -n "$missing_csv" ]]; then
      printf "  Missing: %s\n" "$missing_csv"
    fi
    if [[ -n "$unexpected_csv" ]]; then
      printf "  Unexpected: %s\n" "$unexpected_csv"
    fi
    printf "Re-write the file with the expected keys and try again.\n"
  } >&2

  return 1
}
