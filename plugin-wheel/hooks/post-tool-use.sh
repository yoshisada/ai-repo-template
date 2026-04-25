#!/usr/bin/env bash
# post-tool-use.sh — PostToolUse(Bash) hook handler
# FR-022/023: Logs every command the LLM executes during agent steps
# Also intercepts activate.sh calls to create per-agent state files
set -euo pipefail

# 1. Read hook input from stdin.
#
# FR-C1 (specs/wheel-as-runtime): the previous implementation flattened every
# newline in RAW_INPUT before jq parsing. That destroyed newlines in
# tool_input.command — meaning multi-line Bash tool calls that invoked
# activate.sh anywhere but the first line silently never activated. The fix:
#   (a) extract .tool_input.command from the RAW input via jq first (preserves
#       newlines);
#   (b) fall back to python3's JSON parser with strict=False on jq failure —
#       Claude Code's harness can emit literal U+0000–U+001F bytes inside
#       tool_input.command values, which jq strictly rejects (exit 4) but
#       python's json.loads(..., strict=False) accepts.
#   (c) defensive sanitization of OTHER fields (logging metadata) is allowed
#       for downstream jq calls, but MUST NOT touch the command string.
#
# This block:
#   - RAW_INPUT is the untouched stdin payload; use this for command extraction.
#   - HOOK_INPUT_SAFE is a control-char-flattened copy used ONLY for non-command
#     jq reads (session_id, tool_name, tool_output, etc.) where multi-line
#     fidelity is not required and jq robustness is the priority.
RAW_INPUT=$(cat)
HOOK_INPUT_SAFE=$(printf '%s' "$RAW_INPUT" | tr '\n' ' ' | sed 's/[[:cntrl:]]/ /g')
# Back-compat alias: some older references inside this script may still read
# $HOOK_INPUT. Keep it pointing at the SAFE copy so those reads continue to
# work. Command extraction below explicitly uses RAW_INPUT.
HOOK_INPUT="$HOOK_INPUT_SAFE"

# FR-C1 helper: extract tool_input.command preserving newlines.
# 1) Try jq on raw input.
# 2) On jq parse failure, try python3 json.loads(strict=False).
# 3) If both fail, emit an identifiable stderr diagnostic (NFR-2: silent drop
#    is forbidden) and return the empty string.
_extract_command() {
  local out
  if out=$(printf '%s' "$RAW_INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null); then
    printf '%s' "$out"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    if out=$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read(), strict=False)
except Exception as e:
    sys.stderr.write("wheel post-tool-use: python3 JSON fallback failed: " + str(e) + "\n")
    sys.exit(2)
ti = d.get("tool_input") or {}
sys.stdout.write(ti.get("command") or "")
' 2>/dev/null); then
      printf '%s' "$out"
      return 0
    fi
  fi
  # Both paths failed — loud, identifiable diagnostic (NFR-2 tripwire string).
  echo "wheel post-tool-use: FR-C1 command extraction failed (jq + python3 both rejected hook input)" >&2
  printf ''
}

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${HOOK_DIR}/.." && pwd)"

# Initialize logging
export WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
source "${PLUGIN_DIR}/lib/log.sh"
_SID=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
wheel_log_init "post-tool-use" "$_SID"
_TOOL=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
wheel_log "enter" "tool=${_TOOL}"

# 2. Extract command for interception checks.
# Use the FR-C1 helper so newlines are preserved (multi-line Bash tool calls
# with activate.sh in any position MUST activate — FR-C2 invariant).
COMMAND=$(_extract_command)

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
ACTIVATE_LINE=""
if [[ "$COMMAND" == *"activate.sh"* ]]; then
  # Extract the line containing activate.sh, but only if it looks like an
  # actual invocation — not prose. Valid invocations start (after optional
  # leading whitespace) with `bash /path/activate.sh`, `/path/activate.sh`,
  # or `./activate.sh`. Prose like `(e.g. activate.sh tests/foo ...)` inside
  # a git commit heredoc must NOT trigger activation.
  ACTIVATE_LINE=$(printf '%s\n' "$COMMAND" | grep -E '^[[:space:]]*(bash[[:space:]]+)?("|'"'"')?(\./|/)?[^[:space:]()"'"'"']*activate\.sh([[:space:]]|$)' | tail -1)
fi
if [[ -n "$ACTIVATE_LINE" ]]; then
  wheel_log "branch" "path=activate"
  WORKFLOW_NAME=$(printf '%s\n' "$ACTIVATE_LINE" | sed 's/.*activate\.sh["'"'"']*[[:space:]]*//' | awk '{print $1}' | tr -d "\"'")

  # Teammate activation: the `--as <tid>` flag carries the team-format ID
  # (e.g. worker-1@test-static-team) so hooks can map this raw-id state file
  # back to the right teammate slot without guessing.
  ALTERNATE_AGENT_ID=""
  if [[ "$ACTIVATE_LINE" == *"--as "* ]]; then
    _tail="${ACTIVATE_LINE#*--as }"
    ALTERNATE_AGENT_ID="${_tail%% *}"
    ALTERNATE_AGENT_ID="${ALTERNATE_AGENT_ID//\"/}"
    ALTERNATE_AGENT_ID="${ALTERNATE_AGENT_ID//\'/}"
  fi

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

  # Source engine libs up-front so both resolution (workflow_discover_plugin_workflows)
  # and state creation (state_init, workflow_load) are available. Sourcing engine.sh
  # pulls in state.sh + workflow.sh + others via its own guard.
  export WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
  source "${PLUGIN_DIR}/lib/engine.sh"

  # Read workflow file — check local workflows/ first, then scan plugin workflows/ dirs
  WORKFLOW_FILE="workflows/${WORKFLOW_NAME}.json"
  if [[ -n "$WORKFLOW_NAME" && ! -f "$WORKFLOW_FILE" ]]; then
    # Not found locally — check if WORKFLOW_NAME is an absolute path (plugin workflow)
    if [[ -f "$WORKFLOW_NAME" ]]; then
      WORKFLOW_FILE="$WORKFLOW_NAME"
    else
      # Scan installed plugins for a workflows/ dir containing this workflow.
      # Plugin-prefixed names (plugin:name) MUST match both fields, because
      # discovery emits bare .name values — mirrors validate-workflow.sh.
      PLUGIN_WORKFLOWS=$(workflow_discover_plugin_workflows 2>/dev/null || echo '[]')
      if [[ "$WORKFLOW_NAME" == *":"* ]]; then
        PLUGIN_REF="${WORKFLOW_NAME%%:*}"
        NAME_REF="${WORKFLOW_NAME#*:}"
        RESOLVED=$(printf '%s\n' "$PLUGIN_WORKFLOWS" | jq -r \
          --arg plugin "$PLUGIN_REF" --arg name "$NAME_REF" \
          '.[] | select(.plugin == $plugin and .name == $name) | .path // empty' | head -1)
      else
        RESOLVED=$(printf '%s\n' "$PLUGIN_WORKFLOWS" | jq -r \
          --arg name "$WORKFLOW_NAME" \
          '.[] | select(.name == $name) | .path // empty' | head -1)
      fi
      if [[ -n "$RESOLVED" && -f "$RESOLVED" ]]; then
        WORKFLOW_FILE="$RESOLVED"
      fi
    fi
  fi
  ACTIVATE_OK=0
  if [[ -n "$WORKFLOW_NAME" && -f "$WORKFLOW_FILE" ]]; then

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

      # Teammate activation: the --as flag already told us the team-format ID,
      # so stamp it on the child state file directly. No parent-state guess,
      # no lock, no race.
      if [[ -n "$ALTERNATE_AGENT_ID" ]]; then
        _st=$(state_read "$STATE_FILE")
        state_write "$STATE_FILE" "$(printf '%s\n' "$_st" | jq --arg alt "$ALTERNATE_AGENT_ID" '.alternate_agent_id = $alt')"
      fi

      wheel_log_set_state "$STATE_FILE"
      wheel_log "activate" "workflow=${WORKFLOW_NAME} file=${WORKFLOW_FILE}"
      WORKFLOW="$WORKFLOW_JSON"
      export WHEEL_HOOK_SCRIPT=""
      export WHEEL_HOOK_INPUT='{}'
      engine_kickstart "$STATE_FILE" >/dev/null 2>&1
      ACTIVATE_OK=1

      # Clean up legacy pending file if present
      rm -f .wheel/pending.json
    fi
  fi

  if [[ "$ACTIVATE_OK" -eq 1 ]]; then
    wheel_log "exit" "result=activate workflow=${WORKFLOW_NAME}"
  else
    wheel_log "exit" "result=activate-failed workflow=${WORKFLOW_NAME} reason=unresolved-or-invalid"
  fi
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
