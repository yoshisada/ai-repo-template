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

# Initialize logging
export WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
source "${PLUGIN_DIR}/lib/log.sh"
_SID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
wheel_log_init "post-tool-use" "$_SID"
_TOOL=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
wheel_log "enter" "tool=${_TOOL}"

# 2. Extract command for interception checks
COMMAND=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

# 2a. Check for deactivate.sh FIRST — "deactivate.sh" contains "activate.sh" as a substring,
# so this must be checked before the activate.sh branch to avoid false matches.
if [[ "$COMMAND" == *"deactivate.sh"* ]]; then
  wheel_log "branch" "path=deactivate"
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
  for sf in .wheel/state_*.json; do
    [[ -f "$sf" ]] || continue
    PARENT_PATH=$(jq -r '.parent_workflow // empty' "$sf" 2>/dev/null) || continue
    if [[ -n "$PARENT_PATH" && ! -f "$PARENT_PATH" ]]; then
      TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
      FNAME=$(basename "$sf" .json)
      cp "$sf" ".wheel/history/stopped/${FNAME}-${TIMESTAMP}.json"
      rm -f "$sf"
      STOPPED=$((STOPPED + 1))
    fi
  done

  # FR-028: Cascade stop to team agent sub-workflows
  for sf in .wheel/history/stopped/*.json; do
    [[ -f "$sf" ]] || continue
    TEAMS_JSON=$(jq -r '.teams // empty' "$sf" 2>/dev/null) || continue
    [[ -z "$TEAMS_JSON" || "$TEAMS_JSON" == "null" ]] && continue
    TEAMMATE_AIDS=$(printf '%s\n' "$TEAMS_JSON" | jq -r '
      [to_entries[] | .value.teammates // {} | to_entries[] |
       select(.value.status == "pending" or .value.status == "running") |
       .value.agent_id] | .[]' 2>/dev/null) || continue
    [[ -z "$TEAMMATE_AIDS" ]] && continue
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

  wheel_log "exit" "result=deactivate stopped=${STOPPED}"
  echo '{"hookEventName": "PostToolUse"}'
  exit 0
fi

# 2b. Check for activate.sh interception — create state file with full ownership
if [[ "$COMMAND" == *"activate.sh"* ]]; then
  wheel_log "branch" "path=activate"
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

      # For teammate agents: the hook input has the raw agent ID but Stop hooks
      # receive the team-format ID (worker-1@team). Find the parent state file
      # and look up which teammate entry maps to this agent, then store the
      # team-format ID as alternate_agent_id.
      # For teammate agents: map the raw agent ID to the team-format ID.
      # Use a lock file per team-format ID to prevent race conditions when
      # multiple teammates activate simultaneously.
      # For teammate agents: map the raw agent ID to the team-format ID.
      # Find the parent state file, get running teammate IDs, and atomically
      # claim one via mkdir lock.
      if [[ -n "$AGENT_ID" && -n "$SESSION_ID" ]]; then
        _parent_sf=""
        for _psf in .wheel/state_*.json; do
          [[ -f "$_psf" && "$_psf" != "$STATE_FILE" ]] || continue
          _psid=$(jq -r '.owner_session_id // empty' "$_psf" 2>/dev/null) || continue
          _paid=$(jq -r '.owner_agent_id // empty' "$_psf" 2>/dev/null) || continue
          if [[ "$_psid" == "$SESSION_ID" && -z "$_paid" ]]; then
            _parent_sf="$_psf"
            break
          fi
        done
        if [[ -n "$_parent_sf" ]]; then
          _tids=$(jq -r '
            [.teams // {} | to_entries[] | .value.teammates // {} | to_entries[] |
             select(.value.status == "running") | .value.agent_id // empty] | .[]
          ' "$_parent_sf" 2>/dev/null) || true
          mkdir -p .wheel/.locks
          while IFS= read -r _tid; do
            [[ -z "$_tid" ]] && continue
            _lock=".wheel/.locks/agent_map_${_tid//[@\/]/_}"
            if mkdir "$_lock" 2>/dev/null; then
              _st=$(state_read "$STATE_FILE")
              state_write "$STATE_FILE" "$(printf '%s\n' "$_st" | jq --arg alt "$_tid" '.alternate_agent_id = $alt')"
              break
            fi
          done <<< "$_tids"
        fi
      fi

      wheel_log_set_state "$STATE_FILE"
      wheel_log "activate" "workflow=${WORKFLOW_NAME} file=${WORKFLOW_FILE}"
      WORKFLOW="$WORKFLOW_JSON"
      export WHEEL_HOOK_SCRIPT=""
      export WHEEL_HOOK_INPUT='{}'
      engine_kickstart "$STATE_FILE" >/dev/null 2>&1

      # Clean up legacy pending file if present
      rm -f .wheel/pending.json
    fi
  fi

  wheel_log "exit" "result=activate workflow=${WORKFLOW_NAME}"
  echo '{"hookEventName": "PostToolUse"}'
  exit 0
fi

# 3. Resolve state file from hook input (FR-004) — normal hook path
wheel_log "branch" "path=normal"
source "${PLUGIN_DIR}/lib/guard.sh"
STATE_FILE=$(resolve_state_file ".wheel" "$HOOK_INPUT") || true
if [[ -z "$STATE_FILE" ]]; then
  wheel_log "exit" "result=no-state reason=unresolved"
  echo '{"hookEventName": "PostToolUse"}'
  exit 0
fi
wheel_log_set_state "$STATE_FILE"
wheel_log "resolved" "state=$STATE_FILE"

# 4. Read workflow file from resolved state (FR-005)
WORKFLOW_FILE=$(jq -r '.workflow_file // empty' "$STATE_FILE")
if [[ -z "$WORKFLOW_FILE" || ! -f "$WORKFLOW_FILE" ]]; then
  wheel_log "exit" "result=no-workflow reason=missing_workflow_file"
  echo '{"hookEventName": "PostToolUse"}'
  exit 0
fi

# 5. Source engine, init with resolved state file (FR-010)
source "${PLUGIN_DIR}/lib/engine.sh"
if ! engine_init "$WORKFLOW_FILE" "$STATE_FILE"; then
  wheel_log "exit" "result=engine-init-failed"
  echo '{"hookEventName": "PostToolUse"}'
  exit 0
fi

# 6. Proceed with hook-specific logic
_CURSOR=$(jq -r '.cursor // 0' "$STATE_FILE" 2>/dev/null || echo "?")
_STYPE=$(jq -r ".steps[${_CURSOR}].type // empty" "$STATE_FILE" 2>/dev/null || echo "?")
_SSTAT=$(jq -r ".steps[${_CURSOR}].status // empty" "$STATE_FILE" 2>/dev/null || echo "?")
wheel_log "handle" "cursor=${_CURSOR} step_type=${_STYPE} step_status=${_SSTAT}"
_RESULT=$(engine_handle_hook "post_tool_use" "$HOOK_INPUT")
wheel_log "exit" "result=$(printf '%s' "$_RESULT" | tr -d '\n' | head -c 200)"
printf '%s\n' "$_RESULT"
