---
name: status
description: Show the status of all running workflows. Displays workflow name, current step, progress, session/agent IDs, and elapsed time.
---

# Wheel Status — Check Workflow Progress

Display the current state of all active workflows.

## Step 1: Check if Any Workflow is Running (FR-008)

```bash
STATE_FILES=($(ls .wheel/state_*.json 2>/dev/null))
if [[ ${#STATE_FILES[@]} -eq 0 ]]; then
  echo "No workflows are currently running."
  exit 0
fi
```

If no workflows are running, report that and **stop here**.

## Step 2: Display All Active Workflows (FR-008)

```bash
echo "Active workflows: ${#STATE_FILES[@]}"
echo ""

for sf in "${STATE_FILES[@]}"; do
  STATE=$(cat "$sf")
  NAME=$(echo "$STATE" | jq -r '.workflow_name')
  STATUS=$(echo "$STATE" | jq -r '.status')
  CURSOR=$(echo "$STATE" | jq -r '.cursor')
  TOTAL=$(echo "$STATE" | jq '.steps | length')
  STEP_ID=$(echo "$STATE" | jq -r ".steps[$CURSOR].id")
  STEP_STATUS=$(echo "$STATE" | jq -r ".steps[$CURSOR].status")
  STARTED=$(echo "$STATE" | jq -r '.started_at')
  OWNER_SID=$(echo "$STATE" | jq -r '.owner_session_id // "(none)"')
  OWNER_AID=$(echo "$STATE" | jq -r '.owner_agent_id // "(none)"')
  LAST_CMD=$(echo "$STATE" | jq -r ".steps[$CURSOR].command_log[-1].command // \"(none)\"")
  FILENAME=$(basename "$sf")

  echo "--- $FILENAME ---"
  echo "Workflow: $NAME"
  echo "Status:   $STATUS"
  echo "Owner:    session=$OWNER_SID agent=$OWNER_AID"
  echo "Step:     $STEP_ID ($((CURSOR + 1))/$TOTAL)"
  echo "Step status: $STEP_STATUS"
  echo "Last command: $LAST_CMD"
  echo "Started: $STARTED"
  echo ""
done
```

## Rules

- This skill takes no arguments.
- If any state file is corrupted (invalid JSON), report the error for that file and suggest running `/wheel:stop` to clean up.
- If the workflow file referenced in a state file no longer exists, report that error.
