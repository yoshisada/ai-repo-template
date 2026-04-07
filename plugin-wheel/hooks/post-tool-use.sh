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
  # Strip quotes — bash commands may include escaped quotes: activate.sh \"name\"
  WORKFLOW_NAME=$(printf '%s\n' "$COMMAND" | sed 's/.*activate\.sh[[:space:]]*//' | awk '{print $1}' | tr -d "\"'")

  # Read workflow file directly — no pending.json needed, eliminates race condition
  WORKFLOW_FILE="workflows/${WORKFLOW_NAME}.json"
  if [[ -n "$WORKFLOW_NAME" && -f "$WORKFLOW_FILE" ]]; then
    # Source engine libs for validation and state creation
    export WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
    source "${PLUGIN_DIR}/lib/engine.sh"

    # Validate workflow
    WORKFLOW_JSON=$(workflow_load "$WORKFLOW_FILE" 2>/dev/null)
    if [[ $? -eq 0 && -n "$WORKFLOW_JSON" ]]; then
      # Extract session_id and agent_id from hook input — stored as ownership
      SESSION_ID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.session_id // empty')
      AGENT_ID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.agent_id // empty')

      # Generate unique state filename — ownership is inside the JSON, not the filename
      UNIQUE="${AGENT_ID:-${SESSION_ID}_$(date +%s)_${RANDOM}}"
      STATE_FILE=".wheel/state_${UNIQUE}.json"

      # Create state and run kickstart
      state_init "$STATE_FILE" "$WORKFLOW_JSON" "$SESSION_ID" "$AGENT_ID" "$WORKFLOW_FILE"
      WORKFLOW="$WORKFLOW_JSON"
      export WHEEL_HOOK_SCRIPT=""
      export WHEEL_HOOK_INPUT='{}'
      engine_kickstart "$STATE_FILE" >/dev/null 2>&1

      # Clean up legacy pending file if present
      rm -f .wheel/pending.json
    fi
  fi

  echo '{"hookEventName": "PostToolUse"}'
  exit 0
fi

# 2b. Check for deactivate.sh interception — ownership-aware workflow stop
if [[ "$COMMAND" == *"deactivate.sh"* ]]; then
  # Extract argument from command (deactivate.sh [--all | <target>])
  DEACTIVATE_ARG=$(printf '%s\n' "$COMMAND" | sed 's/.*deactivate\.sh[[:space:]]*//' | awk '{print $1}' | tr -d "\"'")

  SESSION_ID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.session_id // empty')
  AGENT_ID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.agent_id // empty')

  mkdir -p .wheel/history/stopped

  STOPPED=0
  if [[ "$DEACTIVATE_ARG" == "--all" ]]; then
    # Stop all workflows regardless of ownership
    for sf in .wheel/state_*.json; do
      [[ -f "$sf" ]] || continue
      TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
      FNAME=$(basename "$sf" .json)
      cp "$sf" ".wheel/history/stopped/${FNAME}-${TIMESTAMP}.json"
      rm -f "$sf"
      STOPPED=$((STOPPED + 1))
    done
  elif [[ -n "$DEACTIVATE_ARG" ]]; then
    # Stop workflows matching target substring in filename
    for sf in .wheel/state_*.json; do
      [[ -f "$sf" ]] || continue
      if [[ "$(basename "$sf")" == *"$DEACTIVATE_ARG"* ]]; then
        TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
        FNAME=$(basename "$sf" .json)
        cp "$sf" ".wheel/history/stopped/${FNAME}-${TIMESTAMP}.json"
        rm -f "$sf"
        STOPPED=$((STOPPED + 1))
      fi
    done
  else
    # Default: stop only the caller's own workflow (content-based ownership match)
    for sf in .wheel/state_*.json; do
      [[ -f "$sf" ]] || continue
      local owner_sid owner_aid
      owner_sid=$(jq -r '.owner_session_id // empty' "$sf" 2>/dev/null) || continue
      owner_aid=$(jq -r '.owner_agent_id // empty' "$sf" 2>/dev/null) || continue
      if [[ "$owner_sid" == "$SESSION_ID" && "$owner_aid" == "$AGENT_ID" ]]; then
        TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
        FNAME=$(basename "$sf" .json)
        cp "$sf" ".wheel/history/stopped/${FNAME}-${TIMESTAMP}.json"
        rm -f "$sf"
        STOPPED=$((STOPPED + 1))
        break
      fi
    done
  fi

  echo '{"hookEventName": "PostToolUse"}'
  exit 0
fi

# 3. Resolve state file from hook input (FR-004) — normal hook path
source "${PLUGIN_DIR}/lib/guard.sh"
STATE_FILE=$(resolve_state_file ".wheel" "$HOOK_INPUT") || true
if [[ -z "$STATE_FILE" ]]; then
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
export WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
source "${PLUGIN_DIR}/lib/engine.sh"
if ! engine_init "$WORKFLOW_FILE" "$STATE_FILE"; then
  echo '{"hookEventName": "PostToolUse"}'
  exit 0
fi

# 6. Proceed with hook-specific logic
engine_handle_hook "post_tool_use" "$HOOK_INPUT"
