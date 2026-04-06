#!/usr/bin/env bash
# post-tool-use.sh — PostToolUse(Bash) hook handler
# FR-022/023: Logs every command the LLM executes during agent steps
# into the current step's command_log array in state.json
set -euo pipefail

# 1. Read hook input from stdin
HOOK_INPUT=$(cat)

# 2. Resolve state file from hook input (FR-004)
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${HOOK_DIR}/.." && pwd)"
source "${PLUGIN_DIR}/lib/guard.sh"
STATE_FILE=$(resolve_state_file ".wheel" "$HOOK_INPUT")
if [[ $? -ne 0 || -z "$STATE_FILE" ]]; then
  echo '{"hookEventName": "PostToolUse"}'
  exit 0
fi

# 3. Read workflow file from resolved state (FR-005)
WORKFLOW_FILE=$(jq -r '.workflow_file // empty' "$STATE_FILE")
if [[ -z "$WORKFLOW_FILE" || ! -f "$WORKFLOW_FILE" ]]; then
  echo '{"hookEventName": "PostToolUse"}'
  exit 0
fi

# 4. Source engine, init with resolved state file (FR-010)
source "${PLUGIN_DIR}/lib/engine.sh"
if ! engine_init "$WORKFLOW_FILE" "$STATE_FILE"; then
  echo '{"hookEventName": "PostToolUse"}'
  exit 0
fi

# 5. Proceed with hook-specific logic (FR-005: no guard_check needed)
engine_handle_hook "post_tool_use" "$HOOK_INPUT"
