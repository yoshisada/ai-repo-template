# Quickstart: Wheel Workflow Composition

## Creating a Workflow with a Workflow Step

1. Create a child workflow (or use an existing one) at `workflows/child-workflow.json`:
```json
{
  "name": "child-workflow",
  "version": "1.0.0",
  "steps": [
    {"id": "step-1", "type": "command", "command": "echo 'child step 1'"},
    {"id": "step-2", "type": "command", "command": "echo 'child step 2'", "terminal": true}
  ]
}
```

2. Create a parent workflow at `workflows/parent-workflow.json` that references it:
```json
{
  "name": "parent-workflow",
  "version": "1.0.0",
  "steps": [
    {"id": "setup", "type": "command", "command": "echo 'parent setup'"},
    {"id": "run-child", "type": "workflow", "workflow": "child-workflow"},
    {"id": "teardown", "type": "command", "command": "echo 'parent teardown'", "terminal": true}
  ]
}
```

3. Run the parent: `/wheel-run parent-workflow`

4. The engine will:
   - Execute `setup` (command step)
   - Reach `run-child` → activate `child-workflow` as a child
   - Execute `child-workflow`'s steps (step-1, step-2)
   - When child completes, parent's `run-child` step is marked done
   - Execute `teardown` (command step)
   - Parent workflow completes

## Validation Errors

**Missing workflow**: If `child-workflow.json` doesn't exist:
```
ERROR: workflow step 'run-child' references missing workflow: child-workflow
```

**Circular reference**: If A references B and B references A:
```
ERROR: circular workflow reference detected: A -> B -> A
```

**Nesting too deep** (>5 levels):
```
ERROR: workflow nesting depth exceeds maximum (5)
```
