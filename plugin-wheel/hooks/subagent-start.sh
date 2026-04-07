#!/usr/bin/env bash
# subagent-start.sh — SubagentStart hook handler
# FR-006: Injects previous step output as additionalContext into newly spawned agents
set -euo pipefail

# 1. Read hook input from stdin
HOOK_INPUT=$(cat)

# 2. Resolve state file from hook input (FR-004)
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${HOOK_DIR}/.." && pwd)"
source "${PLUGIN_DIR}/lib/guard.sh"
STATE_FILE=$(resolve_state_file ".wheel" "$HOOK_INPUT")
if [[ $? -ne 0 || -z "$STATE_FILE" ]]; then
  echo '{"decision": "approve"}'
  exit 0
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
# For SubagentStart, build context and inject it
current_step=$(engine_current_step)
step_exit=$?

if [[ "$step_exit" -ne 0 ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

state=$(state_read "$STATE_FILE")
agent_type=$(echo "$HOOK_INPUT" | jq -r '.agent_type // empty')

if [[ -n "$agent_type" ]]; then
  additional_context=$(context_subagent_start "$current_step" "$state" "$WORKFLOW" "$agent_type")
  if [[ -n "$additional_context" ]]; then
    jq -n --arg ctx "$additional_context" '{"decision": "approve", "additionalContext": $ctx}'
  else
    echo '{"decision": "approve"}'
  fi
else
  echo '{"decision": "approve"}'
fi
