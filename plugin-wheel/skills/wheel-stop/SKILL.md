---
name: wheel-stop
description: Stop the currently running workflow. Archives state.json to .wheel/history/ and deactivates hook interception.
---

# Wheel Stop — Stop a Running Workflow

Stop the active workflow, archive the state for history, and deactivate hook interception.

## Step 1: Check if a Workflow is Running

```bash
if [[ ! -f ".wheel/state.json" ]]; then
  echo "No workflow is currently running."
  exit 0
fi
```

If no workflow is running, report that and **stop here**.

## Step 2: Archive State (FR-002)

```bash
mkdir -p .wheel/history
NAME=$(jq -r '.workflow_name' .wheel/state.json)
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
cp .wheel/state.json ".wheel/history/${NAME}-${TIMESTAMP}.json"
```

## Step 3: Remove State

```bash
rm .wheel/state.json
```

## Step 4: Confirm

```bash
echo "Workflow '$NAME' stopped. Archived to .wheel/history/${NAME}-${TIMESTAMP}.json"
echo "Hooks are now dormant."
```

## Rules

- This skill takes no arguments.
- Always archive before removing — never lose workflow history.
- If state.json is corrupted (invalid JSON), still remove it and warn the user.
