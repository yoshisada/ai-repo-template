# Data Model: Wheel Workflow Composition

## Entities

### Workflow Step (type: "workflow")

A step definition within a workflow JSON file that invokes another workflow.

**Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Unique step identifier within the workflow |
| `type` | string | yes | Must be `"workflow"` |
| `workflow` | string | yes | Name of the child workflow (resolved to `workflows/<name>.json`) |
| `terminal` | boolean | no | If true, parent workflow completes when this step finishes |
| `next` | string | no | Step ID to jump to after completion (overrides linear advancement) |

**Prohibited fields** (from other step types): `context_from`, `command`, `instruction`, `output`, `condition`, `if_zero`, `if_nonzero`, `max_iterations`, `on_exhaustion`, `substep`, `agents`, `agent_instructions`, `message`.

### Child State File

A `.wheel/state_*.json` file created when a workflow step activates a child workflow.

**Additional field** (beyond standard state fields):
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `parent_workflow` | string | yes (for child states) | Absolute path to the parent state file |

**Standard fields inherited**: `workflow_name`, `workflow_version`, `workflow_file`, `status`, `cursor`, `owner_session_id`, `owner_agent_id`, `started_at`, `updated_at`, `steps[]`.

### State Transitions

**Parent workflow step lifecycle**:
```
pending → working (child activated) → done (child completed)
pending → working (child activated) → [stays working if child fails/stops]
```

**Child workflow lifecycle**:
```
Created (state_init with parent_workflow) → running → completed (archived to history/success/)
Created → running → stopped (archived to history/stopped/ — if parent stops)
```

### Relationships

```
Parent State File (state_*.json)
  └── steps[N] (type: "workflow", status: "working")
        └── Child State File (state_*.json)
              └── parent_workflow: "<parent state file path>"
```

- One parent workflow step → one child state file (1:1)
- One child state file → one parent state file (via `parent_workflow` field)
- Parent and child share `owner_session_id` and `owner_agent_id`
