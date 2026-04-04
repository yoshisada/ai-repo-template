#!/usr/bin/env bash
# subagent-stop.sh — SubagentStop hook handler
# FR-007: Marks agents done in state.json, checks if all parallel agents
# for the current step have finished, and advances to the next step if so

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${HOOK_DIR}/.." && pwd)"

HOOK_INPUT=$(cat)

export WHEEL_HOOK_SCRIPT="${BASH_SOURCE[0]}"
export WHEEL_HOOK_INPUT="$HOOK_INPUT"

source "${PLUGIN_DIR}/lib/engine.sh"

WORKFLOW_FILE="${WHEEL_WORKFLOW:-}"
if [[ -z "$WORKFLOW_FILE" ]]; then
  WORKFLOW_FILE=$(find workflows/ -name '*.json' -type f 2>/dev/null | head -1)
fi

if [[ -z "$WORKFLOW_FILE" || ! -f "$WORKFLOW_FILE" ]]; then
  echo '{"decision": "allow"}'
  exit 0
fi

if ! engine_init "$WORKFLOW_FILE" ".wheel"; then
  echo '{"decision": "allow"}'
  exit 0
fi

engine_handle_hook "subagent_stop" "$HOOK_INPUT"
