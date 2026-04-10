#!/usr/bin/env bash
# teammate-idle.sh — TeammateIdle hook handler
# FR-005: Gates agents with their agent-specific next task,
# or allows idle when the step is done
set -euo pipefail

# 1. Read hook input from stdin
HOOK_INPUT=$(cat)

# Debug: capture hook input for analysis
echo "$HOOK_INPUT" > /tmp/teammate-idle-debug.json 2>/dev/null || true

# 2. Resolve state file from hook input (FR-004)
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${HOOK_DIR}/.." && pwd)"
export WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
source "${PLUGIN_DIR}/lib/log.sh"
_SID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
wheel_log_init "teammate-idle" "$_SID"
_TM=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.teammate_name // empty' 2>/dev/null || echo "")
_TN=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.team_name // empty' 2>/dev/null || echo "")
wheel_log "enter" "teammate=${_TM} team=${_TN}"

source "${PLUGIN_DIR}/lib/guard.sh"
# TeammateIdle hook input has teammate_name and team_name but NO agent_id.
# Construct the team-format ID for state file resolution.
TEAMMATE_NAME=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.teammate_name // empty' 2>/dev/null || echo "")
TEAM_NAME=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.team_name // empty' 2>/dev/null || echo "")
IDLE_SESSION_ID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")

if [[ -n "$TEAMMATE_NAME" && -n "$TEAM_NAME" ]]; then
  IDLE_AGENT_ID="${TEAMMATE_NAME}@${TEAM_NAME}"
  # Inject agent_id into hook input so resolve_state_file can match
  HOOK_INPUT=$(printf '%s\n' "$HOOK_INPUT" | jq --arg aid "$IDLE_AGENT_ID" '.agent_id = $aid')
fi

STATE_FILE=$(resolve_state_file ".wheel" "$HOOK_INPUT") || true
wheel_log_set_state "${STATE_FILE:-?}"
wheel_log "resolved" "state=${STATE_FILE:-none}"
if [[ -z "$STATE_FILE" ]]; then
  # No state file for this teammate — sub-workflow may have completed and been
  # archived. Find the parent state file so team-wait can detect completion.
  if [[ -n "$IDLE_SESSION_ID" ]]; then
    for _psf in .wheel/state_*.json; do
      [[ -f "$_psf" ]] || continue
      _psid=$(jq -r '.owner_session_id // empty' "$_psf" 2>/dev/null) || continue
      _paid=$(jq -r '.owner_agent_id // empty' "$_psf" 2>/dev/null) || continue
      if [[ "$_psid" == "$IDLE_SESSION_ID" && -z "$_paid" ]]; then
        STATE_FILE="$_psf"
        break
      fi
    done
  fi
  if [[ -z "$STATE_FILE" ]]; then
    echo '{"decision": "approve"}'
    exit 0
  fi
fi

# 3. Read workflow file from resolved state (FR-005)
WORKFLOW_FILE=$(jq -r '.workflow_file // empty' "$STATE_FILE")
if [[ -z "$WORKFLOW_FILE" || ! -f "$WORKFLOW_FILE" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

export WHEEL_HOOK_SCRIPT="${BASH_SOURCE[0]}"
export WHEEL_HOOK_INPUT="$HOOK_INPUT"

# 4. Source engine, init with resolved state file (FR-010)
export WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
source "${PLUGIN_DIR}/lib/engine.sh"
if ! engine_init "$WORKFLOW_FILE" "$STATE_FILE"; then
  echo '{"decision": "approve"}'
  exit 0
fi

# 5. Proceed with hook-specific logic (FR-005: no guard_check needed)
_CURSOR=$(jq -r '.cursor // 0' "$STATE_FILE" 2>/dev/null || echo "?")
_STYPE=$(jq -r ".steps[${_CURSOR}].type // empty" "$STATE_FILE" 2>/dev/null || echo "?")
wheel_log "handle" "cursor=${_CURSOR} step_type=${_STYPE}"
_RESULT=$(engine_handle_hook "teammate_idle" "$HOOK_INPUT")
wheel_log "exit" "result=$(printf '%s' "$_RESULT" | tr -d '\n' | head -c 200)"
printf '%s\n' "$_RESULT"
