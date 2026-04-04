#!/usr/bin/env bash
# stop.sh — Stop hook handler
# FR-004: Gates the parent orchestrator, injects next step instruction,
# or allows stop when workflow is complete
set -euo pipefail

# FR-004: Guard — exit if no workflow active
if [[ ! -f ".wheel/state.json" ]]; then
  echo '{"decision": "allow"}'
  exit 0
fi

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Resolve paths
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${HOOK_DIR}/.." && pwd)"

# FR-005: Read workflow file path from state.json (no auto-discovery)
WORKFLOW_FILE=$(jq -r '.workflow_file // empty' ".wheel/state.json")
if [[ -z "$WORKFLOW_FILE" || ! -f "$WORKFLOW_FILE" ]]; then
  echo '{"decision": "allow"}'
  exit 0
fi

# Export for command chaining (FR-020)
export WHEEL_HOOK_SCRIPT="${BASH_SOURCE[0]}"
export WHEEL_HOOK_INPUT="$HOOK_INPUT"

# Source the engine
source "${PLUGIN_DIR}/lib/engine.sh"

# Initialize engine (loads workflow, reads state — does NOT create state)
if ! engine_init "$WORKFLOW_FILE" ".wheel"; then
  echo '{"decision": "allow"}'
  exit 0
fi

engine_handle_hook "stop" "$HOOK_INPUT"
