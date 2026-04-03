---
title: "Create lobster — hook-based workflow engine plugin for Claude Code"
type: feature-request
severity: high
category: workflow
source: manual
github_issue: null
status: open
date: 2026-04-02
---

## Description

Create a new repo (`yoshisada/lobster`) and Claude Code plugin (`@yoshisada/lobster`) for a deterministic workflow runtime that orchestrates multi-agent pipelines using hooks and a state machine.

Core concept: hooks can't spawn agents or trigger tools, but they CAN gate execution (Stop, TeammateIdle), inject context (SubagentStart, additionalContext), and detect lifecycle events (SubagentStop). Combined with `session_id` and `agent_type` available on every hook input, this is enough to build a state machine that feeds the LLM one instruction at a time instead of front-loading the entire plan into context.

### Hook primitives used

| Hook | Role |
|---|---|
| `Stop` | Gate parent orchestrator — inject next step or allow stop when workflow done |
| `TeammateIdle` | Gate agents — inject agent-specific next task or allow idle when step done |
| `SubagentStart` | Inject previous step output as `additionalContext` into new agents |
| `SubagentStop` | Fan-in — mark agent done in state.json, check if all parallel agents finished, advance step |
| `SessionStart(resume)` | Reload state.json, resume from last completed step |

### Capabilities

- **Linear step sequencing**: Stop hook advances step cursor, injects exact next instruction
- **Parallel agent fan-out/fan-in**: Per-agent state tracking via `agent_type`, atomic completion checks via `mkdir` lock, `SubagentStop` as fan-in signal
- **Per-step context injection**: Each agent gets only the context it needs for its current task — no full plan in context
- **Approval gates**: TeammateIdle blocks until explicit approval
- **Session resume**: State persisted to disk, SessionStart hook reloads on reconnect
- **Context-loss prevention**: LLM never needs to hold full workflow in memory — state.json is the source of truth

### State file structure

```json
{
  "session_id": "abc123",
  "current_step": 2,
  "steps": [
    { "id": "specify", "status": "done", "output": "specs/feature/spec.md" },
    { "id": "implement", "status": "active",
      "parallel_agents": {
        "implementer-a": { "agent_id": "uuid1", "status": "done" },
        "implementer-b": { "agent_id": "uuid2", "status": "working" },
        "qa-engineer": { "agent_id": "uuid3", "status": "idle" }
      }
    },
    { "id": "audit", "status": "pending" }
  ]
}
```

### Relationship to kiln

Kiln becomes a **consumer** of lobster. `/build-prd` would define its pipeline as a workflow and delegate orchestration to the engine. Kiln-specific guardrails (4-gate enforcement, build checks, QA hooks) stay in kiln. Lobster owns the general-purpose runtime.

## Impact

Currently `/build-prd` embeds orchestration logic in a giant skill prompt — the LLM decides step ordering, agent sequencing, and fan-in. This is the "LLM as unreliable router" anti-pattern. A deterministic runtime would make pipelines reproducible, resumable, and less prone to context-loss failures on long runs.

## Suggested Fix

1. Create repo `yoshisada/lobster` with Claude Code plugin structure
2. Implement `engine.sh` — shell script that reads state.json, handles step advancement, fan-in, context injection
3. Wire hooks in `hooks.json` (Stop, SubagentStop, SubagentStart, TeammateIdle, SessionStart)
4. Start with a single hardcoded linear workflow as POC, then add parallel agent support
5. Publish as `@yoshisada/lobster` on npm
6. Update kiln's `/build-prd` to consume lobster for orchestration
