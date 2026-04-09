---
name: wheel-run
description: Start a workflow by name or plugin:name. Validates the workflow JSON, creates per-agent state file, and activates hook interception. Usage: /wheel-run <workflow-name> or /wheel-run <plugin>:<workflow-name>
---

# Wheel Run — Start a Workflow

Start a named workflow so that wheel hooks begin intercepting Claude Code events. Supports both local workflows (`workflows/<name>.json`) and plugin-provided workflows (`<plugin>:<workflow-name>`).

## User Input

```text
$ARGUMENTS
```

## Step 0: Pre-flight Check (FR-007, FR-008)

Check that wheel infrastructure exists before attempting workflow execution.

```bash
# FR-007: Verify wheel directory exists
if [ ! -d ".wheel" ]; then
  echo "Wheel is not set up for this repo."
  echo ""
  echo "Running wheel init to set up..."
  PLUGIN_DIR="$SKILL_BASE_DIR/../.."
  node "${PLUGIN_DIR}/bin/init.mjs" init
  echo ""
  echo "Setup complete — continuing with workflow."
fi
```

If the `.wheel/` directory does not exist, automatically run the init script from the installed plugin path to set up wheel, then continue with the workflow.

## Step 1: Resolve Workflow File (FR-031)

The workflow name comes from `$ARGUMENTS`. Resolve it to a file path. If the name contains `:`, treat it as a `<plugin>:<workflow-name>` reference and look up the workflow from the plugin's install path.

```bash
WORKFLOW_NAME="$ARGUMENTS"
PLUGIN_DIR="$SKILL_BASE_DIR/../.."
WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
source "${WHEEL_LIB_DIR}/workflow.sh"

IS_PLUGIN_WORKFLOW=false

if [[ "$WORKFLOW_NAME" == *":"* ]]; then
  # FR-031: Plugin workflow — resolve via plugin manifest discovery
  PLUGIN_NAME="${WORKFLOW_NAME%%:*}"
  WF_NAME="${WORKFLOW_NAME#*:}"

  PLUGIN_WORKFLOWS=$(workflow_discover_plugin_workflows)
  WORKFLOW_FILE=$(printf '%s\n' "$PLUGIN_WORKFLOWS" | jq -r \
    --arg plugin "$PLUGIN_NAME" --arg name "$WF_NAME" \
    '.[] | select(.plugin == $plugin and .name == $name) | .path // empty')

  if [[ -z "$WORKFLOW_FILE" ]]; then
    echo "ERROR: Plugin workflow not found: $WORKFLOW_NAME"
    echo ""
    echo "Available plugin workflows:"
    printf '%s\n' "$PLUGIN_WORKFLOWS" | jq -r '.[] | "  \(.plugin):\(.name)"'
    AVAILABLE=$(printf '%s\n' "$PLUGIN_WORKFLOWS" | jq 'length')
    if [[ "$AVAILABLE" -eq 0 ]]; then
      echo "  (none — no installed plugins declare workflows)"
    fi
    exit 1
  fi

  # FR-030: Check for local override
  if [[ -f "workflows/${WF_NAME}.json" ]]; then
    echo "Note: Local override found at workflows/${WF_NAME}.json — using local copy instead of plugin version."
    WORKFLOW_FILE="workflows/${WF_NAME}.json"
  else
    IS_PLUGIN_WORKFLOW=true
  fi

  # For activate.sh, use the resolved absolute path
  WORKFLOW_NAME_FOR_ACTIVATE="$WORKFLOW_FILE"
else
  # Local workflow — resolve from workflows/ directory
  WORKFLOW_FILE="workflows/${WORKFLOW_NAME}.json"
  if [[ ! -f "$WORKFLOW_FILE" ]]; then
    echo "ERROR: Workflow file not found: $WORKFLOW_FILE"
    echo "Available workflows:"
    ls workflows/*.json 2>/dev/null || echo "  (none)"
    exit 1
  fi
  WORKFLOW_NAME_FOR_ACTIVATE="$WORKFLOW_NAME"
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

Source the remaining wheel engine libs (workflow.sh already sourced in Step 1) and validate:

```bash
# workflow.sh already sourced in Step 1 for plugin discovery
source "${WHEEL_LIB_DIR}/state.sh"
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

For plugin workflows, `WORKFLOW_NAME_FOR_ACTIVATE` is the absolute path to the workflow file (so the hook can find it). For local workflows, it's the bare name.

```bash
# Run activate.sh — the PostToolUse hook intercepts this call,
# reads the workflow file, and creates the state file with proper ownership
mkdir -p .wheel
"${PLUGIN_DIR}/bin/activate.sh" "$WORKFLOW_NAME_FOR_ACTIVATE"
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

State file creation happens in the PostToolUse hook, NOT in the skill. The hook reads the workflow file directly (no intermediate pending file), validates it, and creates the state file with session_id and agent_id from the hook input JSON.

The flow for local workflows:
1. Skill validates workflow (early error reporting)
2. Skill runs `activate.sh <name>` (no-op script)
3. PostToolUse hook fires → sees `activate.sh` in command → reads `workflows/<name>.json` → validates → creates `state_{sid}_{aid}.json` → runs kickstart

The flow for plugin workflows (FR-031):
1. Skill resolves `<plugin>:<name>` to absolute path via `workflow_discover_plugin_workflows()`
2. Skill validates workflow at that path (early error reporting)
3. Skill runs `activate.sh <absolute-path>` (no-op script)
4. PostToolUse hook fires → sees `activate.sh` in command → reads workflow at the given path → validates → creates state file → runs kickstart

No race condition: the hook reads the workflow file directly. No shared mutable state between concurrent agents.

## Rules

- If `$ARGUMENTS` is empty, ask the user for a workflow name. List available workflows from `workflows/*.json` and installed plugins.
- Never create a state file directly — always go through activate.sh + hook.
- Plugin workflows are read-only (FR-030) — they execute from the plugin's install path. Users can copy to `workflows/` to customize, and the local copy takes precedence.

## Execution Behavior (NON-NEGOTIABLE)

After activation, **all workflow progression happens through hooks**. Do not manually advance the cursor, update step statuses, or modify state files yourself.

- **Do NOT spawn sub-agents** for any workflow step — including `"type": "workflow"` steps. Workflow steps are like function calls: the referenced workflow runs inline in the same conversation, dispatched by the hook system.
- **Do NOT manually stop workflows.** Use `/wheel-stop` and let the hook handle archival. If the hook doesn't clean up, investigate why — do not bypass it with manual `jq`/`rm`.
- **Do NOT manually archive or delete state files.** The hook system owns the workflow lifecycle.
- The purpose of `"type": "workflow"` steps is to **avoid duplication** between workflows — they compose existing workflows as reusable units, not as separate agents.
- Your only job after activation is to **execute the current step's work** (e.g., run commands, write files for agent steps) and let hooks handle progression to the next step.
