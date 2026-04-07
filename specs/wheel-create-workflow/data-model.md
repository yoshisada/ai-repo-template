# Data Model: Wheel Create Workflow

**Date**: 2026-04-06

## Workflow JSON Schema

The generated workflow file follows this schema (derived from `workflow_load` validation and existing workflow files):

```json
{
  "name": "<kebab-case-string>",
  "version": "1.0.0",
  "steps": [
    // One or more step objects
  ]
}
```

## Step Types

### Command Step

```json
{
  "id": "<unique-kebab-case-id>",
  "type": "command",
  "command": "<shell-command-string>",
  "output": "<output-file-path>"
}
```

Optional fields: `context_from` (string array of step IDs), `next` (step ID string), `terminal` (boolean).

### Agent Step

```json
{
  "id": "<unique-kebab-case-id>",
  "type": "agent",
  "instruction": "<what-the-agent-should-do>",
  "output": "<output-file-path>"
}
```

Optional fields: `context_from` (string array of step IDs), `next` (step ID string), `terminal` (boolean).

### Branch Step

```json
{
  "id": "<unique-kebab-case-id>",
  "type": "branch",
  "condition": "<shell-command-that-returns-exit-code>",
  "if_zero": "<step-id-when-exit-0>",
  "if_nonzero": "<step-id-when-exit-nonzero>"
}
```

Optional fields: `context_from` (string array of step IDs).

### Loop Step

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

Optional fields: `output` (string), `context_from` (string array of step IDs), `on_exhaustion` ("fail" or "continue").

## Output Path Conventions

| Step Type | Output Path Pattern |
|-----------|-------------------|
| command | `.wheel/outputs/<step-id>.txt` |
| agent (report) | `reports/<descriptive-name>.md` |
| agent (other) | `.wheel/outputs/<step-id>.md` |
| loop | `.wheel/outputs/<step-id>.txt` |

## Validation Rules (from workflow_load)

1. File must be valid JSON
2. Must have `name` (non-empty string)
3. Must have `steps` (non-empty array)
4. Every step must have `id` (string) and `type` (string)
5. All step IDs must be unique
6. Branch `if_zero` and `if_nonzero` must reference valid step IDs
7. All `next` fields must reference valid step IDs
8. All `context_from` entries must reference valid step IDs

## Entity Relationships

```
Workflow 1──* Step
Step *──* Step (via context_from references)
Step 1──? Step (via next reference)
Branch Step 1──2 Step (via if_zero, if_nonzero)
Loop Step 1──1 Substep
```
