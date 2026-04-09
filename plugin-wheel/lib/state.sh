#!/usr/bin/env bash
# state.sh — State persistence for .wheel/state.json
# FR-002: Read, write, and query workflow execution state

# FR-002: Read the full state.json and output it
# Params: $1 = state file path
# Output (stdout): full state.json contents
# Exit: 0 on success, 1 if file missing or invalid JSON
state_read() {
  local state_file="$1"
  if [[ ! -f "$state_file" ]]; then
    echo "ERROR: state file not found: $state_file" >&2
    return 1
  fi
  if ! jq empty "$state_file" 2>/dev/null; then
    echo "ERROR: invalid JSON in state file: $state_file" >&2
    return 1
  fi
  jq -c '.' "$state_file"
}

# FR-002: Write state.json atomically (write to tmp, then mv)
# Params: $1 = state file path, $2 = new state JSON (string)
# Output: none
# Exit: 0 on success, 1 on write failure
state_write() {
  local state_file="$1"
  local new_state="$2"
  local tmp_file
  tmp_file=$(mktemp "${state_file}.tmp.XXXXXX") || return 1
  if ! printf '%s\n' "$new_state" > "$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi
  mv "$tmp_file" "$state_file" || return 1
}

# FR-011/FR-016: Initialize a new state file from a workflow definition.
# Called by the PostToolUse hook after intercepting activate.sh, which provides
# session_id and agent_id from hook input for proper ownership.
#
# Params:
#   $1 = state_file (string) — full path to the state file to create
#   $2 = workflow_json (string) — validated workflow JSON
#   $3 = session_id (string) — owner session ID
#   $4 = agent_id (string) — owner agent ID (may be empty for main orchestrator)
#   $5 = workflow_file (string, optional) — path to workflow file
#   $6 = parent_workflow (string, optional) — path to parent state file (FR-016)
#
# Output: none (creates state file at the given path)
# Exit: 0 on success, 1 on failure
state_init() {
  local state_file="$1"
  local workflow_json="$2"
  local session_id="$3"
  local agent_id="${4:-}"
  local workflow_file="${5:-}"
  local parent_workflow="${6:-}"

  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  local wf_name wf_version step_count
  wf_name=$(printf '%s\n' "$workflow_json" | jq -r '.name // "unnamed"')
  wf_version=$(printf '%s\n' "$workflow_json" | jq -r '.version // "0.0.0"')
  step_count=$(printf '%s\n' "$workflow_json" | jq '.steps | length')

  # Build steps array from workflow definition
  local steps_json
  steps_json=$(printf '%s\n' "$workflow_json" | jq --arg now "$now" '[
    .steps[] | {
      id: .id,
      type: .type,
      status: "pending",
      started_at: null,
      completed_at: null,
      output: null,
      command_log: [],
      agents: (if .type == "parallel" then
        (.agents // [] | map({key: ., value: {status: "pending", started_at: null, completed_at: null}}) | from_entries)
      else {} end),
      loop_iteration: 0
    }
  ]')

  # FR-016: Include parent_workflow field when provided
  local state
  state=$(jq -n \
    --arg name "$wf_name" \
    --arg version "$wf_version" \
    --arg wf_file "$workflow_file" \
    --arg sid "$session_id" \
    --arg aid "$agent_id" \
    --arg now "$now" \
    --arg parent "$parent_workflow" \
    --argjson steps "$steps_json" \
    '{
      workflow_name: $name,
      workflow_version: $version,
      workflow_file: $wf_file,
      status: "running",
      cursor: 0,
      owner_session_id: $sid,
      owner_agent_id: $aid,
      started_at: $now,
      updated_at: $now,
      steps: $steps
    } + (if $parent != "" then {parent_workflow: $parent} else {} end)')

  mkdir -p "$(dirname "$state_file")"
  state_write "$state_file" "$state"
}

# FR-002: Get the current step index from state
# Params: $1 = state JSON (string)
# Output (stdout): integer step index (0-based)
# Exit: 0
state_get_cursor() {
  local state_json="$1"
  printf '%s\n' "$state_json" | jq -r '.cursor'
}

# FR-002: Advance the step cursor to a specific index
# Params: $1 = state file path, $2 = target step index
# Output: none (updates state file)
# Exit: 0 on success, 1 on failure
state_set_cursor() {
  local state_file="$1"
  local target_index="$2"
  local state
  state=$(state_read "$state_file") || return 1
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  local updated
  updated=$(printf '%s\n' "$state" | jq \
    --argjson idx "$target_index" \
    --arg now "$now" \
    '.cursor = $idx | .updated_at = $now')
  state_write "$state_file" "$updated"
}

# FR-002/011: Get the status of a specific step
# Params: $1 = state JSON (string), $2 = step index
# Output (stdout): status string (pending|working|done|failed)
# Exit: 0
state_get_step_status() {
  local state_json="$1"
  local step_index="$2"
  printf '%s\n' "$state_json" | jq -r --argjson idx "$step_index" '.steps[$idx].status'
}

# FR-002/011: Set the status of a specific step
# Params: $1 = state file path, $2 = step index, $3 = new status
# Output: none (updates state file)
# Exit: 0 on success, 1 on failure
state_set_step_status() {
  local state_file="$1"
  local step_index="$2"
  local new_status="$3"
  local state
  state=$(state_read "$state_file") || return 1
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  local updated
  updated=$(printf '%s\n' "$state" | jq \
    --argjson idx "$step_index" \
    --arg status "$new_status" \
    --arg now "$now" \
    '.steps[$idx].status = $status | .updated_at = $now |
     if $status == "working" then .steps[$idx].started_at = $now
     elif ($status == "done" or $status == "failed") then .steps[$idx].completed_at = $now
     else . end')
  state_write "$state_file" "$updated"
}

# FR-011: Get the status of a specific agent within a parallel step
# Params: $1 = state JSON (string), $2 = step index, $3 = agent_type
# Output (stdout): status string (working|idle|done|failed)
# Exit: 0 if agent found, 1 if not found
state_get_agent_status() {
  local state_json="$1"
  local step_index="$2"
  local agent_type="$3"
  local result
  result=$(printf '%s\n' "$state_json" | jq -r \
    --argjson idx "$step_index" \
    --arg agent "$agent_type" \
    '.steps[$idx].agents[$agent].status // empty')
  if [[ -z "$result" ]]; then
    echo "ERROR: agent not found: $agent_type at step $step_index" >&2
    return 1
  fi
  printf '%s\n' "$result"
}

# FR-011: Set the status of a specific agent within a parallel step
# Params: $1 = state file path, $2 = step index, $3 = agent_type, $4 = new status
# Output: none (updates state file)
# Exit: 0 on success, 1 on failure
state_set_agent_status() {
  local state_file="$1"
  local step_index="$2"
  local agent_type="$3"
  local new_status="$4"
  local state
  state=$(state_read "$state_file") || return 1
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  local updated
  updated=$(printf '%s\n' "$state" | jq \
    --argjson idx "$step_index" \
    --arg agent "$agent_type" \
    --arg status "$new_status" \
    --arg now "$now" \
    '.steps[$idx].agents[$agent].status = $status | .updated_at = $now |
     if $status == "working" then .steps[$idx].agents[$agent].started_at = $now
     elif ($status == "done" or $status == "failed") then .steps[$idx].agents[$agent].completed_at = $now
     else . end')
  state_write "$state_file" "$updated"
}

# FR-028: Record step output artifact path
# Params: $1 = state file path, $2 = step index, $3 = output path or value
# Output: none (updates state file)
# Exit: 0 on success, 1 on failure
state_set_step_output() {
  local state_file="$1"
  local step_index="$2"
  local output_value="$3"
  local state
  state=$(state_read "$state_file") || return 1
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  local updated
  updated=$(printf '%s\n' "$state" | jq \
    --argjson idx "$step_index" \
    --arg output "$output_value" \
    --arg now "$now" \
    '.steps[$idx].output = $output | .updated_at = $now')
  state_write "$state_file" "$updated"
}

# FR-028: Get step output artifact path
# Params: $1 = state JSON (string), $2 = step index
# Output (stdout): output path/value string, or empty if none
# Exit: 0
state_get_step_output() {
  local state_json="$1"
  local step_index="$2"
  printf '%s\n' "$state_json" | jq -r --argjson idx "$step_index" '.steps[$idx].output // empty'
}

# FR-021/022: Append an entry to a step's command log
# Params: $1 = state file path, $2 = step index, $3 = command string, $4 = exit code, $5 = timestamp
# Output: none (updates state file)
# Exit: 0 on success, 1 on failure
state_append_command_log() {
  local state_file="$1"
  local step_index="$2"
  local command_str="$3"
  local exit_code="$4"
  local timestamp="$5"
  local state
  state=$(state_read "$state_file") || return 1
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  local updated
  updated=$(printf '%s\n' "$state" | jq \
    --argjson idx "$step_index" \
    --arg cmd "$command_str" \
    --argjson code "$exit_code" \
    --arg ts "$timestamp" \
    --arg now "$now" \
    '.steps[$idx].command_log += [{command: $cmd, exit_code: $code, timestamp: $ts}] | .updated_at = $now')
  state_write "$state_file" "$updated"
}

# FR-023: Get the command log for a step
# Params: $1 = state JSON (string), $2 = step index
# Output (stdout): JSON array of {command, exit_code, timestamp} objects
# Exit: 0
state_get_command_log() {
  local state_json="$1"
  local step_index="$2"
  printf '%s\n' "$state_json" | jq --argjson idx "$step_index" '.steps[$idx].command_log // []'
}

# FR-025/FR-004: Record a team in the workflow state under teams.{step_id}
# Params: $1 = state file path, $2 = step_id (team-create step ID), $3 = team_name
# Output: none (updates state file)
# Exit: 0 on success, 1 on failure
state_set_team() {
  local state_file="$1"
  local step_id="$2"
  local team_name="$3"
  local state
  state=$(state_read "$state_file") || return 1
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  local updated
  updated=$(printf '%s\n' "$state" | jq \
    --arg sid "$step_id" \
    --arg name "$team_name" \
    --arg now "$now" \
    '.teams[$sid] = {team_name: $name, created_at: $now, teammates: {}} | .updated_at = $now')
  state_write "$state_file" "$updated"
}

# FR-025: Read team metadata from state by step_id
# Params: $1 = state JSON (string), $2 = step_id (team-create step ID)
# Output (stdout): JSON object with team_name, teammates
# Exit: 0 if found, 1 if not found
state_get_team() {
  local state_json="$1"
  local step_id="$2"
  local result
  result=$(printf '%s\n' "$state_json" | jq --arg sid "$step_id" '.teams[$sid] // empty')
  if [[ -z "$result" || "$result" == "null" ]]; then
    echo "ERROR: team not found for step: $step_id" >&2
    return 1
  fi
  printf '%s\n' "$result"
}

# FR-025: Add a teammate entry to a team's teammates map
# Params: $1 = state file, $2 = team_step_id, $3 = agent_name, $4 = task_id,
#         $5 = agent_id, $6 = output_dir, $7 = assign_json (may be empty)
# Output: none (updates state file)
# Exit: 0 on success, 1 on failure
state_add_teammate() {
  local state_file="$1"
  local team_step_id="$2"
  local agent_name="$3"
  local task_id="$4"
  local agent_id="$5"
  local output_dir="$6"
  local assign_json="${7:-"{}"}"
  local state
  state=$(state_read "$state_file") || return 1
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  local updated
  updated=$(printf '%s\n' "$state" | jq \
    --arg sid "$team_step_id" \
    --arg name "$agent_name" \
    --arg tid "$task_id" \
    --arg aid "$agent_id" \
    --arg odir "$output_dir" \
    --argjson assign "$assign_json" \
    --arg now "$now" \
    '.teams[$sid].teammates[$name] = {
      task_id: $tid,
      status: "pending",
      agent_id: $aid,
      output_dir: $odir,
      started_at: null,
      completed_at: null,
      assign: $assign
    } | .updated_at = $now')
  state_write "$state_file" "$updated"
}

# FR-025: Update a teammate's status with timestamp
# Params: $1 = state file, $2 = team_step_id, $3 = agent_name, $4 = new_status
# Output: none (updates state file)
# Exit: 0 on success, 1 on failure
state_update_teammate_status() {
  local state_file="$1"
  local team_step_id="$2"
  local agent_name="$3"
  local new_status="$4"
  local state
  state=$(state_read "$state_file") || return 1
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  local updated
  updated=$(printf '%s\n' "$state" | jq \
    --arg sid "$team_step_id" \
    --arg name "$agent_name" \
    --arg status "$new_status" \
    --arg now "$now" \
    '.teams[$sid].teammates[$name].status = $status | .updated_at = $now |
     if $status == "running" then .teams[$sid].teammates[$name].started_at = $now
     elif ($status == "completed" or $status == "failed") then .teams[$sid].teammates[$name].completed_at = $now
     else . end')
  state_write "$state_file" "$updated"
}

# FR-025: Return all teammate entries for a team
# Params: $1 = state JSON (string), $2 = team_step_id
# Output (stdout): JSON object of teammates map
# Exit: 0 if found, 1 if not found
state_get_teammates() {
  local state_json="$1"
  local team_step_id="$2"
  local result
  result=$(printf '%s\n' "$state_json" | jq --arg sid "$team_step_id" '.teams[$sid].teammates // empty')
  if [[ -z "$result" || "$result" == "null" ]]; then
    echo "ERROR: teammates not found for team step: $team_step_id" >&2
    return 1
  fi
  printf '%s\n' "$result"
}

# FR-025: Remove a team from the state file (called by team-delete)
# Params: $1 = state file, $2 = step_id (team-create step ID)
# Output: none (updates state file)
# Exit: 0 on success, 1 on failure
state_remove_team() {
  local state_file="$1"
  local step_id="$2"
  local state
  state=$(state_read "$state_file") || return 1
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  local updated
  updated=$(printf '%s\n' "$state" | jq \
    --arg sid "$step_id" \
    --arg now "$now" \
    'del(.teams[$sid]) | .updated_at = $now')
  state_write "$state_file" "$updated"
}
