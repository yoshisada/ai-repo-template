# Data Model: Wheel Team Primitives

## State File Schema Extension

The existing `.wheel/state_*.json` gains a new top-level `teams` key for tracking team metadata.

### teams object (added to state JSON root)

```json
{
  "teams": {
    "<step-id>": {
      "team_name": "string — Claude Code team name",
      "created_at": "ISO 8601 timestamp",
      "teammates": {
        "<agent-name>": {
          "task_id": "string — TaskCreate task ID",
          "status": "pending | running | completed | failed",
          "agent_id": "string — Claude Code agent ID",
          "state_file": "string — path to teammate's sub-workflow state file",
          "output_dir": "string — .wheel/outputs/team-{team-name}/{agent-name}/",
          "started_at": "ISO 8601 timestamp | null",
          "completed_at": "ISO 8601 timestamp | null",
          "assign": "object | null — the assignment payload for this teammate"
        }
      }
    }
  }
}
```

### Size constraint (NFR-003)

Per teammate entry: ~200 bytes. With 10 teammates: ~2KB per team. With 3 teams: ~6KB. Well under the 10KB limit. Full outputs are stored on disk in output directories, NOT in the state file.

## Workflow JSON Step Schemas

### team-create step

```json
{
  "id": "string (required)",
  "type": "team-create",
  "team_name": "string (optional — auto-generated if omitted)",
  "output": "string (optional — output file path)"
}
```

### teammate step (static)

```json
{
  "id": "string (required)",
  "type": "teammate",
  "team": "string (required — references team-create step ID)",
  "workflow": "string (required — sub-workflow name or path)",
  "context_from": ["string (step IDs, optional)"],
  "assign": {"object (optional — arbitrary JSON payload)"},
  "name": "string (optional — human-readable agent name)"
}
```

### teammate step (dynamic via loop_from)

```json
{
  "id": "string (required)",
  "type": "teammate",
  "team": "string (required — references team-create step ID)",
  "workflow": "string (required — sub-workflow to run)",
  "loop_from": "string (step ID whose output is a JSON array)",
  "max_agents": 5,
  "context_from": ["string (step IDs, optional)"],
  "name": "string (optional — base name, indexed as {name}-{index})"
}
```

### team-wait step

```json
{
  "id": "string (required)",
  "type": "team-wait",
  "team": "string (required — references team-create step ID)",
  "collect_to": "string (optional — directory to copy outputs into)",
  "output": "string (optional — summary output file path)"
}
```

### team-delete step

```json
{
  "id": "string (required)",
  "type": "team-delete",
  "team": "string (required — references team-create step ID)"
}
```

## Output Directory Layout

```
.wheel/outputs/
└── team-{team-name}/
    ├── {agent-name-0}/
    │   ├── context.json      # Context from parent steps (FR-029)
    │   ├── assignment.json   # Work assignment payload (FR-030)
    │   └── ...               # Sub-workflow outputs
    ├── {agent-name-1}/
    │   ├── context.json
    │   ├── assignment.json
    │   └── ...
    └── summary.json          # Written by team-wait (FR-018)
```

## team-wait Summary Schema (FR-018)

```json
{
  "team_name": "string",
  "total": 3,
  "completed": 2,
  "failed": 1,
  "teammates": [
    {
      "name": "agent-name-0",
      "status": "completed",
      "output_dir": ".wheel/outputs/team-{team-name}/agent-name-0/",
      "duration_seconds": 120
    },
    {
      "name": "agent-name-1",
      "status": "failed",
      "output_dir": ".wheel/outputs/team-{team-name}/agent-name-1/",
      "duration_seconds": 45
    }
  ]
}
```
