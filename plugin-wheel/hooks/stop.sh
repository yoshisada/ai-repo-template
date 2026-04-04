#!/usr/bin/env bash
# stop.sh — Stop hook handler
# FR-004: Gates the parent orchestrator, injects next step instruction,
# or allows stop when workflow is complete

set -euo pipefail

# Resolve paths
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${HOOK_DIR}/.." && pwd)"

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Export for command chaining (FR-020)
export WHEEL_HOOK_SCRIPT="${BASH_SOURCE[0]}"
export WHEEL_HOOK_INPUT="$HOOK_INPUT"

# Source the engine
source "${PLUGIN_DIR}/lib/engine.sh"

# Find the active workflow file
# Convention: first .json file in workflows/ directory, or WHEEL_WORKFLOW env var
WORKFLOW_FILE="${WHEEL_WORKFLOW:-}"
if [[ -z "$WORKFLOW_FILE" ]]; then
  WORKFLOW_FILE=$(find workflows/ -name '*.json' -type f 2>/dev/null | head -1)
fi

if [[ -z "$WORKFLOW_FILE" || ! -f "$WORKFLOW_FILE" ]]; then
  # No workflow — allow stop (wheel is not active)
  echo '{"decision": "allow"}'
  exit 0
fi

# Initialize engine
if ! engine_init "$WORKFLOW_FILE" ".wheel"; then
  echo '{"decision": "allow"}'
  exit 0
fi

# Handle the hook
engine_handle_hook "stop" "$HOOK_INPUT"
