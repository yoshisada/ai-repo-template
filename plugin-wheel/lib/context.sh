#!/usr/bin/env bash
# context.sh — Context injection and output capture for step transitions
# FR-027/028: Per-step context injection and step output capture

# FR-027: Build the context payload for an agent step
# Assembles: step instruction + outputs from dependency steps
# Params: $1 = step JSON, $2 = state JSON (string), $3 = workflow JSON (string)
#         $4 = resolved_map_json (string, optional) — output of resolve_inputs
#              (specs/wheel-step-input-output-schema FR-G3-2; contract §2/§4).
#              When non-empty AND step.inputs is declared, prepends the
#              "## Resolved Inputs" block AND substitutes {{VAR}} placeholders
#              in the instruction body (FR-G3-3) AND suppresses the legacy
#              "## Context from Previous Steps" footer (FR-G1-3).
# Output (stdout): context string to inject as additionalContext
# Exit: 0 on success, 1 on hydration tripwire failure (FR-G3-5).
context_build() {
  local step_json="$1"
  local state_json="$2"
  local workflow_json="$3"
  local resolved_map_json="${4:-}"

  local instruction
  instruction=$(printf '%s\n' "$step_json" | jq -r '.instruction // empty')

  # specs/wheel-step-input-output-schema FR-G3-3 / FR-G3-5 — substitute
  # {{VAR}} placeholders in the instruction body using the resolved map,
  # then enforce the post-substitution tripwire. Failure exits 1; the
  # dispatch caller marks the step failed and aborts.
  if [[ -n "$resolved_map_json" && "$resolved_map_json" != "{}" && -n "$instruction" ]]; then
    local _step_id
    _step_id=$(printf '%s\n' "$step_json" | jq -r '.id // "?"')
    local _substituted
    if ! _substituted=$(substitute_inputs_into_instruction "$instruction" "$resolved_map_json" "$_step_id"); then
      return 1
    fi
    instruction="$_substituted"
  fi

  # Determine whether to suppress the legacy "## Context from Previous Steps"
  # footer (FR-G1-3): suppression triggers when the step declares non-empty
  # `inputs:`. This preserves NFR-G-3 byte-identical behavior for unmigrated
  # workflows (no `inputs:` → footer behavior unchanged).
  local _has_inputs
  _has_inputs=$(printf '%s\n' "$step_json" | jq -r 'if (.inputs // {}) | length > 0 then "yes" else "no" end')

  # Collect outputs from context_from dependencies
  local context_from
  context_from=$(printf '%s\n' "$step_json" | jq -r '.context_from // [] | .[]')

  # FR-F4-3 / T042 (specs/cross-plugin-resolver-and-preflight-registry):
  # Theme D Option B's runtime_env_block emission is REMOVED. Theme F4's
  # preprocessor (`plugin-wheel/lib/preprocess.sh::template_workflow_json`)
  # now substitutes the absolute path of every plugin path token directly
  # into the agent step's `.instruction` field BEFORE state_init. By the
  # time `context_build` runs, the instruction already contains literal
  # absolute paths — the explicit "## Runtime Environment" header is
  # redundant.
  #
  # The Theme D contract (FR-D1: bg sub-agents must see WORKFLOW_PLUGIN_DIR
  # as a usable absolute path) is preserved by construction: if the workflow
  # author wrote `${WORKFLOW_PLUGIN_DIR}/scripts/foo.sh` in the instruction,
  # the preprocessor swapped that for the literal path. The bg sub-agent
  # reads the path verbatim from the instruction text and runs the script
  # with no env-var propagation needed. NFR-F-5 (back-compat for workflows
  # without `requires_plugins`) still holds because the preprocessor passes
  # the legacy `${WORKFLOW_PLUGIN_DIR}` token through the same substitution
  # code path as `${WHEEL_PLUGIN_<calling-plugin>}`.

  local context_parts=""

  # specs/wheel-step-input-output-schema FR-G3-2 — emit the "## Resolved
  # Inputs" block FIRST (before "## Step Instruction") when inputs:
  # resolved successfully. The block is the canonical record of what the
  # resolver produced; downstream agents read it as-is.
  if [[ -n "$resolved_map_json" && "$resolved_map_json" != "{}" ]]; then
    local _resolved_block
    _resolved_block=$(printf '%s' "$resolved_map_json" | jq -r '
      "## Resolved Inputs\n" +
      ([to_entries[] | "- **" + .key + "**: " + (.value | tostring)] | join("\n"))
    ' 2>/dev/null)
    if [[ -n "$_resolved_block" ]]; then
      context_parts="${_resolved_block}\n\n"
    fi
  fi

  if [[ -n "$instruction" ]]; then
    context_parts="${context_parts}## Step Instruction\n\n${instruction}"
  fi

  # specs/wheel-step-input-output-schema FR-G1-3 — suppress the legacy
  # "## Context from Previous Steps" footer when inputs: is declared and
  # non-empty (the resolved-inputs block replaces it). When inputs: is
  # absent (or empty), preserve today's footer behavior byte-identically
  # (NFR-G-3 backward compat).
  if [[ "$_has_inputs" == "yes" ]]; then
    context_from=""
  fi

  if [[ -n "$context_from" ]]; then
    context_parts="${context_parts}\n\n## Context from Previous Steps\n"
    while IFS= read -r dep_id; do
      [[ -z "$dep_id" ]] && continue
      # FR-031: Handle synthetic step IDs _context and _assignment
      if [[ "$dep_id" == "_context" || "$dep_id" == "_assignment" ]]; then
        local synthetic_output
        synthetic_output=$(context_resolve_synthetic "$dep_id" "$state_json")
        if [[ -n "$synthetic_output" ]]; then
          context_parts="${context_parts}\n\n### Output from step: ${dep_id}\n${synthetic_output}"
        fi
        continue
      fi
      local dep_index
      dep_index=$(printf '%s\n' "$workflow_json" | jq --arg id "$dep_id" '[.steps[].id] | index($id)')
      if [[ "$dep_index" != "null" && -n "$dep_index" ]]; then
        local dep_output
        dep_output=$(printf '%s\n' "$state_json" | jq -r --argjson idx "$dep_index" '.steps[$idx].output // empty')
        if [[ -n "$dep_output" ]]; then
          context_parts="${context_parts}\n\n### Output from step: ${dep_id}\n${dep_output}"
        fi
      fi
    done <<< "$context_from"
  fi

  # FR-009 (wheel-user-input): When the step opts into user input via
  # `allow_user_input: true`, append the verbatim instruction block so the
  # agent discovers the primitive. Without this nudge, agents won't run
  # `wheel flag-needs-input` even on permitted steps.
  local _allow
  _allow=$(printf '%s\n' "$step_json" | jq -r '.allow_user_input // false')
  if [[ "$_allow" == "true" ]]; then
    context_parts="${context_parts}\n\n---\n**This step permits user input.** If you cannot resolve this step from repo state alone, you MAY output your question to the user and then run \`wheel flag-needs-input \"<short reason>\"\` (or the absolute-path form \`plugin-wheel/bin/wheel-flag-needs-input \"<short reason>\"\`) before ending your turn. The Stop hook will stay silent until you write the step output. If the question is unnecessary, skip it and write the output directly — pausing is a last resort."
  fi

  printf '%b' "$context_parts"
}

# FR-028: Capture and store step output
# Params: $1 = state file path, $2 = step index, $3 = output value or file path
# Output: none (updates state file via state_set_step_output)
# Exit: 0
context_capture_output() {
  local state_file="$1"
  local step_index="$2"
  local output_value="$3"
  state_set_step_output "$state_file" "$step_index" "$output_value"
}

# FR-006: Build additionalContext for SubagentStart hook
# Params: $1 = step JSON, $2 = state JSON, $3 = workflow JSON, $4 = agent_type
# Output (stdout): JSON additionalContext string
# Exit: 0
context_subagent_start() {
  local step_json="$1"
  local state_json="$2"
  local workflow_json="$3"
  local agent_type="$4"

  local step_type
  step_type=$(printf '%s\n' "$step_json" | jq -r '.type')

  local instruction=""
  if [[ "$step_type" == "parallel" ]]; then
    # Get agent-specific instruction from agent_instructions map
    instruction=$(printf '%s\n' "$step_json" | jq -r --arg agent "$agent_type" '.agent_instructions[$agent] // .instruction // empty')
  else
    instruction=$(printf '%s\n' "$step_json" | jq -r '.instruction // empty')
  fi

  # Build context from dependencies
  local dep_context
  dep_context=$(context_build "$step_json" "$state_json" "$workflow_json")

  # If we have agent-specific instruction, override the generic one in context
  if [[ -n "$instruction" && "$step_type" == "parallel" ]]; then
    local context_from_deps=""
    local context_from
    context_from=$(printf '%s\n' "$step_json" | jq -r '.context_from // [] | .[]')
    if [[ -n "$context_from" ]]; then
      context_from_deps="\n\n## Context from Previous Steps\n"
      while IFS= read -r dep_id; do
        [[ -z "$dep_id" ]] && continue
        local dep_index
        dep_index=$(printf '%s\n' "$workflow_json" | jq --arg id "$dep_id" '[.steps[].id] | index($id)')
        if [[ "$dep_index" != "null" && -n "$dep_index" ]]; then
          local dep_output
          dep_output=$(printf '%s\n' "$state_json" | jq -r --argjson idx "$dep_index" '.steps[$idx].output // empty')
          if [[ -n "$dep_output" ]]; then
            context_from_deps="${context_from_deps}\n\n### Output from step: ${dep_id}\n${dep_output}"
          fi
        fi
      done <<< "$context_from"
    fi
    printf '%b' "## Step Instruction\n\n${instruction}${context_from_deps}"
  else
    printf '%s\n' "$dep_context"
  fi
}

# FR-029/FR-030: Write context.json and assignment.json for a teammate before spawning
# Params:
#   $1 = output_dir (string) — teammate output directory
#   $2 = state_json (string) — parent workflow state
#   $3 = workflow_json (string) — parent workflow definition
#   $4 = context_from_json (string) — JSON array of step IDs (may be "[]")
#   $5 = assign_json (string) — assignment payload JSON (may be "{}")
# Output: none (writes files to output_dir)
# Exit: 0 on success, 1 on failure
context_write_teammate_files() {
  local output_dir="$1"
  local state_json="$2"
  local workflow_json="$3"
  local context_from_json="$4"
  local assign_json="${5:-"{}"}"

  mkdir -p "$output_dir"

  # FR-029: Write context.json — combined outputs from context_from steps
  local context_data='{}'
  local dep_ids
  dep_ids=$(printf '%s\n' "$context_from_json" | jq -r '.[]' 2>/dev/null)
  if [[ -n "$dep_ids" ]]; then
    while IFS= read -r dep_id; do
      [[ -z "$dep_id" ]] && continue
      local dep_index
      dep_index=$(printf '%s\n' "$workflow_json" | jq --arg id "$dep_id" '[.steps[].id] | index($id)')
      if [[ "$dep_index" != "null" && -n "$dep_index" ]]; then
        local dep_output
        dep_output=$(printf '%s\n' "$state_json" | jq -r --argjson idx "$dep_index" '.steps[$idx].output // empty')
        if [[ -n "$dep_output" ]]; then
          # If the output is a file path and the file exists, read the contents
          if [[ -f "$dep_output" ]]; then
            local file_contents
            file_contents=$(cat "$dep_output" 2>/dev/null || echo "")
            context_data=$(printf '%s\n' "$context_data" | jq --arg id "$dep_id" --arg val "$file_contents" '.[$id] = $val')
          else
            context_data=$(printf '%s\n' "$context_data" | jq --arg id "$dep_id" --arg val "$dep_output" '.[$id] = $val')
          fi
        fi
      fi
    done <<< "$dep_ids"
  fi
  printf '%s\n' "$context_data" > "${output_dir}/context.json"

  # FR-030: Write assignment.json
  printf '%s\n' "$assign_json" > "${output_dir}/assignment.json"
}

# FR-031: Resolve synthetic step IDs _context and _assignment for sub-workflows
# Called by context_build() when it encounters these special IDs in context_from.
# Reads context.json or assignment.json from the agent's output directory.
# The output directory is determined from the state file's parent_workflow and
# teams data, or from the agent_id-based output dir convention.
#
# Params:
#   $1 = synthetic_id (string) — "_context" or "_assignment"
#   $2 = state_json (string) — sub-workflow state JSON
# Output (stdout): file contents of the referenced file
# Exit: 0 if found, 1 if not found
context_resolve_synthetic() {
  local synthetic_id="$1"
  local state_json="$2"

  local filename
  case "$synthetic_id" in
    _context)    filename="context.json" ;;
    _assignment) filename="assignment.json" ;;
    *)           return 1 ;;
  esac

  # Determine the agent's output directory from the state file
  # The agent_id in the state file corresponds to the teammate name
  local agent_id
  agent_id=$(printf '%s\n' "$state_json" | jq -r '.owner_agent_id // empty')
  if [[ -z "$agent_id" ]]; then
    return 1
  fi

  # Look for the file in the parent workflow's team output directory
  local parent_state_path
  parent_state_path=$(printf '%s\n' "$state_json" | jq -r '.parent_workflow // empty')
  if [[ -n "$parent_state_path" && -f "$parent_state_path" ]]; then
    local parent_state
    parent_state=$(cat "$parent_state_path" 2>/dev/null) || return 1
    # Search all teams' teammates for this agent_id
    local output_dir
    output_dir=$(printf '%s\n' "$parent_state" | jq -r --arg aid "$agent_id" \
      '[.teams // {} | to_entries[] | .value.teammates // {} | to_entries[] | select(.value.agent_id == $aid) | .value.output_dir] | first // empty')
    if [[ -n "$output_dir" && -f "${output_dir}/${filename}" ]]; then
      cat "${output_dir}/${filename}"
      return 0
    fi
  fi

  # Fallback: search .wheel/outputs/ for a directory matching agent_id
  local search_file
  search_file=$(find .wheel/outputs/ -path "*/${agent_id}/${filename}" 2>/dev/null | head -1)
  if [[ -n "$search_file" && -f "$search_file" ]]; then
    cat "$search_file"
    return 0
  fi

  return 1
}
