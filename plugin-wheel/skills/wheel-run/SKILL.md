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

## Step 1: Obtain Session ID (FR-002)

The session_id is needed to construct the per-agent state filename. Extract it from the environment or conversation context:

```bash
# Try CLAUDE_SESSION_ID env var first, fall back to a generated ID
SESSION_ID="${CLAUDE_SESSION_ID:-}"
if [[ -z "$SESSION_ID" ]]; then
  # Generate a short unique ID if env var not available
  SESSION_ID="s$(date +%s | tail -c 9)"
fi
echo "Session ID: $SESSION_ID"
```

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

## Step 3: Check for Already-Running Workflow (FR-007)

```bash
# FR-007: Check for existing state file for this session
EXISTING=$(ls .wheel/state_${SESSION_ID}*.json 2>/dev/null)
if [[ -n "$EXISTING" ]]; then
  CURRENT=$(jq -r '.workflow_name' $(echo "$EXISTING" | head -1))
  echo "ERROR: Workflow '$CURRENT' is already running for this session."
  echo "State file: $EXISTING"
  echo "Run /wheel-stop to stop it, or /wheel-status to check progress."
  exit 1
fi
```

If this prints an error, **stop here** — do not proceed. Tell the user.

## Step 4: Validate Workflow (FR-006)

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

If validation fails, **stop here** and report the error. Do NOT create a state file.

## Step 5: Create State, Activate, and Kickstart (FR-002, FR-010, FR-011)

```bash
# FR-011: Pass session_id to state_init — creates .wheel/state_{session_id}.json
state_init ".wheel" "$SESSION_ID" "$WORKFLOW" "$WORKFLOW_FILE"

# FR-010: Kickstart with session_id-based filename
STATE_FILE=".wheel/state_${SESSION_ID}.json"
STATE_DIR=".wheel"
export WHEEL_HOOK_SCRIPT=""
export WHEEL_HOOK_INPUT='{}'
KICKSTART_OUTPUT=$(engine_kickstart "$STATE_FILE")
```

## Step 6: Report Success

Read back state and display:

```bash
STEP_COUNT=$(echo "$WORKFLOW" | jq '.steps | length')
WF_NAME=$(echo "$WORKFLOW" | jq -r '.name')
FIRST_STEP_ID=$(echo "$WORKFLOW" | jq -r '.steps[0].id')
FIRST_STEP_TYPE=$(echo "$WORKFLOW" | jq -r '.steps[0].type')

echo "Workflow '$WF_NAME' started ($STEP_COUNT steps)."
echo "Session: $SESSION_ID"
echo "State file: $STATE_FILE"
echo "First step: $FIRST_STEP_ID ($FIRST_STEP_TYPE)"

# Show post-kickstart status
if [[ -f "$STATE_FILE" ]]; then
  CURRENT_CURSOR=$(jq -r '.cursor' "$STATE_FILE")
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

## Ownership (FR-001/FR-003)

State is created with `owner_session_id` set to the session ID and `owner_agent_id` empty. Since the skill does not have an agent_id, the first hook event detects the session-only filename and renames it to include the agent_id (via `resolve_state_file` in `lib/guard.sh`). This two-phase creation ensures each agent gets its own state file.

## Rules

- If `$ARGUMENTS` is empty, ask the user for a workflow name. List available workflows from `workflows/*.json`.
- Never create a state file if validation fails.
- Never create a state file if one already exists for this session (FR-007).
