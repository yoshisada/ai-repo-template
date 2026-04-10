#!/usr/bin/env bash
# session-start.sh — SessionStart hook handler
# FR-008: Reloads state.json on resume and injects resume instructions
set -euo pipefail

# 1. Read hook input from stdin
HOOK_INPUT=$(cat)

# 2. Resolve state file from hook input (FR-004)
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${HOOK_DIR}/.." && pwd)"
export WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
source "${PLUGIN_DIR}/lib/log.sh"
_SID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
wheel_log_init "session-start" "$_SID"
wheel_log "enter" ""

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

# 4. Source engine, init with resolved state file (FR-010)
export WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
source "${PLUGIN_DIR}/lib/engine.sh"
if ! engine_init "$WORKFLOW_FILE" "$STATE_FILE"; then
  echo '{"decision": "approve"}'
  exit 0
fi

# 5. Proceed with hook-specific logic (FR-005: no guard_check needed)
_CURSOR=$(jq -r '.cursor // 0' "$STATE_FILE" 2>/dev/null || echo "?")
wheel_log "handle" "cursor=${_CURSOR}"
_RESULT=$(engine_handle_hook "session_start" "$HOOK_INPUT")
wheel_log "exit" "result=$(printf '%s' "$_RESULT" | tr -d '\n' | head -c 200)"
printf '%s\n' "$_RESULT"
