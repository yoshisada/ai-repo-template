#!/usr/bin/env bash
# context.sh — Context injection and output capture for step transitions
# FR-027/028: Per-step context injection and step output capture

# FR-027: Build the context payload for an agent step
# Assembles: step instruction + outputs from dependency steps
# Params: $1 = step JSON, $2 = state JSON (string), $3 = workflow JSON (string)
# Output (stdout): context string to inject as additionalContext
# Exit: 0
context_build() {
  local step_json="$1"
  local state_json="$2"
  local workflow_json="$3"

  local instruction
  instruction=$(echo "$step_json" | jq -r '.instruction // empty')

  # Collect outputs from context_from dependencies
  local context_from
  context_from=$(echo "$step_json" | jq -r '.context_from // [] | .[]')

  local context_parts=""
  if [[ -n "$instruction" ]]; then
    context_parts="## Step Instruction\n\n${instruction}"
  fi

  if [[ -n "$context_from" ]]; then
    context_parts="${context_parts}\n\n## Context from Previous Steps\n"
    while IFS= read -r dep_id; do
      [[ -z "$dep_id" ]] && continue
      local dep_index
      dep_index=$(echo "$workflow_json" | jq --arg id "$dep_id" '[.steps[].id] | index($id)')
      if [[ "$dep_index" != "null" && -n "$dep_index" ]]; then
        local dep_output
        dep_output=$(echo "$state_json" | jq -r --argjson idx "$dep_index" '.steps[$idx].output // empty')
        if [[ -n "$dep_output" ]]; then
          context_parts="${context_parts}\n\n### Output from step: ${dep_id}\n${dep_output}"
        fi
      fi
    done <<< "$context_from"
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
  step_type=$(echo "$step_json" | jq -r '.type')

  local instruction=""
  if [[ "$step_type" == "parallel" ]]; then
    # Get agent-specific instruction from agent_instructions map
    instruction=$(echo "$step_json" | jq -r --arg agent "$agent_type" '.agent_instructions[$agent] // .instruction // empty')
  else
    instruction=$(echo "$step_json" | jq -r '.instruction // empty')
  fi

  # Build context from dependencies
  local dep_context
  dep_context=$(context_build "$step_json" "$state_json" "$workflow_json")

  # If we have agent-specific instruction, override the generic one in context
  if [[ -n "$instruction" && "$step_type" == "parallel" ]]; then
    local context_from_deps=""
    local context_from
    context_from=$(echo "$step_json" | jq -r '.context_from // [] | .[]')
    if [[ -n "$context_from" ]]; then
      context_from_deps="\n\n## Context from Previous Steps\n"
      while IFS= read -r dep_id; do
        [[ -z "$dep_id" ]] && continue
        local dep_index
        dep_index=$(echo "$workflow_json" | jq --arg id "$dep_id" '[.steps[].id] | index($id)')
        if [[ "$dep_index" != "null" && -n "$dep_index" ]]; then
          local dep_output
          dep_output=$(echo "$state_json" | jq -r --argjson idx "$dep_index" '.steps[$idx].output // empty')
          if [[ -n "$dep_output" ]]; then
            context_from_deps="${context_from_deps}\n\n### Output from step: ${dep_id}\n${dep_output}"
          fi
        fi
      done <<< "$context_from"
    fi
    printf '%b' "## Step Instruction\n\n${instruction}${context_from_deps}"
  else
    echo "$dep_context"
  fi
}
