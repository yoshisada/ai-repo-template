#!/usr/bin/env bash
# session-start.sh — SessionStart hook handler
# FR-008: Reloads state.json on resume and injects resume instructions

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
  echo '{"decision": "allow"}'
  exit 0
fi

# Check if state.json exists (nothing to resume if it doesn't)
if [[ ! -f ".wheel/state.json" ]]; then
  echo '{"decision": "allow"}'
  exit 0
fi

if ! engine_init "$WORKFLOW_FILE" ".wheel"; then
  echo '{"decision": "allow"}'
  exit 0
fi

engine_handle_hook "session_start" "$HOOK_INPUT"
