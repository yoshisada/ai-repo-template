#!/usr/bin/env bash
# stop.sh — Stop hook handler
# FR-004: Gates the parent orchestrator, injects next step instruction,
# or allows stop when workflow is complete
set -euo pipefail

# 1. Read hook input from stdin
HOOK_INPUT=$(cat)

# DEBUG: Capture Stop hook input for teammate debugging
echo "$HOOK_INPUT" > /tmp/wheel-stop-debug.json 2>/dev/null || true

# 2. Resolve state file from hook input (FR-004)
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${HOOK_DIR}/.." && pwd)"
source "${PLUGIN_DIR}/lib/guard.sh"
STATE_FILE=$(resolve_state_file ".wheel" "$HOOK_INPUT") || true
if [[ -z "$STATE_FILE" ]]; then
  # No state file for this agent. If this is a teammate (has team_name or agent_id
  # with @ sign), their sub-workflow completed and was archived — stop the teammate.
  local_team_name=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.team_name // empty' 2>/dev/null || true)
  local_agent_id=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.agent_id // empty' 2>/dev/null || true)
  if [[ -n "$local_team_name" ]] || [[ "$local_agent_id" == *"@"* ]]; then
    jq -n --arg reason "Sub-workflow complete — teammate stopping." \
      '{"continue": false, "stopReason": $reason}'
    exit 0
  fi
  echo '{"decision": "approve"}'
  exit 0
fi

# 3. Read workflow file from resolved state (FR-005)
WORKFLOW_FILE=$(jq -r '.workflow_file // empty' "$STATE_FILE")
if [[ -z "$WORKFLOW_FILE" || ! -f "$WORKFLOW_FILE" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Export for command chaining (FR-020)
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
engine_handle_hook "stop" "$HOOK_INPUT"
