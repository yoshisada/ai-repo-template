#!/usr/bin/env bash
# post-tool-use.sh — PostToolUse(Bash) hook handler
# FR-022/023: Logs every command the LLM executes during agent steps
# Also intercepts activate.sh calls to create per-agent state files
set -euo pipefail

# 1. Read hook input from stdin
HOOK_INPUT=$(cat)

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${HOOK_DIR}/.." && pwd)"

# 2. Check for activate.sh interception — create state file with full ownership
COMMAND=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.tool_input.command // empty')
if [[ "$COMMAND" == *"activate.sh"* ]]; then
  # Extract workflow name from the command (activate.sh <name>)
  WORKFLOW_NAME=$(printf '%s\n' "$COMMAND" | grep -oP 'activate\.sh\s+\K\S+' 2>/dev/null || echo "")
  if [[ -z "$WORKFLOW_NAME" ]]; then
    # Try simpler extraction — last word after activate.sh
    WORKFLOW_NAME=$(printf '%s\n' "$COMMAND" | sed 's/.*activate\.sh[[:space:]]*//' | awk '{print $1}')
  fi

  # Read pending.json for the validated workflow data
  if [[ -n "$WORKFLOW_NAME" && -f ".wheel/pending.json" ]]; then
    PENDING=$(cat .wheel/pending.json)
    WORKFLOW_FILE=$(printf '%s\n' "$PENDING" | jq -r '.workflow_file // empty')
    WORKFLOW_JSON=$(printf '%s\n' "$PENDING" | jq -r '.workflow_json // empty')

    if [[ -n "$WORKFLOW_FILE" && -n "$WORKFLOW_JSON" ]]; then
      # Extract session_id and agent_id from hook input — this is the whole point
      SESSION_ID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.session_id // empty')
      AGENT_ID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.agent_id // empty')

      # Construct state filename with full ownership
      if [[ -n "$AGENT_ID" ]]; then
        STATE_FILE=".wheel/state_${SESSION_ID}_${AGENT_ID}.json"
      elif [[ -n "$SESSION_ID" ]]; then
        STATE_FILE=".wheel/state_${SESSION_ID}.json"
      else
        STATE_FILE=".wheel/state_$(date +%s).json"
      fi

      # Source engine libs and create state
      source "${PLUGIN_DIR}/lib/engine.sh"
      state_init "$STATE_FILE" "$WORKFLOW_JSON" "$SESSION_ID" "$AGENT_ID" "$WORKFLOW_FILE"

      # Run kickstart — execute command/loop/branch steps inline
      WORKFLOW="$WORKFLOW_JSON"
      export WHEEL_HOOK_SCRIPT=""
      export WHEEL_HOOK_INPUT='{}'
      engine_kickstart "$STATE_FILE" >/dev/null 2>&1

      # Clean up pending file
      rm -f .wheel/pending.json
    fi
  fi

  echo '{"hookEventName": "PostToolUse"}'
  exit 0
fi

# 3. Resolve state file from hook input (FR-004) — normal hook path
source "${PLUGIN_DIR}/lib/guard.sh"
STATE_FILE=$(resolve_state_file ".wheel" "$HOOK_INPUT")
if [[ $? -ne 0 || -z "$STATE_FILE" ]]; then
  echo '{"hookEventName": "PostToolUse"}'
  exit 0
fi

# 4. Read workflow file from resolved state (FR-005)
WORKFLOW_FILE=$(jq -r '.workflow_file // empty' "$STATE_FILE")
if [[ -z "$WORKFLOW_FILE" || ! -f "$WORKFLOW_FILE" ]]; then
  echo '{"hookEventName": "PostToolUse"}'
  exit 0
fi

# 5. Source engine, init with resolved state file (FR-010)
source "${PLUGIN_DIR}/lib/engine.sh"
if ! engine_init "$WORKFLOW_FILE" "$STATE_FILE"; then
  echo '{"hookEventName": "PostToolUse"}'
  exit 0
fi

# 6. Proceed with hook-specific logic
engine_handle_hook "post_tool_use" "$HOOK_INPUT"
