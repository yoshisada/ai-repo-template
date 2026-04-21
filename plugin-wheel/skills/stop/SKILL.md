---
name: stop
description: Stop running workflows. Archives state files to .wheel/history/ and deactivates hook interception. Optionally target a specific workflow by session_id or agent_id.
---

# Wheel Stop — Stop Running Workflows

Stop active workflows, archive the state for history, and deactivate hook interception.

## User Input

```text
$ARGUMENTS
```

## Step 1: Find Active Workflows (FR-009)

```bash
STATE_FILES=($(ls .wheel/state_*.json 2>/dev/null))
if [[ ${#STATE_FILES[@]} -eq 0 ]]; then
  echo "No workflows are currently running."
  exit 0
fi
echo "Found ${#STATE_FILES[@]} active workflow(s):"
for sf in "${STATE_FILES[@]}"; do
  NAME=$(jq -r '.workflow_name // "unknown"' "$sf" 2>/dev/null || echo "unknown")
  OWNER_SID=$(jq -r '.owner_session_id // "?"' "$sf" 2>/dev/null || echo "?")
  OWNER_AID=$(jq -r '.owner_agent_id // "none"' "$sf" 2>/dev/null || echo "none")
  echo "  $(basename $sf): $NAME (owner: session=$OWNER_SID agent=$OWNER_AID)"
done
```

If no workflows are running, report that and **stop here**.

## Step 2: Deactivate via Hook Interception

The skill does NOT directly delete state files. Instead, it calls `deactivate.sh` so the PostToolUse hook handles cleanup with proper ownership resolution from hook input.

```bash
PLUGIN_DIR="$SKILL_BASE_DIR/../.."
TARGET="$ARGUMENTS"

if [[ -z "$TARGET" ]]; then
  # No target — stop only the caller's own workflow (ownership-aware)
  "${PLUGIN_DIR}/bin/deactivate.sh"
elif [[ "$TARGET" == "--all" || "$TARGET" == "all" ]]; then
  # Stop ALL workflows
  "${PLUGIN_DIR}/bin/deactivate.sh" --all
else
  # Stop matching workflows by target
  "${PLUGIN_DIR}/bin/deactivate.sh" "$TARGET"
fi
```

## Step 3: Report Results

```bash
REMAINING=($(ls .wheel/state_*.json 2>/dev/null))
STOPPED_COUNT=$((${#STATE_FILES[@]} - ${#REMAINING[@]}))
echo ""
echo "Stopped $STOPPED_COUNT workflow(s)."
if [[ ${#REMAINING[@]} -gt 0 ]]; then
  echo "${#REMAINING[@]} workflow(s) still running:"
  for sf in "${REMAINING[@]}"; do
    NAME=$(jq -r '.workflow_name // "unknown"' "$sf" 2>/dev/null || echo "unknown")
    echo "  $(basename $sf): $NAME"
  done
  echo ""
  echo "Use '/wheel:stop --all' to stop all workflows, or '/wheel:stop <target>' to target specific ones."
else
  echo "All workflows stopped. Hooks are now dormant."
fi
```

## Rules

- If `$ARGUMENTS` is empty, stop **only the caller's own workflow** (ownership-aware via PostToolUse hook interception). This is safe for concurrent workflows.
- If `$ARGUMENTS` is `--all` or `all`, stop all active workflows regardless of ownership.
- If `$ARGUMENTS` is a specific target, filter to matching state files by session_id or agent_id substring in the filename.
- Always archive before removing — never lose workflow history.
- If a state file is corrupted (invalid JSON), still archive and remove it.
