#!/usr/bin/env bash
# post-tool-use.sh — PostToolUse(Bash) hook handler
# FR-022/023: Logs every command the LLM executes during agent steps
# Also intercepts activate.sh calls to create per-agent state files
set -euo pipefail

# 1. Read hook input from stdin and sanitize control characters for jq
RAW_INPUT=$(cat)
# Replace literal control chars (newlines, tabs, etc. inside JSON string values)
# that Claude Code may include in tool_output — jq rejects unescaped U+0000-U+001F
HOOK_INPUT=$(printf '%s' "$RAW_INPUT" | tr '\n' ' ' | sed 's/[[:cntrl:]]/ /g')

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${HOOK_DIR}/.." && pwd)"

# 2. Check for activate.sh interception — create state file with full ownership
COMMAND=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
if [[ "$COMMAND" == *"activate.sh"* ]]; then
  # Extract workflow name from the line containing activate.sh
  # Claude Code may send multi-line commands with variable assignments before the call,
  # so isolate the activate.sh line first, then extract the argument after it.
  ACTIVATE_LINE=$(printf '%s\n' "$COMMAND" | grep 'activate\.sh' | tail -1)
  WORKFLOW_NAME=$(printf '%s\n' "$ACTIVATE_LINE" | sed 's/.*activate\.sh["'"'"']*[[:space:]]*//' | awk '{print $1}' | tr -d "\"'")

  # If the extracted name is an unexpanded shell variable (e.g., $WORKFLOW_FILE),
  # try to resolve it from variable assignments earlier in the command block
  if [[ "$WORKFLOW_NAME" == \$* ]]; then
    VAR_NAME="${WORKFLOW_NAME#\$}"
    VAR_NAME="${VAR_NAME#\{}"
    VAR_NAME="${VAR_NAME%\}}"
    RESOLVED_VAL=$(printf '%s\n' "$COMMAND" | grep "^${VAR_NAME}=" | tail -1 | sed "s/^${VAR_NAME}=//" | tr -d "\"'")
    if [[ -n "$RESOLVED_VAL" ]]; then
      WORKFLOW_NAME="$RESOLVED_VAL"
    fi
  fi

  # Read workflow file — check local workflows/ first, then scan plugin workflows/ dirs
  WORKFLOW_FILE="workflows/${WORKFLOW_NAME}.json"
  if [[ -n "$WORKFLOW_NAME" && ! -f "$WORKFLOW_FILE" ]]; then
    # Not found locally — check if WORKFLOW_NAME is an absolute path (plugin workflow)
    if [[ -f "$WORKFLOW_NAME" ]]; then
      WORKFLOW_FILE="$WORKFLOW_NAME"
    else
      # Scan installed plugins for a workflows/ dir containing this workflow
      export WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
      source "${PLUGIN_DIR}/lib/workflow.sh"
      PLUGIN_WORKFLOWS=$(workflow_discover_plugin_workflows 2>/dev/null || echo '[]')
      RESOLVED=$(printf '%s\n' "$PLUGIN_WORKFLOWS" | jq -r \
        --arg name "$WORKFLOW_NAME" \
        '.[] | select(.name == $name) | .path // empty' | head -1)
      if [[ -n "$RESOLVED" && -f "$RESOLVED" ]]; then
        WORKFLOW_FILE="$RESOLVED"
      fi
    fi
  fi
  if [[ -n "$WORKFLOW_NAME" && -f "$WORKFLOW_FILE" ]]; then
    # Source engine libs for validation and state creation
    export WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
    source "${PLUGIN_DIR}/lib/engine.sh"

    # Validate workflow
    WORKFLOW_JSON=$(workflow_load "$WORKFLOW_FILE" 2>/dev/null)
    if [[ $? -eq 0 && -n "$WORKFLOW_JSON" ]]; then
      # Extract session_id and agent_id from hook input — stored as ownership
      SESSION_ID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
      AGENT_ID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.agent_id // empty' 2>/dev/null || echo "")

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
  # Extract argument from the line containing deactivate.sh (handles multi-line commands)
  DEACTIVATE_LINE=$(printf '%s\n' "$COMMAND" | grep 'deactivate\.sh' | tail -1)
  DEACTIVATE_ARG=$(printf '%s\n' "$DEACTIVATE_LINE" | sed 's/.*deactivate\.sh[[:space:]]*//' | awk '{print $1}' | tr -d "\"'")

  SESSION_ID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
  AGENT_ID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.agent_id // empty' 2>/dev/null || echo "")

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
      local owner_sid="" owner_aid=""
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

  # FR-018: Cascade stop to active child workflows
  # Scan remaining state files for any with parent_workflow pointing to a stopped file
  for sf in .wheel/state_*.json; do
    [[ -f "$sf" ]] || continue
    PARENT_PATH=$(jq -r '.parent_workflow // empty' "$sf" 2>/dev/null) || continue
    if [[ -n "$PARENT_PATH" && ! -f "$PARENT_PATH" ]]; then
      # Parent was stopped (no longer exists) — stop this child too
      TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
      FNAME=$(basename "$sf" .json)
      cp "$sf" ".wheel/history/stopped/${FNAME}-${TIMESTAMP}.json"
      rm -f "$sf"
      STOPPED=$((STOPPED + 1))
    fi
  done

  # FR-028: Cascade stop to team agent sub-workflows
  # Check stopped state files (in history/stopped/) for teams with running teammates.
  # Their sub-workflow state files need to be stopped too.
  for sf in .wheel/history/stopped/*.json; do
    [[ -f "$sf" ]] || continue
    TEAMS_JSON=$(jq -r '.teams // empty' "$sf" 2>/dev/null) || continue
    [[ -z "$TEAMS_JSON" || "$TEAMS_JSON" == "null" ]] && continue
    # Extract all teammate agent_ids from all teams
    TEAMMATE_AIDS=$(printf '%s\n' "$TEAMS_JSON" | jq -r '
      [to_entries[] | .value.teammates // {} | to_entries[] |
       select(.value.status == "pending" or .value.status == "running") |
       .value.agent_id] | .[]' 2>/dev/null) || continue
    [[ -z "$TEAMMATE_AIDS" ]] && continue
    # Stop any remaining state files owned by these teammate agents
    while IFS= read -r TAID; do
      [[ -z "$TAID" ]] && continue
      for tsf in .wheel/state_*.json; do
        [[ -f "$tsf" ]] || continue
        TSF_AID=$(jq -r '.owner_agent_id // empty' "$tsf" 2>/dev/null) || continue
        if [[ "$TSF_AID" == "$TAID" ]]; then
          TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
          TFNAME=$(basename "$tsf" .json)
          cp "$tsf" ".wheel/history/stopped/${TFNAME}-${TIMESTAMP}.json"
          rm -f "$tsf"
          STOPPED=$((STOPPED + 1))
        fi
      done
    done <<< "$TEAMMATE_AIDS"
  done

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
