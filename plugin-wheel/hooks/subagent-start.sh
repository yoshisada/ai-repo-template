#!/usr/bin/env bash
# subagent-start.sh — SubagentStart hook handler
# FR-006: Injects previous step output as additionalContext into newly spawned agents
set -euo pipefail

# FR-004: Guard — exit if no workflow active
if [[ ! -f ".wheel/state.json" ]]; then
  echo '{"decision": "allow"}'
  exit 0
fi

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Resolve paths
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${HOOK_DIR}/.." && pwd)"

# FR-005: Read workflow file path from state.json (no auto-discovery)
WORKFLOW_FILE=$(jq -r '.workflow_file // empty' ".wheel/state.json")
if [[ -z "$WORKFLOW_FILE" || ! -f "$WORKFLOW_FILE" ]]; then
  echo '{"decision": "allow"}'
  exit 0
fi

export WHEEL_HOOK_SCRIPT="${BASH_SOURCE[0]}"
export WHEEL_HOOK_INPUT="$HOOK_INPUT"

source "${PLUGIN_DIR}/lib/engine.sh"

if ! engine_init "$WORKFLOW_FILE" ".wheel"; then
  echo '{"decision": "allow"}'
  exit 0
fi

# For SubagentStart, build context and inject it
current_step=$(engine_current_step)
step_exit=$?

if [[ "$step_exit" -ne 0 ]]; then
  echo '{"decision": "allow"}'
  exit 0
fi

state=$(state_read "$STATE_FILE")
agent_type=$(echo "$HOOK_INPUT" | jq -r '.agent_type // empty')

if [[ -n "$agent_type" ]]; then
  additional_context=$(context_subagent_start "$current_step" "$state" "$WORKFLOW" "$agent_type")
  if [[ -n "$additional_context" ]]; then
    jq -n --arg ctx "$additional_context" '{"decision": "allow", "additionalContext": $ctx}'
  else
    echo '{"decision": "allow"}'
  fi
else
  echo '{"decision": "allow"}'
fi
