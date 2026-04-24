#!/usr/bin/env bash
# stop.sh — Stop hook handler
# FR-004: Gates the parent orchestrator, injects next step instruction,
# or allows stop when workflow is complete
set -euo pipefail

# 1. Read hook input from stdin
HOOK_INPUT=$(cat)

# 2. Resolve state file from hook input (FR-004)
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${HOOK_DIR}/.." && pwd)"
export WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
source "${PLUGIN_DIR}/lib/log.sh"
_SID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
wheel_log_init "stop" "$_SID"
_AID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.agent_id // empty' 2>/dev/null || echo "")
_TNAME=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.team_name // empty' 2>/dev/null || echo "")
wheel_log "enter" "agent_id=${_AID} team_name=${_TNAME}"

source "${PLUGIN_DIR}/lib/guard.sh"
STATE_FILE=$(resolve_state_file ".wheel" "$HOOK_INPUT") || true
if [[ -z "$STATE_FILE" ]]; then
  # No state file for this agent. If this is a teammate (has team_name or agent_id
  # with @ sign), their sub-workflow completed and was archived — stop the teammate.
  local_team_name=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.team_name // empty' 2>/dev/null || true)
  local_agent_id=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.agent_id // empty' 2>/dev/null || true)
  if [[ -n "$local_team_name" ]] || [[ "$local_agent_id" == *"@"* ]]; then
    wheel_log "exit" "result=teammate-stop reason=sub_workflow_archived"
    jq -n --arg reason "Sub-workflow complete — teammate stopping." \
      '{"continue": false, "stopReason": $reason}'
    exit 0
  fi
  wheel_log "exit" "result=no-state reason=unresolved"
  echo '{"decision": "approve"}'
  exit 0
fi
wheel_log_set_state "$STATE_FILE"
wheel_log "resolved" "state=$STATE_FILE"

# FR-007 (wheel-user-input): Silence branch — if the current step is awaiting
# user input AND the output file has NOT yet been written, emit nothing and
# return. The Stop hook re-fires on every turn while the user answers; without
# this branch the agent would be spammed with "write your output" reminders
# across every reply turn.
#
# If the output file IS present, fall through to the normal advance path —
# dispatch_agent will mark the step done, auto-clear awaiting_user_input
# (FR-008), and advance the cursor.
#
# Silent JSON (no stopReason/systemMessage/additionalContext) matches the
# no-state-file path above; produces zero user-visible text.
_PRE_CURSOR=$(jq -r '.cursor // 0' "$STATE_FILE" 2>/dev/null || echo 0)
_PRE_AWAITING=$(jq -r --argjson idx "$_PRE_CURSOR" '.steps[$idx].awaiting_user_input // false' "$STATE_FILE" 2>/dev/null || echo false)
if [[ "$_PRE_AWAITING" == "true" ]]; then
  # Only silence if the step's output hasn't been written yet. Read the
  # output key from the workflow file.
  _PRE_WF=$(jq -r '.workflow_file // empty' "$STATE_FILE" 2>/dev/null || echo "")
  _PRE_OUTPUT=""
  if [[ -n "$_PRE_WF" && -f "$_PRE_WF" ]]; then
    _PRE_OUTPUT=$(jq -r --argjson idx "$_PRE_CURSOR" '.steps[$idx].output // empty' "$_PRE_WF" 2>/dev/null || echo "")
  fi
  _PRE_STEP_ID=$(jq -r --argjson idx "$_PRE_CURSOR" '.steps[$idx].id // "?"' "$STATE_FILE" 2>/dev/null || echo "?")
  if [[ -z "$_PRE_OUTPUT" ]] || [[ ! -f "$_PRE_OUTPUT" ]]; then
    wheel_log "silent" "reason=awaiting_user_input step=${_PRE_STEP_ID}"
    echo '{"decision": "approve"}'
    exit 0
  fi
  wheel_log "advance_from_silent" "step=${_PRE_STEP_ID} output=${_PRE_OUTPUT}"
fi

# 3. Read workflow file from resolved state (FR-005)
WORKFLOW_FILE=$(jq -r '.workflow_file // empty' "$STATE_FILE")
if [[ -z "$WORKFLOW_FILE" || ! -f "$WORKFLOW_FILE" ]]; then
  wheel_log "exit" "result=no-workflow"
  echo '{"decision": "approve"}'
  exit 0
fi

# Export for command chaining (FR-020)
export WHEEL_HOOK_SCRIPT="${BASH_SOURCE[0]}"
export WHEEL_HOOK_INPUT="$HOOK_INPUT"

# 4. Source engine, init with resolved state file (FR-010)
source "${PLUGIN_DIR}/lib/engine.sh"
if ! engine_init "$WORKFLOW_FILE" "$STATE_FILE"; then
  wheel_log "exit" "result=engine-init-failed"
  echo '{"decision": "approve"}'
  exit 0
fi

# 5. Proceed with hook-specific logic (FR-005: no guard_check needed)
_CURSOR=$(jq -r '.cursor // 0' "$STATE_FILE" 2>/dev/null || echo "?")
_STYPE=$(jq -r ".steps[${_CURSOR}].type // empty" "$STATE_FILE" 2>/dev/null || echo "?")
_SSTAT=$(jq -r ".steps[${_CURSOR}].status // empty" "$STATE_FILE" 2>/dev/null || echo "?")
wheel_log "handle" "cursor=${_CURSOR} step_type=${_STYPE} step_status=${_SSTAT}"
_RESULT=$(engine_handle_hook "stop" "$HOOK_INPUT")
wheel_log "exit" "result=$(printf '%s' "$_RESULT" | tr -d '\n' | head -c 300)"
printf '%s\n' "$_RESULT"
