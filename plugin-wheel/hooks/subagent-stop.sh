#!/usr/bin/env bash
# subagent-stop.sh — SubagentStop hook handler
# FR-007: Marks agents done in state.json, checks if all parallel agents
# for the current step have finished, and advances to the next step if so
set -euo pipefail

# FR-004: Guard — exit if no workflow active
if [[ ! -f ".wheel/state.json" ]]; then
  echo '{"decision": "approve"}'
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
  echo '{"decision": "approve"}'
  exit 0
fi

export WHEEL_HOOK_SCRIPT="${BASH_SOURCE[0]}"
export WHEEL_HOOK_INPUT="$HOOK_INPUT"

source "${PLUGIN_DIR}/lib/engine.sh"

if ! engine_init "$WORKFLOW_FILE" ".wheel"; then
  echo '{"decision": "approve"}'
  exit 0
fi

# FR-002: Session guard — only the owning agent can advance the workflow
if ! guard_check "$STATE_FILE" "$HOOK_INPUT"; then
  echo '{"decision": "approve"}'
  exit 0
fi

engine_handle_hook "subagent_stop" "$HOOK_INPUT"
