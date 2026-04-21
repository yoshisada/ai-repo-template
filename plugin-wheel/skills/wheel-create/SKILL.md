---
name: wheel-create
description: Generate a wheel workflow JSON file from a natural language description or by reverse-engineering an existing file. Usage: /wheel:wheel-create <description> or /wheel:wheel-create from:<filepath>
---

# Wheel Create — Generate Workflow JSON

Create a new wheel workflow JSON file from either a natural language description or by reverse-engineering an existing file (SKILL.md, shell script, etc.).

**Two modes**:
- **Description Mode**: `/wheel:wheel-create gather git stats, analyze repo structure, write a health report`
- **File Mode**: `/wheel:wheel-create from:plugin-wheel/skills/wheel-status/SKILL.md`

## User Input

```text
$ARGUMENTS
```

## Step 1 — Input Parsing

<!-- FR-001, FR-002, FR-003 -->

Determine the mode from `$ARGUMENTS`:

1. **If `$ARGUMENTS` is empty**: Prompt the user — "Please provide either a workflow description or a file path with the `from:` prefix. Examples: `/wheel:wheel-create gather git stats and write a report` or `/wheel:wheel-create from:path/to/script.sh`". **Stop here.**

2. **If `$ARGUMENTS` starts with `from:`**: This is **File Mode**. Extract the file path (everything after `from:`). Validate the file exists:

```bash
FILE_PATH="${ARGUMENTS#from:}"
FILE_PATH="${FILE_PATH## }"
if [[ ! -f "$FILE_PATH" ]]; then
  echo "ERROR: File not found: $FILE_PATH"
  echo "Please check the path and try again."
  exit 1
fi
echo "File Mode: reading $FILE_PATH"
```

If the file does not exist, report the error and **stop here**.

3. **Otherwise**: This is **Description Mode**. The entire `$ARGUMENTS` string is the natural language description.

## Step 2 — Name Resolution

<!-- FR-004, FR-005 -->

Derive a kebab-case workflow name:

- **Description Mode**: Extract 2-4 key action/noun words from the description. Form a kebab-case slug (e.g., "gather git stats, analyze repo structure, write a health report" becomes `git-stats-health-report`).
- **File Mode**: Use the source filename stem or parent directory name (e.g., `status/SKILL.md` becomes `status`).

Check for name collisions and append a numeric suffix if needed:

```bash
mkdir -p workflows
NAME="<derived-kebab-case-name>"
OUTFILE="workflows/${NAME}.json"
if [[ -f "$OUTFILE" ]]; then
  SUFFIX=2
  while [[ -f "workflows/${NAME}-${SUFFIX}.json" ]]; do
    SUFFIX=$((SUFFIX + 1))
  done
  NAME="${NAME}-${SUFFIX}"
  OUTFILE="workflows/${NAME}.json"
fi
echo "Workflow name: $NAME"
echo "Output file: $OUTFILE"
```

Never overwrite an existing workflow file.

## Step 3 — Step Decomposition (Description Mode)

<!-- FR-006, FR-007, FR-008, FR-009, FR-025 -->

**Only execute this step if in Description Mode. If in File Mode, skip to Step 4.**

Parse the natural language description into discrete workflow steps. For each identified action:

### Step Type Classification

<!-- FR-007 -->

Classify each step using these heuristics:

| Pattern in Description | Step Type | Rationale |
|---|---|---|
| Shell commands, file checks, data gathering, listing, counting, running scripts | `command` | Deterministic shell work |
| LLM reasoning, writing, analysis, summarizing, reviewing, explaining | `agent` | Requires LLM intelligence |
| Conditional logic ("if X then Y else Z", "check whether", "decide") | `branch` | Condition-based routing |
| Repeated execution ("repeat until", "for each", "keep trying", "retry") | `loop` | Iterative processing |

When in doubt, prefer `command` for concrete actions and `agent` for open-ended reasoning.

### Dependency Analysis

<!-- FR-008 -->

Determine `context_from` arrays based on data flow:
- If step B needs output from step A, add A's ID to B's `context_from`
- If steps are independent, leave `context_from` empty
- Follow the natural ordering from the description

### Output Path Conventions

<!-- FR-009 -->

Assign output paths following wheel conventions:

| Step Type | Output Path Pattern |
|---|---|
| `command` | `.wheel/outputs/<step-id>.txt` |
| `agent` (producing a report) | `reports/<descriptive-name>.md` |
| `agent` (other output) | `.wheel/outputs/<step-id>.md` |
| `loop` | `.wheel/outputs/<step-id>.txt` |

### Step Limit

<!-- FR-025 -->

Cap the workflow at a maximum of **20 steps**. If the description implies more than 20 discrete actions, consolidate related actions into broader steps. Prefer fewer, more capable steps over many granular ones.

After decomposition, proceed to **Step 5 — JSON Assembly**.

## Step 4 — Step Decomposition (File Mode)

<!-- FR-012, FR-013, FR-014, FR-015, FR-016 -->

**Only execute this step if in File Mode. If in Description Mode, skip (already handled in Step 3).**

Read the source file and analyze its structure to identify discrete workflow steps.

### SKILL.md Files

<!-- FR-013 -->

For files ending in `.md` or named `SKILL.md`:
- **Headings** (`## Step N`) define step boundaries
- **Code blocks** (` ```bash `) become `command` steps — extract the shell command
- **Prose/reasoning sections** between code blocks become `agent` steps — use the prose as the instruction
- Preserve the original ordering of sections

### Shell Scripts

<!-- FR-014 -->

For `.sh` files or files with a `#!/bin/bash` shebang:
- Each distinct command or pipeline becomes a `command` step
- Complex logic blocks (functions with conditionals, long pipelines with processing) that would benefit from LLM reasoning become `agent` steps
- Preserve command ordering

### Other Files

<!-- FR-015 -->

For JSON, YAML, Markdown, or other structured files:
- Use best-effort heuristic parsing
- Identify logical sections or blocks
- Map each to the most appropriate step type
- When uncertain, wrap as an `agent` step with instructions describing the section's intent

### Preservation Rule

<!-- FR-016 -->

Preserve the intent and ordering of the source file. Do NOT reorder or combine steps unless necessary for workflow validity. The generated workflow should replicate what the source file does, step by step.

Apply the same **Step Type Classification**, **Output Path Conventions**, and **Step Limit** rules from Step 3.

After decomposition, proceed to **Step 5 — JSON Assembly**.

## Step 5 — JSON Assembly

<!-- FR-010, FR-011, FR-021, FR-022, FR-023, FR-024 -->

Assemble the workflow JSON object with the following structure:

```json
{
  "name": "<resolved-workflow-name>",
  "version": "1.0.0",
  "steps": [ ... ]
}
```

### Step Schemas

**Command step** (FR-021):
```json
{
  "id": "<unique-kebab-case-id>",
  "type": "command",
  "command": "<shell-command>",
  "output": ".wheel/outputs/<id>.txt"
}
```
Optional fields: `context_from` (string array of step IDs), `next` (step ID), `terminal` (boolean).

**Agent step** (FR-022):
```json
{
  "id": "<unique-kebab-case-id>",
  "type": "agent",
  "instruction": "<what the agent should do>",
  "output": "reports/<name>.md"
}
```
Optional fields: `context_from` (string array of step IDs), `next` (step ID), `terminal` (boolean).

**Branch step** (FR-023):
```json
{
  "id": "<unique-kebab-case-id>",
  "type": "branch",
  "condition": "<shell-command-returning-exit-code>",
  "if_zero": "<step-id-on-exit-0>",
  "if_nonzero": "<step-id-on-nonzero-exit>"
}
```
Optional fields: `context_from` (string array of step IDs).

**Loop step** (FR-024):
```json
{
  "id": "<unique-kebab-case-id>",
  "type": "loop",
  "condition": "<shell-command-exits-0-to-stop>",
  "max_iterations": 10,
  "substep": {
    "type": "command",
    "command": "<shell-command-for-each-iteration>"
  }
}
```
Optional fields: `output` (file path), `context_from` (string array of step IDs), `on_exhaustion` ("fail" or "continue").

### Terminal Step

<!-- FR-010 -->

Mark the **last step** in the linear flow (or the final convergence point in branching workflows) with `"terminal": true`. Branch endpoints that are final should each be marked terminal.

### Envelope Fields

<!-- FR-011 -->

- `name`: The resolved workflow name from Step 2
- `version`: Always `"1.0.0"` for newly generated workflows

## Step 6 — Validation

<!-- FR-017, FR-018 -->

Before writing the file, validate the generated JSON against the same checks as `workflow_load`:

```bash
# Validate using jq
WORKFLOW_JSON='<the-generated-json>'

# 1. Valid JSON
echo "$WORKFLOW_JSON" | jq empty 2>/dev/null || { echo "ERROR: Invalid JSON"; exit 1; }

# 2. name field exists and is non-empty
NAME=$(echo "$WORKFLOW_JSON" | jq -r '.name // empty')
[[ -n "$NAME" ]] || { echo "ERROR: Missing or empty 'name' field"; exit 1; }

# 3. steps is non-empty array
STEP_COUNT=$(echo "$WORKFLOW_JSON" | jq '.steps | length')
[[ "$STEP_COUNT" -gt 0 ]] || { echo "ERROR: 'steps' array is empty"; exit 1; }

# 4. Every step has id and type
MISSING=$(echo "$WORKFLOW_JSON" | jq '[.steps[] | select(.id == null or .type == null)] | length')
[[ "$MISSING" -eq 0 ]] || { echo "ERROR: $MISSING step(s) missing 'id' or 'type'"; exit 1; }

# 5. Unique step IDs
TOTAL_IDS=$(echo "$WORKFLOW_JSON" | jq '[.steps[].id] | length')
UNIQUE_IDS=$(echo "$WORKFLOW_JSON" | jq '[.steps[].id] | unique | length')
[[ "$TOTAL_IDS" -eq "$UNIQUE_IDS" ]] || { echo "ERROR: Duplicate step IDs found"; exit 1; }

# 6. Branch targets reference valid step IDs
ALL_IDS=$(echo "$WORKFLOW_JSON" | jq -r '[.steps[].id] | join(",")')
echo "$WORKFLOW_JSON" | jq -r '.steps[] | select(.type=="branch") | .if_zero, .if_nonzero' | while read -r TARGET; do
  echo ",$ALL_IDS," | grep -q ",$TARGET," || { echo "ERROR: Branch target '$TARGET' is not a valid step ID"; exit 1; }
done

# 7. context_from references valid step IDs
echo "$WORKFLOW_JSON" | jq -r '.steps[] | select(.context_from != null) | .context_from[]' | while read -r REF; do
  echo ",$ALL_IDS," | grep -q ",$REF," || { echo "ERROR: context_from '$REF' is not a valid step ID"; exit 1; }
done

# 8. next references valid step IDs
echo "$WORKFLOW_JSON" | jq -r '.steps[] | select(.next != null) | .next' | while read -r REF; do
  echo ",$ALL_IDS," | grep -q ",$REF," || { echo "ERROR: next '$REF' is not a valid step ID"; exit 1; }
done

echo "Validation passed ($STEP_COUNT steps)"
```

### Self-Correction

<!-- FR-018 -->

If validation fails, attempt to fix the issue:
- **Duplicate IDs**: Append a numeric suffix to duplicates
- **Invalid references**: Remove or correct `context_from`, `next`, or branch target references
- **Missing fields**: Add required fields with sensible defaults

Re-validate after correction. If self-correction fails after one attempt, report the errors and **do not write the file**.

## Step 7 — Write Output

<!-- FR-019, FR-020 -->

Write the validated JSON to the output file:

```bash
mkdir -p workflows
echo "$WORKFLOW_JSON" | jq '.' > "$OUTFILE"
echo "Workflow written to: $OUTFILE"
```

The file MUST use 2-space JSON indentation (jq default).

### Report Summary

<!-- FR-020 -->

After writing, report:

1. **File path**: The full path to the created file
2. **Workflow name**: The resolved name
3. **Step count**: Total number of steps
4. **Step summary**: For each step, show: `id` | `type` | one-line description
5. **Run command**: `/wheel:wheel-run <name>`

Example output:

```
Created: workflows/git-stats-health-report.json
Name: git-stats-health-report
Steps: 3

  1. gather-stats    | command | Gather git statistics
  2. analyze-repo    | command | Analyze repository structure
  3. write-report    | agent   | Write health report from gathered data

Run with: /wheel:wheel-run git-stats-health-report
```

## Agent Self-Service

<!-- FR-005, FR-025 -->

When invoked by an agent (not a human), the skill should:
- Never prompt for clarification if the description is specific enough to decompose into steps
- Handle name collisions silently via numeric suffix (no interactive confirmation)
- Produce machine-parseable output (the summary format above is sufficient)
- Cap at 20 steps without asking for confirmation — just consolidate

The skill auto-detects agent context: if the description is clear and actionable, proceed without questions. Only ask for clarification when the description is genuinely too vague to decompose (e.g., "do something", "help me").

## Rules

- **Never overwrite**: If `workflows/<name>.json` exists, append a numeric suffix (`-2`, `-3`, ...). Never overwrite an existing file.
- **Max 20 steps**: Cap generated workflows at 20 steps. Consolidate if the input implies more.
- **Validate before writing**: Always run the full validation from Step 6 before writing. Never write invalid JSON.
- **No auto-execution**: The skill creates the workflow file but does NOT run it. The user must run `/wheel:wheel-run <name>` separately.
- **Create workflows/ directory**: If the `workflows/` directory doesn't exist, create it before writing.
- **Clarify when vague**: If the description is too vague to decompose into steps (e.g., "do something"), ask a clarifying question before proceeding.
- **Complex logic as agent steps**: If a section of the source file has deeply nested conditional logic that doesn't map cleanly to the 4 step types, wrap it as an `agent` step with the original intent in the instruction field.
- **Loop conditions**: Loop `condition` is a shell command that exits 0 when the loop should STOP. If the condition semantics can't be reliably inferred from natural language, generate a reasonable default and note it in the output summary for user review.
