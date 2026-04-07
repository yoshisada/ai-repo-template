---
name: wheel-list
description: List all available wheel workflows. Scans workflows/ directory and displays names, step counts, step types, validation status, grouped by directory.
---

# Wheel List — Discover Available Workflows

Display all wheel workflow files in the project, grouped by directory, with metadata and validation status.

## Step 1: Scan for Workflow Files (FR-001)

```bash
WORKFLOW_FILES=($(find workflows/ -name "*.json" -type f 2>/dev/null | sort))
if [[ ${#WORKFLOW_FILES[@]} -eq 0 ]]; then
  echo "NO_WORKFLOWS_FOUND"
fi
```

If the output contains `NO_WORKFLOWS_FOUND`, skip to the **Empty State** section below.

## Step 2: Parse, Validate & Group (FR-002, FR-003, FR-004)

For each workflow file found in Step 1, extract metadata and validate. Group results by parent directory.

```bash
declare -A DIR_RESULTS

for WF_FILE in "${WORKFLOW_FILES[@]}"; do
  DIR=$(dirname "$WF_FILE")
  BASENAME=$(basename "$WF_FILE" .json)

  # Try to parse JSON
  if ! JSON=$(cat "$WF_FILE" 2>/dev/null) || ! echo "$JSON" | jq empty 2>/dev/null; then
    DIR_RESULTS["$DIR"]+="| $BASENAME | - | - | - | ERROR: invalid JSON |"$'\n'
    continue
  fi

  # Extract name
  NAME=$(echo "$JSON" | jq -r '.name // empty')
  if [[ -z "$NAME" ]]; then
    DIR_RESULTS["$DIR"]+="| $BASENAME | - | - | - | ERROR: missing name field |"$'\n'
    continue
  fi

  # Check steps array exists and is non-empty
  STEP_COUNT=$(echo "$JSON" | jq '.steps | length' 2>/dev/null)
  if [[ -z "$STEP_COUNT" || "$STEP_COUNT" -eq 0 ]]; then
    DIR_RESULTS["$DIR"]+="| $NAME | 0 | - | - | ERROR: empty or missing steps |"$'\n'
    continue
  fi

  # Extract unique step types
  STEP_TYPES=$(echo "$JSON" | jq -r '[.steps[].type] | unique | join(", ")' 2>/dev/null)

  # Check for composition (workflow-type steps)
  HAS_COMPOSITION=$(echo "$JSON" | jq '[.steps[] | select(.type == "workflow")] | length' 2>/dev/null)
  if [[ "$HAS_COMPOSITION" -gt 0 ]]; then
    COMP="Yes"
  else
    COMP="No"
  fi

  # Validate step IDs are unique
  TOTAL_IDS=$(echo "$JSON" | jq '[.steps[].id] | length' 2>/dev/null)
  UNIQUE_IDS=$(echo "$JSON" | jq '[.steps[].id] | unique | length' 2>/dev/null)
  if [[ "$TOTAL_IDS" -ne "$UNIQUE_IDS" ]]; then
    DIR_RESULTS["$DIR"]+="| $NAME | $STEP_COUNT | $STEP_TYPES | $COMP | ERROR: duplicate step IDs |"$'\n'
    continue
  fi

  # Validate all steps have id and type
  MISSING=$(echo "$JSON" | jq '[.steps[] | select(.id == null or .type == null)] | length' 2>/dev/null)
  if [[ "$MISSING" -gt 0 ]]; then
    DIR_RESULTS["$DIR"]+="| $NAME | $STEP_COUNT | $STEP_TYPES | $COMP | ERROR: $MISSING step(s) missing id/type |"$'\n'
    continue
  fi

  # Validate branch targets and context_from references
  ALL_IDS=$(echo "$JSON" | jq -r '[.steps[].id] | join(",")' 2>/dev/null)
  VALIDATION_ERROR=""

  # Check branch targets
  BRANCH_TARGETS=$(echo "$JSON" | jq -r '.steps[] | select(.type=="branch") | .if_zero, .if_nonzero' 2>/dev/null)
  while IFS= read -r TARGET; do
    [[ -z "$TARGET" ]] && continue
    if ! echo ",$ALL_IDS," | grep -q ",$TARGET,"; then
      VALIDATION_ERROR="ERROR: invalid branch target '$TARGET'"
      break
    fi
  done <<< "$BRANCH_TARGETS"

  # Check context_from references
  if [[ -z "$VALIDATION_ERROR" ]]; then
    CTX_REFS=$(echo "$JSON" | jq -r '.steps[] | select(.context_from != null) | .context_from[]' 2>/dev/null)
    while IFS= read -r REF; do
      [[ -z "$REF" ]] && continue
      if ! echo ",$ALL_IDS," | grep -q ",$REF,"; then
        VALIDATION_ERROR="ERROR: invalid context_from ref '$REF'"
        break
      fi
    done <<< "$CTX_REFS"
  fi

  if [[ -n "$VALIDATION_ERROR" ]]; then
    DIR_RESULTS["$DIR"]+="| $NAME | $STEP_COUNT | $STEP_TYPES | $COMP | $VALIDATION_ERROR |"$'\n'
  else
    DIR_RESULTS["$DIR"]+="| $NAME | $STEP_COUNT | $STEP_TYPES | $COMP | Valid |"$'\n'
  fi
done

# Display grouped results
TOTAL_WORKFLOWS=0
for DIR in $(echo "${!DIR_RESULTS[@]}" | tr ' ' '\n' | sort); do
  echo "## $DIR/"
  echo ""
  echo "| Workflow | Steps | Types | Composition | Status |"
  echo "|----------|-------|-------|-------------|--------|"
  echo -n "${DIR_RESULTS[$DIR]}"
  echo ""
  # Count workflows in this group
  COUNT=$(echo -n "${DIR_RESULTS[$DIR]}" | grep -c '^|')
  TOTAL_WORKFLOWS=$((TOTAL_WORKFLOWS + COUNT))
done

echo "---"
echo "Total: $TOTAL_WORKFLOWS workflow(s) found."
```

Display the output from the bash block above. This is the final output of the skill.

## Empty State (FR-005)

If Step 1 found no workflow files, display this message:

```
No workflows found.

Run `/wheel-create` to create your first workflow.
```

**Stop here** — there is nothing else to display.

## Rules

- This skill takes no arguments and is read-only.
- Invalid JSON files appear in the list with an error indicator — they do not cause the command to fail.
- Workflows missing required fields (name, steps) appear with descriptive error messages.
- Branch targets and context_from references are validated against known step IDs.
- The skill scans recursively — deeply nested directories (e.g., `workflows/a/b/c/`) are supported.
