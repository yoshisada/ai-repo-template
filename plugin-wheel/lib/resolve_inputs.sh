#!/usr/bin/env bash
# resolve_inputs.sh — wheel-step inputs resolver + output-schema extractor.
#
# Implements Themes G2 + G3 of
#   specs/wheel-step-input-output-schema/spec.md
# under the contract
#   specs/wheel-step-input-output-schema/contracts/interfaces.md §1, §2, §3, §7.
#
# Public entrypoints:
#   _parse_jsonpath_expr <expr>                                       (FR-G2-5; contract §1)
#   resolve_inputs       <step_json> <state_json> <workflow_json> <registry_json>   (FR-G3-1, FR-G3-4; contract §2)
#   extract_output_field <upstream_output> <output_schema_json> <field_name>         (FR-G1-2; contract §3)
#
# Single source of truth for the JSONPath subset grammar (I-PJ-3):
# `workflow.sh::workflow_validate_inputs_outputs` MUST source this file
# and call `_parse_jsonpath_expr` for shape-only validation. The resolver
# and the workflow-load validator share the SAME grammar function so
# error strings stay byte-identical (cross-plugin-resolver dual-gate
# pattern, lifted into this PRD per plan.md §3.A).
#
# Re-source guard: aligns with registry.sh / resolve.sh / preprocess.sh so
# engine.sh (and workflow.sh) can unconditionally `source` this file.

if [[ -n "${WHEEL_RESOLVE_INPUTS_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || true
fi
WHEEL_RESOLVE_INPUTS_SH_LOADED=1

# -----------------------------------------------------------------------------
# Allowlist — NFR-G-7 / OQ-G-1 Candidate A (default-deny, explicit opt-in).
#
# Spec-phase decision (specs/wheel-step-input-output-schema/spec.md §OQ-G-1):
# v1 ships with the small set below. Adding a key requires editing this file
# with a security-justification comment and going through code review with
# the `security` label per project policy (I-AL-3).
#
# JSON-file form `<file>:<jq-path>` is NOT allowlisted — the literal jq path
# in the workflow JSON is itself the auditable artifact (per spec §OQ-G-1).
# -----------------------------------------------------------------------------
declare -gA CONFIG_KEY_ALLOWLIST=(
  [".shelf-config:shelf_full_sync_counter"]="non-secret integer counter (full-sync cadence state)"
  [".shelf-config:shelf_full_sync_threshold"]="non-secret integer threshold (full-sync cadence config)"
  [".shelf-config:slug"]="non-secret project slug (used in Obsidian path computation)"
  [".shelf-config:base_path"]="non-secret filesystem path (Obsidian vault base)"
  [".shelf-config:obsidian_vault_path"]="non-secret filesystem path (full vault location)"
)

# -----------------------------------------------------------------------------
# _parse_jsonpath_expr — FR-G2-1..FR-G2-5 / contract §1.
#
# Pure function. Sets _PARSED_KIND / _PARSED_ARG1 / _PARSED_ARG2 globals on
# success; sets _PARSED_ERROR on failure. Silent on stdout AND stderr —
# callers decide whether to print the error.
#
# Grammar table (interfaces.md §1):
#   ^\$\.steps\.([A-Za-z0-9_-]+)\.output\.([A-Za-z0-9_-]+)$   → dollar_steps  (step-id, field)
#   ^\$config\(([^:)]+):([^)]+)\)$                            → dollar_config (file, key)
#   ^\$plugin\(([A-Za-z0-9_-]+)\)$                            → dollar_plugin (plugin-name, "")
#   ^\$step\(([A-Za-z0-9_-]+)\)$                              → dollar_step   (step-id, "")
#
# Args:
#   $1  expr   — JSONPath subset expression string
#
# Globals set on success (exit 0):
#   _PARSED_KIND, _PARSED_ARG1, _PARSED_ARG2
# Globals set on failure (exit 1):
#   _PARSED_ERROR
# -----------------------------------------------------------------------------
_parse_jsonpath_expr() {
  local expr="$1"

  # Reset all globals — idempotency invariant I-PJ-2.
  _PARSED_KIND=""
  _PARSED_ARG1=""
  _PARSED_ARG2=""
  _PARSED_ERROR=""

  # Pattern 1: $.steps.<step-id>.output.<field>
  if [[ "$expr" =~ ^\$\.steps\.([A-Za-z0-9_-]+)\.output\.([A-Za-z0-9_-]+)$ ]]; then
    _PARSED_KIND="dollar_steps"
    _PARSED_ARG1="${BASH_REMATCH[1]}"
    _PARSED_ARG2="${BASH_REMATCH[2]}"
    return 0
  fi

  # Pattern 2: $config(<file>:<key>)
  if [[ "$expr" =~ ^\$config\(([^:\)]+):([^\)]+)\)$ ]]; then
    _PARSED_KIND="dollar_config"
    _PARSED_ARG1="${BASH_REMATCH[1]}"
    _PARSED_ARG2="${BASH_REMATCH[2]}"
    return 0
  fi

  # Pattern 3: $plugin(<name>)
  if [[ "$expr" =~ ^\$plugin\(([A-Za-z0-9_-]+)\)$ ]]; then
    _PARSED_KIND="dollar_plugin"
    _PARSED_ARG1="${BASH_REMATCH[1]}"
    _PARSED_ARG2=""
    return 0
  fi

  # Pattern 4: $step(<step-id>)
  if [[ "$expr" =~ ^\$step\(([A-Za-z0-9_-]+)\)$ ]]; then
    _PARSED_KIND="dollar_step"
    _PARSED_ARG1="${BASH_REMATCH[1]}"
    _PARSED_ARG2=""
    return 0
  fi

  # Anything else → loud failure (FR-G2-5).
  _PARSED_ERROR="unsupported expression"
  return 1
}

# -----------------------------------------------------------------------------
# extract_output_field — FR-G1-2 / contract §3.
#
# Args:
#   $1  upstream_output       — string, raw output of the upstream step
#   $2  output_schema_json    — single-line JSON, the upstream step's output_schema field
#   $3  field_name            — string, the field to extract
#
# Stdout (on exit 0): the extracted value as a string.
# Stderr (on exit 1): contract §3 / FR-G2 documented error string.
#
# Extractor types (interfaces.md §3):
#   "$.foo.bar"                       → JSON path; jq -r '.foo.bar'
#   {"extract": "regex:<pattern>"}    → text; first match wins; capture group 1 if present
#   {"extract": "jq:<expr>"}          → JSON; jq -r '<expr>'
# -----------------------------------------------------------------------------
extract_output_field() {
  local upstream_output="$1"
  local output_schema_json="$2"
  local field_name="$3"

  # Pull the field's directive from the output_schema. jq returns "null" on
  # missing — we treat that as "field not in schema" (defense-in-depth; the
  # workflow_validate_inputs_outputs caller already catches this statically,
  # but runtime defends in case of stale state files).
  local directive
  directive=$(printf '%s' "$output_schema_json" | jq -c --arg f "$field_name" '.[$f] // null')

  if [[ "$directive" == "null" ]]; then
    echo "extract_output_field: field '${field_name}' not in upstream output_schema" >&2
    return 1
  fi

  # Determine the directive shape:
  #   - String starting with `$.`        → direct JSON path
  #   - Object with "extract" key        → regex: or jq: directive
  local directive_type
  directive_type=$(printf '%s' "$directive" | jq -r 'type')

  case "$directive_type" in
    string)
      # Direct JSON path. Strip the leading/trailing quotes via jq -r.
      local jq_path
      jq_path=$(printf '%s' "$directive" | jq -r '.')
      if [[ "$jq_path" != \$.* ]]; then
        echo "extract_output_field: field '${field_name}' has malformed JSON-path directive: '${jq_path}' (must start with \$.)" >&2
        return 1
      fi
      # Run jq against the upstream output.
      local extracted
      if ! extracted=$(printf '%s' "$upstream_output" | jq -r "$jq_path" 2>&1); then
        echo "extract_output_field: jq '${jq_path}' failed against step output: ${extracted}" >&2
        return 1
      fi
      if [[ "$extracted" == "null" ]]; then
        echo "extract_output_field: field '${field_name}' resolved to null in upstream output" >&2
        return 1
      fi
      printf '%s' "$extracted"
      return 0
      ;;
    object)
      local extract_directive
      extract_directive=$(printf '%s' "$directive" | jq -r '.extract // empty')
      if [[ -z "$extract_directive" ]]; then
        echo "extract_output_field: field '${field_name}' object directive missing 'extract' key" >&2
        return 1
      fi

      if [[ "$extract_directive" == regex:* ]]; then
        local pattern="${extract_directive#regex:}"
        # First match wins (I-EX-1 / contract §3 table). If the pattern has
        # a capture group, return capture #1; otherwise the whole match.
        # We use python3 (already a wheel runtime dep) for reliable PCRE-ish
        # behavior across BSD/GNU grep variants.
        local extracted
        extracted=$(PATTERN="$pattern" UPSTREAM="$upstream_output" python3 -c '
import os, re, sys
pat = os.environ["PATTERN"]
text = os.environ["UPSTREAM"]
try:
    rx = re.compile(pat, re.MULTILINE)
except re.error as e:
    sys.stderr.write(f"regex compile error: {e}\n")
    sys.exit(1)
m = rx.search(text)
if not m:
    sys.exit(2)
if m.groups():
    sys.stdout.write(m.group(1))
else:
    sys.stdout.write(m.group(0))
' 2>&1)
        local rc=$?
        if [[ $rc -eq 2 ]]; then
          echo "extract_output_field: regex '${pattern}' did not match step output for field '${field_name}'" >&2
          return 1
        fi
        if [[ $rc -ne 0 ]]; then
          echo "extract_output_field: regex extractor failed for field '${field_name}': ${extracted}" >&2
          return 1
        fi
        printf '%s' "$extracted"
        return 0
      elif [[ "$extract_directive" == jq:* ]]; then
        local jq_expr="${extract_directive#jq:}"
        local extracted
        if ! extracted=$(printf '%s' "$upstream_output" | jq -r "$jq_expr" 2>&1); then
          echo "extract_output_field: jq '${jq_expr}' failed for field '${field_name}': ${extracted}" >&2
          return 1
        fi
        if [[ "$extracted" == "null" ]]; then
          echo "extract_output_field: jq extractor resolved to null for field '${field_name}'" >&2
          return 1
        fi
        printf '%s' "$extracted"
        return 0
      else
        echo "extract_output_field: field '${field_name}' has malformed extract directive: '${extract_directive}' (expected regex:<pattern> or jq:<expr>)" >&2
        return 1
      fi
      ;;
    *)
      echo "extract_output_field: field '${field_name}' has unsupported directive type '${directive_type}'" >&2
      return 1
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Internal — read upstream step's output content (FR-G2-1 / sub-workflow alias).
#
# The state file records `steps[idx].output` as either a literal value OR a
# file path the agent wrote to. For `type: workflow` (sub-workflow) steps,
# the wheel-step itself often has no `output:` field — the sub-workflow
# writes its result under its OWN name (e.g. `shelf:shelf-write-issue-note`
# writes `.wheel/outputs/shelf-write-issue-note-result.json`). The resolver
# handles this aliasing transparently:
#
#   1. If state.steps[idx].output is a non-empty file path that exists, read it.
#   2. Else, if step.type == "workflow", derive the conventional sub-workflow
#      result path from step.workflow (`shelf:shelf-write-issue-note` →
#      `.wheel/outputs/shelf-write-issue-note-result.json`) and read that.
#   3. Else, treat state.steps[idx].output as a literal value.
#   4. On all-misses, return non-zero.
#
# Args:
#   $1  step_idx          — integer, index in state.steps[]
#   $2  state_json        — single-line JSON, parent state
#   $3  upstream_step_json — single-line JSON, the upstream step from workflow.steps[]
#
# Stdout: file contents OR literal value
# Exit:   0 on success, 1 if no readable upstream output
# -----------------------------------------------------------------------------
_read_upstream_output() {
  local step_idx="$1"
  local state_json="$2"
  local upstream_step_json="$3"

  local recorded
  recorded=$(printf '%s' "$state_json" | jq -r --argjson idx "$step_idx" '.steps[$idx].output // empty')

  if [[ -n "$recorded" && -f "$recorded" ]]; then
    cat "$recorded"
    return 0
  fi

  # Sub-workflow filename aliasing per researcher-baseline §Job 2.
  local upstream_type
  upstream_type=$(printf '%s' "$upstream_step_json" | jq -r '.type // ""')
  if [[ "$upstream_type" == "workflow" ]]; then
    local sub_wf
    sub_wf=$(printf '%s' "$upstream_step_json" | jq -r '.workflow // ""')
    # Strip plugin prefix: `shelf:shelf-write-issue-note` → `shelf-write-issue-note`.
    local sub_wf_name="${sub_wf##*:}"
    local conv_path=".wheel/outputs/${sub_wf_name}-result.json"
    if [[ -f "$conv_path" ]]; then
      cat "$conv_path"
      return 0
    fi
  fi

  # Last-resort fallback: treat recorded value as a literal (in-memory string).
  if [[ -n "$recorded" ]]; then
    printf '%s' "$recorded"
    return 0
  fi

  return 1
}

# -----------------------------------------------------------------------------
# resolve_inputs — FR-G3-1 / FR-G3-4 / contract §2.
#
# Iterates `step.inputs`, dispatches each via `_parse_jsonpath_expr`, resolves
# each expression, returns a single-line JSON object with the resolved map.
#
# Args:
#   $1  step_json       — single-line JSON, the agent step from workflow.steps[]
#   $2  state_json      — single-line JSON, parent workflow state
#   $3  workflow_json   — single-line JSON, the templated workflow
#   $4  registry_json   — single-line JSON, output of build_session_registry
#
# Stdout (on exit 0): single-line JSON `{ "<VAR>": "<resolved>", ... }` (or `{}`).
# Stderr (on exit 1): ONE line matching one of the contract §2 error shapes.
# -----------------------------------------------------------------------------
resolve_inputs() {
  local step_json="$1"
  local state_json="$2"
  local workflow_json="$3"
  local registry_json="$4"

  # Pull workflow + step identifiers for error messages.
  local wf_name step_id
  wf_name=$(printf '%s' "$workflow_json" | jq -r '.name // "unnamed"')
  step_id=$(printf '%s' "$step_json" | jq -r '.id // "?"')

  # No-op fast path (I-RI-5 / NFR-G-5 ≤5ms).
  local inputs_json
  inputs_json=$(printf '%s' "$step_json" | jq -c '.inputs // {}')
  if [[ "$inputs_json" == "{}" || -z "$inputs_json" ]]; then
    echo '{}'
    return 0
  fi

  # Iterate keys in sorted order for deterministic resolved-map ordering.
  local var_names
  var_names=$(printf '%s' "$inputs_json" | jq -r 'keys_unsorted[]')

  # Build the resolved map incrementally as JSON. Use jq to handle escaping.
  local resolved_map='{}'

  local var_name expr resolved_value

  while IFS= read -r var_name; do
    [[ -z "$var_name" ]] && continue

    expr=$(printf '%s' "$inputs_json" | jq -r --arg k "$var_name" '.[$k]')

    if ! _parse_jsonpath_expr "$expr"; then
      printf "Workflow '%s' step '%s' input '%s' uses unsupported expression: '%s'. Supported: \$.steps.<id>.output.<field>, \$config(<file>:<key>), \$plugin(<name>), \$step(<id>).\n" \
        "$wf_name" "$step_id" "$var_name" "$expr" >&2
      return 1
    fi

    case "$_PARSED_KIND" in
      dollar_steps)
        local upstream_step_id="$_PARSED_ARG1"
        local field_name="$_PARSED_ARG2"

        # Locate the upstream step in workflow.steps[].
        local upstream_idx
        upstream_idx=$(printf '%s' "$workflow_json" | jq --arg id "$upstream_step_id" '[.steps[].id] | index($id)')
        if [[ "$upstream_idx" == "null" || -z "$upstream_idx" ]]; then
          printf "Workflow '%s' step '%s' input '%s' references missing upstream output: step '%s' has not run or has no output_schema declaration.\n" \
            "$wf_name" "$step_id" "$var_name" "$upstream_step_id" >&2
          return 1
        fi

        # Confirm upstream has run (status: done).
        local upstream_status
        upstream_status=$(printf '%s' "$state_json" | jq -r --argjson idx "$upstream_idx" '.steps[$idx].status // ""')
        if [[ "$upstream_status" != "done" ]]; then
          printf "Workflow '%s' step '%s' input '%s' references missing upstream output: step '%s' has not run or has no output_schema declaration.\n" \
            "$wf_name" "$step_id" "$var_name" "$upstream_step_id" >&2
          return 1
        fi

        # Pull the upstream step's output_schema.
        local upstream_step
        upstream_step=$(printf '%s' "$workflow_json" | jq -c --argjson idx "$upstream_idx" '.steps[$idx]')
        local upstream_schema
        upstream_schema=$(printf '%s' "$upstream_step" | jq -c '.output_schema // null')
        if [[ "$upstream_schema" == "null" ]]; then
          printf "Workflow '%s' step '%s' input '%s' references missing upstream output: step '%s' has not run or has no output_schema declaration.\n" \
            "$wf_name" "$step_id" "$var_name" "$upstream_step_id" >&2
          return 1
        fi

        # Read the upstream output (handles sub-workflow filename aliasing).
        local upstream_output
        if ! upstream_output=$(_read_upstream_output "$upstream_idx" "$state_json" "$upstream_step"); then
          printf "Workflow '%s' step '%s' input '%s' references missing upstream output: step '%s' has not run or has no output_schema declaration.\n" \
            "$wf_name" "$step_id" "$var_name" "$upstream_step_id" >&2
          return 1
        fi

        # Extract the field per the schema.
        if ! resolved_value=$(extract_output_field "$upstream_output" "$upstream_schema" "$field_name" 2>/dev/null); then
          # Distinguish "field not in schema" (validation drift) vs "regex did not match" (data error).
          local schema_has_field
          schema_has_field=$(printf '%s' "$upstream_schema" | jq -r --arg f "$field_name" 'has($f)')
          if [[ "$schema_has_field" != "true" ]]; then
            printf "Workflow '%s' step '%s' input '%s' references field '%s' of step '%s' but '%s' is not in that step's output_schema.\n" \
              "$wf_name" "$step_id" "$var_name" "$field_name" "$upstream_step_id" "$field_name" >&2
          else
            printf "Workflow '%s' step '%s' input '%s' resolves regex extractor against step '%s' output but pattern did not match.\n" \
              "$wf_name" "$step_id" "$var_name" "$upstream_step_id" >&2
          fi
          return 1
        fi
        ;;

      dollar_config)
        local cfg_file="$_PARSED_ARG1"
        local cfg_key="$_PARSED_ARG2"

        # Allowlist gate (I-AL-1 / NFR-G-7) — fail BEFORE any file read.
        # JSON file form (`<file>:<jq-path>`, where the key starts with `.`)
        # is exempt from the flat allowlist (the literal jq path is the gate).
        local is_jq_path=0
        if [[ "$cfg_key" == .* ]]; then
          is_jq_path=1
        fi

        if [[ $is_jq_path -eq 0 ]]; then
          local allowlist_lookup="${cfg_file}:${cfg_key}"
          if [[ -z "${CONFIG_KEY_ALLOWLIST[$allowlist_lookup]:-}" ]]; then
            printf "Workflow '%s' step '%s' input '%s' resolves \$config(%s:%s) but '%s' is not in the safe-key allowlist for %s. Add it to plugin-wheel/lib/resolve_inputs.sh::CONFIG_KEY_ALLOWLIST after security review, or use \$step()/\$.steps.* for non-config values.\n" \
              "$wf_name" "$step_id" "$var_name" "$cfg_file" "$cfg_key" "$cfg_key" "$cfg_file" >&2
            return 1
          fi
        fi

        # Existence gate.
        if [[ ! -f "$cfg_file" ]]; then
          printf "Workflow '%s' step '%s' input '%s' resolves \$config(%s:%s) but config file '%s' not found.\n" \
            "$wf_name" "$step_id" "$var_name" "$cfg_file" "$cfg_key" "$cfg_file" >&2
          return 1
        fi

        if [[ $is_jq_path -eq 1 ]]; then
          # JSON file form — feed the jq path to jq -r.
          local jq_out
          if ! jq_out=$(jq -r "$cfg_key" "$cfg_file" 2>&1); then
            printf "Workflow '%s' step '%s' input '%s' resolves \$config(%s:%s) but key '%s' not found in '%s'.\n" \
              "$wf_name" "$step_id" "$var_name" "$cfg_file" "$cfg_key" "$cfg_key" "$cfg_file" >&2
            return 1
          fi
          if [[ "$jq_out" == "null" || -z "$jq_out" ]]; then
            printf "Workflow '%s' step '%s' input '%s' resolves \$config(%s:%s) but key '%s' not found in '%s'.\n" \
              "$wf_name" "$step_id" "$var_name" "$cfg_file" "$cfg_key" "$cfg_key" "$cfg_file" >&2
            return 1
          fi
          resolved_value="$jq_out"
        else
          # Flat config (.shelf-config) — `key = value` lines, `key=value` also accepted.
          # Match the `shelf-counter.sh read` shape (interfaces.md §2 + spec.md FR-G2-2).
          # Pattern: optional whitespace, key, optional whitespace, `=`, optional whitespace, value.
          local val
          val=$(awk -v key="$cfg_key" '
            BEGIN { found=0 }
            {
              line=$0
              # Strip leading/trailing whitespace.
              sub(/^[ \t]+/, "", line)
              sub(/[ \t]+$/, "", line)
              # Skip blanks + comments.
              if (line == "" || line ~ /^#/) next
              # Match `key = value` or `key=value`.
              n = index(line, "=")
              if (n == 0) next
              k = substr(line, 1, n-1)
              v = substr(line, n+1)
              # Strip whitespace around k + v.
              sub(/[ \t]+$/, "", k)
              sub(/^[ \t]+/, "", v)
              sub(/[ \t]+$/, "", v)
              if (k == key) { print v; found=1; exit }
            }
            END { if (!found) exit 2 }
          ' "$cfg_file" 2>/dev/null)
          local awk_rc=$?
          if [[ $awk_rc -ne 0 ]]; then
            printf "Workflow '%s' step '%s' input '%s' resolves \$config(%s:%s) but key '%s' not found in '%s'.\n" \
              "$wf_name" "$step_id" "$var_name" "$cfg_file" "$cfg_key" "$cfg_key" "$cfg_file" >&2
            return 1
          fi
          resolved_value="$val"
        fi
        ;;

      dollar_plugin)
        local plugin_name="$_PARSED_ARG1"
        local plugin_path
        plugin_path=$(printf '%s' "$registry_json" | jq -r --arg n "$plugin_name" '.plugins[$n] // empty')
        if [[ -z "$plugin_path" ]]; then
          printf "Workflow '%s' step '%s' input '%s' resolves \$plugin(%s) but '%s' is not in this session's registry.\n" \
            "$wf_name" "$step_id" "$var_name" "$plugin_name" "$plugin_name" >&2
          return 1
        fi
        resolved_value="$plugin_path"
        ;;

      dollar_step)
        local upstream_step_id="$_PARSED_ARG1"
        local upstream_idx
        upstream_idx=$(printf '%s' "$workflow_json" | jq --arg id "$upstream_step_id" '[.steps[].id] | index($id)')
        if [[ "$upstream_idx" == "null" || -z "$upstream_idx" ]]; then
          printf "Workflow '%s' step '%s' input '%s' references missing upstream output: step '%s' has not run or has no output_schema declaration.\n" \
            "$wf_name" "$step_id" "$var_name" "$upstream_step_id" >&2
          return 1
        fi
        local recorded
        recorded=$(printf '%s' "$state_json" | jq -r --argjson idx "$upstream_idx" '.steps[$idx].output // empty')
        if [[ -z "$recorded" ]]; then
          # Sub-workflow alias fallback.
          local upstream_step
          upstream_step=$(printf '%s' "$workflow_json" | jq -c --argjson idx "$upstream_idx" '.steps[$idx]')
          local upstream_type
          upstream_type=$(printf '%s' "$upstream_step" | jq -r '.type // ""')
          if [[ "$upstream_type" == "workflow" ]]; then
            local sub_wf
            sub_wf=$(printf '%s' "$upstream_step" | jq -r '.workflow // ""')
            local sub_wf_name="${sub_wf##*:}"
            recorded=".wheel/outputs/${sub_wf_name}-result.json"
          fi
        fi
        if [[ -z "$recorded" ]]; then
          printf "Workflow '%s' step '%s' input '%s' references missing upstream output: step '%s' has not run or has no output_schema declaration.\n" \
            "$wf_name" "$step_id" "$var_name" "$upstream_step_id" >&2
          return 1
        fi
        resolved_value="$recorded"
        ;;
    esac

    # Append to resolved_map atomically.
    resolved_map=$(printf '%s' "$resolved_map" | jq -c --arg k "$var_name" --arg v "$resolved_value" '.[$k] = $v')

  done <<< "$var_names"

  printf '%s' "$resolved_map"
  return 0
}
