# Quickstart: Wheel Team Primitives

## Static Fan-Out Example

A workflow that creates a team, spawns 3 teammates to build pages in parallel, waits for all to finish, then cleans up:

```json
{
  "name": "build-pages-parallel",
  "version": "1.0.0",
  "steps": [
    {
      "id": "create-team",
      "type": "team-create",
      "team_name": "page-builders"
    },
    {
      "id": "build-home",
      "type": "teammate",
      "team": "create-team",
      "workflow": "build-page",
      "assign": {"page": "home", "index": 0},
      "name": "builder-home"
    },
    {
      "id": "build-about",
      "type": "teammate",
      "team": "create-team",
      "workflow": "build-page",
      "assign": {"page": "about", "index": 1},
      "name": "builder-about"
    },
    {
      "id": "build-contact",
      "type": "teammate",
      "team": "create-team",
      "workflow": "build-page",
      "assign": {"page": "contact", "index": 2},
      "name": "builder-contact"
    },
    {
      "id": "wait-all",
      "type": "team-wait",
      "team": "create-team",
      "collect_to": ".wheel/outputs/all-pages/",
      "output": ".wheel/outputs/build-pages-summary.json"
    },
    {
      "id": "cleanup",
      "type": "team-delete",
      "team": "create-team"
    }
  ]
}
```

## Dynamic Fan-Out Example

A workflow where step 1 discovers pages, then a single teammate step spawns one agent per page:

```json
{
  "name": "build-all-pages-dynamic",
  "version": "1.0.0",
  "steps": [
    {
      "id": "discover-pages",
      "type": "command",
      "command": "jq -c '[.pages[]]' pages-config.json",
      "output": ".wheel/outputs/discover-pages.json"
    },
    {
      "id": "create-team",
      "type": "team-create"
    },
    {
      "id": "spawn-builders",
      "type": "teammate",
      "team": "create-team",
      "workflow": "build-page",
      "loop_from": "discover-pages",
      "max_agents": 5,
      "name": "builder"
    },
    {
      "id": "wait-all",
      "type": "team-wait",
      "team": "create-team",
      "output": ".wheel/outputs/build-summary.json"
    },
    {
      "id": "cleanup",
      "type": "team-delete",
      "team": "create-team",
      "terminal": true
    }
  ]
}
```

## Context Passing Example

A teammate that receives context from a previous research step:

```json
{
  "id": "implement-feature",
  "type": "teammate",
  "team": "create-team",
  "workflow": "implement-and-test",
  "context_from": ["research-step", "plan-step"],
  "assign": {"feature": "auth", "files": ["src/auth.ts", "src/middleware.ts"]},
  "name": "implementer-auth"
}
```

The sub-workflow can reference the context via synthetic step IDs:

```json
{
  "id": "read-context",
  "type": "agent",
  "instruction": "Read the context and assignment files to understand your task.",
  "context_from": ["_context", "_assignment"],
  "output": ".wheel/outputs/team-{team-name}/implementer-auth/understood.md"
}
```
