#!/usr/bin/env bash
# validate-workflow.sh — Resolve, validate, and report workflow metadata
# Keeps workflow JSON OUT of the LLM's context. Only prints a short summary.
#
# Usage: validate-workflow.sh <workflow-name-or-plugin:name>
# Output: One-line JSON summary on success, human-readable error on failure
# Exit:   0 on valid, 1 on invalid

set -euo pipefail

WORKFLOW_NAME="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"

source "${WHEEL_LIB_DIR}/workflow.sh"

# --- Pre-flight ---
if [ ! -d ".wheel" ]; then
  echo "ERROR: Wheel is not set up. Run /wheel-init first." >&2
  exit 1
fi

# --- Resolve workflow file ---
WORKFLOW_FILE=""
WORKFLOW_NAME_FOR_ACTIVATE=""

if [[ "$WORKFLOW_NAME" == *":"* ]]; then
  # Plugin workflow
  PLUGIN_NAME_REF="${WORKFLOW_NAME%%:*}"
  WF_NAME_REF="${WORKFLOW_NAME#*:}"

  PLUGIN_WORKFLOWS=$(workflow_discover_plugin_workflows)
  WORKFLOW_FILE=$(printf '%s\n' "$PLUGIN_WORKFLOWS" | jq -r \
    --arg plugin "$PLUGIN_NAME_REF" --arg name "$WF_NAME_REF" \
    '.[] | select(.plugin == $plugin and .name == $name) | .path // empty')

  if [[ -z "$WORKFLOW_FILE" ]]; then
    echo "ERROR: Plugin workflow not found: $WORKFLOW_NAME" >&2
    printf '%s\n' "$PLUGIN_WORKFLOWS" | jq -r '.[] | "  \(.plugin):\(.name)"' >&2
    exit 1
  fi

  # Check for local override
  if [[ -f "workflows/${WF_NAME_REF}.json" ]]; then
    WORKFLOW_FILE="workflows/${WF_NAME_REF}.json"
    WORKFLOW_NAME_FOR_ACTIVATE="$WORKFLOW_NAME"
  else
    WORKFLOW_NAME_FOR_ACTIVATE="$WORKFLOW_FILE"
  fi
else
  # Local workflow
  WORKFLOW_FILE="workflows/${WORKFLOW_NAME}.json"
  if [[ ! -f "$WORKFLOW_FILE" ]]; then
    echo "ERROR: Workflow file not found: $WORKFLOW_FILE" >&2
    echo "Available workflows:" >&2
    ls workflows/*.json 2>/dev/null | sed 's|workflows/||;s|\.json||' | sed 's/^/  /' >&2 || echo "  (none)" >&2
    exit 1
  fi
  WORKFLOW_NAME_FOR_ACTIVATE="$WORKFLOW_NAME"
fi

# --- Check existing workflows (informational) ---
EXISTING=$(ls .wheel/state_*.json 2>/dev/null || true)
if [[ -n "$EXISTING" ]]; then
  echo "Note: Other workflows already running." >&2
  for sf in $EXISTING; do
    NAME=$(jq -r '.workflow_name // "unknown"' "$sf" 2>/dev/null || echo "unknown")
    echo "  $(basename "$sf"): $NAME" >&2
  done
fi

# --- Validate ---
WORKFLOW=$(workflow_load "$WORKFLOW_FILE")
if [[ $? -ne 0 ]]; then
  echo "ERROR: Workflow validation failed." >&2
  exit 1
fi

if ! workflow_validate_unique_ids "$WORKFLOW"; then
  echo "ERROR: Duplicate step IDs found." >&2
  exit 1
fi

# --- Output summary (NO step details, NO workflow content) ---
WF_NAME=$(printf '%s\n' "$WORKFLOW" | jq -r '.name')
STEP_COUNT=$(printf '%s\n' "$WORKFLOW" | jq '.steps | length')

jq -n \
  --arg name "$WF_NAME" \
  --argjson step_count "$STEP_COUNT" \
  --arg activate_name "$WORKFLOW_NAME_FOR_ACTIVATE" \
  --arg plugin_dir "$PLUGIN_DIR" \
  '{name: $name, step_count: $step_count, activate_name: $activate_name, plugin_dir: $plugin_dir}'
