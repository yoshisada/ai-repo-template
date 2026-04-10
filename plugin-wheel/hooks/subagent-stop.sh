#!/usr/bin/env bash
# subagent-stop.sh — SubagentStop hook handler
# FR-007: Marks agents done in state.json, checks if all parallel agents
# for the current step have finished, and advances to the next step if so
set -euo pipefail

# 1. Read hook input from stdin
HOOK_INPUT=$(cat)

# 2. Resolve state file from hook input (FR-004)
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${HOOK_DIR}/.." && pwd)"
export WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
source "${PLUGIN_DIR}/lib/log.sh"
_SID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
wheel_log_init "subagent-stop" "$_SID"
_AT=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.agent_type // empty' 2>/dev/null || echo "")
wheel_log "enter" "agent_type=${_AT}"

source "${PLUGIN_DIR}/lib/guard.sh"
STATE_FILE=$(resolve_state_file ".wheel" "$HOOK_INPUT") || true
if [[ -z "$STATE_FILE" ]]; then
  wheel_log "exit" "result=no-state"
  echo '{"decision": "approve"}'
  exit 0
fi
wheel_log_set_state "$STATE_FILE"
wheel_log "resolved" "state=$STATE_FILE"

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
_RESULT=$(engine_handle_hook "subagent_stop" "$HOOK_INPUT")
wheel_log "exit" "result=$(printf '%s' "$_RESULT" | tr -d '\n' | head -c 200)"
printf '%s\n' "$_RESULT"
