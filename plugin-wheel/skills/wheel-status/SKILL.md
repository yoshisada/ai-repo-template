---
name: wheel-status
description: Show the status of the currently running workflow. Displays workflow name, current step, progress, and elapsed time.
---

# Wheel Status — Check Workflow Progress

Display the current state of the active workflow.

## Step 1: Check if a Workflow is Running

```bash
if [[ ! -f ".wheel/state.json" ]]; then
  echo "No workflow is currently running."
  exit 0
fi
```

If no workflow is running, report that and **stop here**.

## Step 2: Read and Display State (FR-003)

```bash
STATE=$(cat .wheel/state.json)
NAME=$(echo "$STATE" | jq -r '.workflow_name')
STATUS=$(echo "$STATE" | jq -r '.status')
CURSOR=$(echo "$STATE" | jq -r '.cursor')
TOTAL=$(echo "$STATE" | jq '.steps | length')
STEP_ID=$(echo "$STATE" | jq -r ".steps[$CURSOR].id")
STEP_STATUS=$(echo "$STATE" | jq -r ".steps[$CURSOR].status")
STARTED=$(echo "$STATE" | jq -r '.started_at')
LAST_CMD=$(echo "$STATE" | jq -r ".steps[$CURSOR].command_log[-1].command // \"(none)\"")

echo "Workflow: $NAME"
echo "Status:   $STATUS"
echo "Step:     $STEP_ID ($((CURSOR + 1))/$TOTAL)"
echo "Step status: $STEP_STATUS"
echo "Last command: $LAST_CMD"
echo "Started: $STARTED"
```

## Rules

- This skill takes no arguments.
- If state.json is corrupted (invalid JSON), report the error and suggest running `/wheel-stop` to clean up.
- If the workflow file referenced in state.json no longer exists, report that error.
