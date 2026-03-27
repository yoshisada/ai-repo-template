# Ruflo Workflow Pipeline

This directory contains a ruflo (claude-flow) workflow definition that replicates the speckit.run pipeline.

## Files

- `speckit-pipeline.json` — The full pipeline definition with agents, tasks, dependencies, and claudePrompts

## How It Works

The workflow defines 8 agents and 16 tasks in a dependency chain:

```
specify → plan → research → tasks → commit
  → implement-phase-1 → audit-phase-1
  → implement-phase-2 → audit-phase-2
  → implement-phase-3 → audit-phase-3
  → implement-phase-4 → audit-phase-4
  → final-audit → smoke-test → create-pr
```

Each task has:
- `claudePrompt` — exact instructions including which files to read and what to produce
- `depends` — dependency chain ensuring correct ordering
- `outputs` — declared expected files and extracted values

## Running

```bash
# Via ruflo CLI
npx claude-flow@alpha automation run-workflow workflows/speckit-pipeline.json \
  --claude \
  --non-interactive \
  --variables '{"feature_description": "your feature here", "feature_name": "your-feature"}' \
  --max-concurrency 3

# Via MCP tool
mcp__claude-flow__workflow_run({
  file: "workflows/speckit-pipeline.json",
  options: { parallel: false, maxAgents: 8, timeout: 600 }
})
```

## Comparison to speckit.run

| Aspect | speckit.run (skill) | This workflow (ruflo) |
|--------|--------------------|-----------------------|
| Step definitions | Embedded in markdown prompts | Declarative JSON with typed fields |
| Orchestration | Sequential subagents via Agent tool | Dependency DAG with ruflo scheduler |
| I/O control | In natural language prompts | `claudePrompt` + `outputs` schema |
| Parallelism | None (sequential only) | Automatic for independent tasks |
| State | Git filesystem only | Git + ruflo memory + stream chaining |
| Resume | Manual (no checkpoint) | `startFromStep` parameter |
