#!/usr/bin/env bash
# teammate-idle.sh — TeammateIdle hook handler
# FR-005: Gates agents with their agent-specific next task,
# or allows idle when the step is done

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

engine_handle_hook "teammate_idle" "$HOOK_INPUT"
