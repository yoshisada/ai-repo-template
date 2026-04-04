---
name: wheel-run
description: Start a workflow by name. Validates the workflow JSON, creates .wheel/state.json, and activates hook interception. Usage: /wheel-run <workflow-name>
---

# Wheel Run — Start a Workflow

Start a named workflow so that wheel hooks begin intercepting Claude Code events. The workflow file must exist at `workflows/<name>.json`.

## User Input

```text
$ARGUMENTS
```

## Step 1: Check for Already-Running Workflow (FR-007)

Run:

```bash
if [[ -f ".wheel/state.json" ]]; then
  CURRENT=$(jq -r '.workflow_name' .wheel/state.json)
  echo "ERROR: Workflow '$CURRENT' is already running."
  echo "Run /wheel-stop to stop it, or /wheel-status to check progress."
  exit 1
fi
```

If this prints an error, **stop here** — do not proceed. Tell the user.

## Step 2: Resolve Workflow File

The workflow name comes from `$ARGUMENTS`. Resolve it to a file path:

```bash
WORKFLOW_NAME="$ARGUMENTS"
WORKFLOW_FILE="workflows/${WORKFLOW_NAME}.json"
if [[ ! -f "$WORKFLOW_FILE" ]]; then
  echo "ERROR: Workflow file not found: $WORKFLOW_FILE"
  echo "Available workflows:"
  ls workflows/*.json 2>/dev/null || echo "  (none)"
  exit 1
fi
```

If the file doesn't exist, **stop here** and show the error.

## Step 3: Validate Workflow (FR-006)

Source the wheel engine libs and validate:

```bash
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_DIR="$(cd "${HOOK_DIR}/../../" && pwd)"
source "${PLUGIN_DIR}/lib/engine.sh"

# workflow_load validates: valid JSON, required fields, branch targets
WORKFLOW=$(workflow_load "$WORKFLOW_FILE")
if [[ $? -ne 0 ]]; then
  echo "ERROR: Workflow validation failed. See errors above."
  exit 1
fi

# Validate unique step IDs
if ! workflow_validate_unique_ids "$WORKFLOW"; then
  echo "ERROR: Workflow has duplicate step IDs. Each step must have a unique id."
  exit 1
fi
```

If validation fails, **stop here** and report the error. Do NOT create state.json.

## Step 4: Create State, Activate, and Kickstart (FR-001)

```bash
state_init ".wheel/state.json" "$WORKFLOW" "$WORKFLOW_FILE"

# Kickstart: dispatch the first step inline so command/loop/branch
# workflows don't stall waiting for a hook event
STATE_DIR=".wheel"
STATE_FILE=".wheel/state.json"
KICKSTART_OUTPUT=$(engine_kickstart ".wheel/state.json")
```

## Step 5: Report Success

Read back state and display:

```bash
STEP_COUNT=$(echo "$WORKFLOW" | jq '.steps | length')
WF_NAME=$(echo "$WORKFLOW" | jq -r '.name')
FIRST_STEP_ID=$(echo "$WORKFLOW" | jq -r '.steps[0].id')
FIRST_STEP_TYPE=$(echo "$WORKFLOW" | jq -r '.steps[0].type')

echo "Workflow '$WF_NAME' started ($STEP_COUNT steps)."
echo "First step: $FIRST_STEP_ID ($FIRST_STEP_TYPE)"

# Show post-kickstart status
if [[ -f ".wheel/state.json" ]]; then
  CURRENT_CURSOR=$(jq -r '.cursor' .wheel/state.json)
  CURRENT_STEP_ID=$(echo "$WORKFLOW" | jq -r --argjson idx "$CURRENT_CURSOR" '.steps[$idx].id // "complete"')
  CURRENT_STEP_TYPE=$(echo "$WORKFLOW" | jq -r --argjson idx "$CURRENT_CURSOR" '.steps[$idx].type // "done"')
  if [[ "$CURRENT_CURSOR" -gt 0 ]]; then
    echo "Kickstarted: advanced to step $CURRENT_STEP_ID ($CURRENT_STEP_TYPE)"
  fi
else
  echo "Workflow completed during kickstart (all steps were automatic)."
fi

echo ""
if [[ -n "$KICKSTART_OUTPUT" ]]; then
  echo "First agent instruction:"
  echo "$KICKSTART_OUTPUT"
fi
echo "Hooks are now active. Run /wheel-status to check progress, /wheel-stop to deactivate."
```

## Rules

- If `$ARGUMENTS` is empty, ask the user for a workflow name. List available workflows from `workflows/*.json`.
- Never create state.json if validation fails.
- Never overwrite an existing state.json — always check first (FR-007).
