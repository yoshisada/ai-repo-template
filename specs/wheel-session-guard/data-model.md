# Data Model: Wheel Session Guard

## Entities

### Owner Context (in state.json)

Two new top-level fields added to the existing `.wheel/state.json` schema:

| Field | Type | Description | Set By |
|-------|------|-------------|--------|
| `owner_session_id` | string | Session ID of the agent that owns this workflow | First hook event (guard_check stamps when empty) |
| `owner_agent_id` | string | Agent ID of the agent that owns this workflow (empty for main orchestrator) | First hook event (guard_check stamps when empty) |

**Initial value**: Both fields are initialized to `""` (empty string) by `state_init`.

**Lifecycle**: Set once on first hook event, never changed until workflow completes or is stopped.

### Extended state.json Schema

```json
{
  "workflow_name": "string",
  "workflow_version": "string",
  "workflow_file": "string",
  "status": "running|completed|failed",
  "cursor": 0,
  "started_at": "ISO-8601",
  "updated_at": "ISO-8601",
  "owner_session_id": "",
  "owner_agent_id": "",
  "steps": [...]
}
```

### Hook Input Context (read-only)

Fields extracted from the hook input JSON (provided by Claude Code, not stored):

| Field | Type | Presence | Description |
|-------|------|----------|-------------|
| `session_id` | string | Always present for identifiable events | Session that triggered this hook event |
| `agent_id` | string | Present for subagents/teammates only | Agent that triggered this hook event |

## State Transitions

```
state_init creates state.json
  → owner_session_id = ""
  → owner_agent_id = ""

First hook event fires (guard_check)
  → owner_session_id = hook_input.session_id
  → owner_agent_id = hook_input.agent_id (or "" if absent)

Subsequent hook events (guard_check)
  → ownership fields unchanged
  → compare hook_input vs owner fields → allow or pass-through
```

## Validation Rules

- `owner_session_id` is stamped exactly once (when transitioning from empty to non-empty)
- `owner_agent_id` is stamped exactly once (when `owner_session_id` is being stamped)
- Guard never overwrites non-empty ownership fields
- Missing `session_id` in hook input always results in pass-through
