---
name: wheel-run
description: Start a workflow by name. Validates the workflow JSON, creates per-agent state file, and activates hook interception. Usage: /wheel-run <workflow-name>
---

# Wheel Run — Start a Workflow

Start a named workflow so that wheel hooks begin intercepting Claude Code events. The workflow file must exist at `workflows/<name>.json`.

## User Input

```text
$ARGUMENTS
```

## Step 1: Resolve Workflow File

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

## Step 2: Check for Already-Running Workflow (FR-007)

```bash
# FR-007: Check for existing state files (any agent)
EXISTING=$(ls .wheel/state_*.json 2>/dev/null || true)
if [[ -n "$EXISTING" ]]; then
  echo "Active workflows:"
  for sf in $EXISTING; do
    NAME=$(jq -r '.workflow_name // "unknown"' "$sf" 2>/dev/null || echo "unknown")
    echo "  $(basename $sf): $NAME"
  done
  echo ""
  echo "Run /wheel-stop to stop them, or /wheel-status to check progress."
  echo "Multiple concurrent workflows are supported — proceeding."
fi
```

Note: Multiple workflows CAN run concurrently (one per agent). This check is informational.

## Step 3: Validate Workflow

Source the wheel engine libs and validate:

```bash
PLUGIN_DIR="$SKILL_BASE_DIR/../.."
WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
source "${WHEEL_LIB_DIR}/state.sh"
source "${WHEEL_LIB_DIR}/workflow.sh"
source "${WHEEL_LIB_DIR}/dispatch.sh"
source "${WHEEL_LIB_DIR}/lock.sh"
source "${WHEEL_LIB_DIR}/context.sh"
source "${WHEEL_LIB_DIR}/engine.sh"

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

If validation fails, **stop here** and report the error.

## Step 4: Activate

The skill does NOT create the state file directly. It runs `activate.sh` which the PostToolUse hook intercepts. The hook reads the workflow file directly (no intermediate files), validates it, and creates the state file with the correct session_id and agent_id from hook input.

```bash
# Run activate.sh — the PostToolUse hook intercepts this call,
# reads the workflow file, and creates the state file with proper ownership
mkdir -p .wheel
"${PLUGIN_DIR}/bin/activate.sh" "$WORKFLOW_NAME"
```

## Step 5: Report Success

After activate.sh runs, the PostToolUse hook has created the state file and run kickstart. Report the result:

```bash
WF_NAME=$(echo "$WORKFLOW" | jq -r '.name')
STEP_COUNT=$(echo "$WORKFLOW" | jq '.steps | length')
FIRST_STEP_ID=$(echo "$WORKFLOW" | jq -r '.steps[0].id')
FIRST_STEP_TYPE=$(echo "$WORKFLOW" | jq -r '.steps[0].type')

echo "Workflow '$WF_NAME' started ($STEP_COUNT steps)."
echo "First step: $FIRST_STEP_ID ($FIRST_STEP_TYPE)"

# Find the state file that was created by the hook
STATE_FILE=$(ls -t .wheel/state_*.json 2>/dev/null | head -1 || true)
if [[ -n "$STATE_FILE" && -f "$STATE_FILE" ]]; then
  OWNER_SID=$(jq -r '.owner_session_id // "(unknown)"' "$STATE_FILE")
  OWNER_AID=$(jq -r '.owner_agent_id // "(none)"' "$STATE_FILE")
  CURRENT_CURSOR=$(jq -r '.cursor' "$STATE_FILE")
  echo "State file: $(basename $STATE_FILE)"
  echo "Owner: session=$OWNER_SID agent=$OWNER_AID"

  CURRENT_STEP_ID=$(echo "$WORKFLOW" | jq -r --argjson idx "$CURRENT_CURSOR" '.steps[$idx].id // "complete"')
  if [[ "$CURRENT_CURSOR" -gt 0 ]]; then
    echo "Kickstarted: advanced to step $CURRENT_STEP_ID"
  fi
else
  echo "Workflow completed during kickstart (all steps were automatic)."
fi

echo ""
echo "Hooks are now active. Run /wheel-status to check progress, /wheel-stop to deactivate."
```

## Ownership

State file creation happens in the PostToolUse hook, NOT in the skill. The hook reads the workflow file directly from `workflows/<name>.json` (no intermediate pending file), validates it, and creates the state file with session_id and agent_id from the hook input JSON.

The flow:
1. Skill validates workflow (early error reporting)
2. Skill runs `activate.sh <name>` (no-op script)
3. PostToolUse hook fires → sees `activate.sh` in command → reads `workflows/<name>.json` → validates → creates `state_{sid}_{aid}.json` → runs kickstart

No race condition: the hook reads the workflow file directly. No shared mutable state between concurrent agents.

## Rules

- If `$ARGUMENTS` is empty, ask the user for a workflow name. List available workflows from `workflows/*.json`.
- Never create a state file directly — always go through activate.sh + hook.
