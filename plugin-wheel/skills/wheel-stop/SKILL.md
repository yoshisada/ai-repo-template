---
name: wheel-stop
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
```

If no workflows are running, report that and **stop here**.

## Step 2: Filter by Target (FR-009)

```bash
TARGET="$ARGUMENTS"
if [[ -n "$TARGET" ]]; then
  # Filter to matching files — match on session_id or agent_id in filename
  MATCHED=()
  for sf in "${STATE_FILES[@]}"; do
    FILENAME=$(basename "$sf")
    if [[ "$FILENAME" == *"$TARGET"* ]]; then
      MATCHED+=("$sf")
    fi
  done
  if [[ ${#MATCHED[@]} -eq 0 ]]; then
    echo "ERROR: No workflow found matching '$TARGET'."
    echo "Active state files:"
    printf '  %s\n' "${STATE_FILES[@]}"
    exit 1
  fi
  STATE_FILES=("${MATCHED[@]}")
fi
```

## Step 3: Archive and Remove Each Workflow (FR-009)

```bash
mkdir -p .wheel/history
for sf in "${STATE_FILES[@]}"; do
  NAME=$(jq -r '.workflow_name // "unknown"' "$sf" 2>/dev/null || echo "unknown")
  TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
  FILENAME=$(basename "$sf" .json)
  cp "$sf" ".wheel/history/${FILENAME}-${TIMESTAMP}.json"
  rm "$sf"
  echo "Stopped workflow '$NAME'. Archived to .wheel/history/${FILENAME}-${TIMESTAMP}.json"
done
echo "Hooks are now dormant."
```

## Rules

- If `$ARGUMENTS` is empty, stop all active workflows.
- If `$ARGUMENTS` is provided, filter to matching state files by session_id or agent_id substring.
- Always archive before removing — never lose workflow history.
- If a state file is corrupted (invalid JSON), still remove it and warn the user.
