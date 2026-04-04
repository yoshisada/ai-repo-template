#!/usr/bin/env bash
# post-tool-use.sh — PostToolUse(Bash) hook handler
# FR-022/023: Logs every command the LLM executes during agent steps
# into the current step's command_log array in state.json

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${HOOK_DIR}/.." && pwd)"

HOOK_INPUT=$(cat)

source "${PLUGIN_DIR}/lib/engine.sh"

WORKFLOW_FILE="${WHEEL_WORKFLOW:-}"
if [[ -z "$WORKFLOW_FILE" ]]; then
  WORKFLOW_FILE=$(find workflows/ -name '*.json' -type f 2>/dev/null | head -1)
fi

if [[ -z "$WORKFLOW_FILE" || ! -f "$WORKFLOW_FILE" ]]; then
  # No workflow active — nothing to log
  exit 0
fi

# Only proceed if state.json exists (workflow is running)
if [[ ! -f ".wheel/state.json" ]]; then
  exit 0
fi

if ! engine_init "$WORKFLOW_FILE" ".wheel"; then
  exit 0
fi

engine_handle_hook "post_tool_use" "$HOOK_INPUT"
