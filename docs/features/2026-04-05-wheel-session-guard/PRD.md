# Feature PRD: Wheel Session Guard

**Date**: 2026-04-05
**Status**: Draft

## Background

Wheel workflows run via hooks that intercept every Claude Code event in the session. When a workflow is active, all hooks (stop, post-tool-use, subagent-start, subagent-stop, teammate-idle) fire for every agent in the session — including subagents spawned by the pipeline that have nothing to do with the workflow. This means a `/build-prd` pipeline running alongside a wheel workflow would have multiple agents competing to advance the workflow state machine.

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [Wheel needs session/agent detection so only one agent runs a workflow](.kiln/issues/2026-04-04-wheel-session-agent-detection.md) | — | improvement | high |

## Problem Statement

When wheel hooks fire on events from subagents that didn't start the workflow, the engine may execute command steps twice, inject conflicting agent instructions, or corrupt branch decisions via race conditions. This makes wheel workflows unsafe to run inside any multi-agent context (pipelines, parallel agents, background agents). The wheel engine has no concept of "ownership" — it blindly processes every event as if it came from the workflow orchestrator.

## Goals

- Only the agent that started the workflow can advance it — one workflow per agent
- All other agents pass through hooks transparently (no blocking, no state changes)
- Ownership is recorded at workflow start and checked on every hook invocation

## Non-Goals

- Multi-agent workflow orchestration (one workflow driven by multiple agents)
- Session handoff (transferring workflow ownership between agents)
- Changes to workflow JSON schema — ownership is a runtime concern, not a workflow definition concern
- Backwards compatibility with old state.json files — all active workflows will have the guard

## Requirements

### Functional Requirements

FR-001: `state_init` MUST capture `session_id` and `agent_id` (if present) from the hook input JSON and store them in `.wheel/state.json` as `owner_session_id` and `owner_agent_id`. (from: wheel-session-agent-detection.md)

FR-002: Every hook handler (stop.sh, post-tool-use.sh, subagent-start.sh, subagent-stop.sh, teammate-idle.sh, session-start.sh) MUST call a shared guard function before processing. The guard reads `session_id` and `agent_id` from the hook input and compares against the owner fields in state.json. If they don't match, return `{"decision": "approve"}` immediately without touching state. (from: wheel-session-agent-detection.md)

FR-003: The guard MUST match on `session_id` first. If `owner_agent_id` is also set, it MUST additionally match `agent_id`. Events from the same session but a different agent MUST pass through. (from: wheel-session-agent-detection.md)

FR-004: `/wheel-run` MUST capture the session/agent context at workflow start. Since skills don't receive hook input, the first hook event after state creation MUST stamp the owner fields if they're not yet set. (from: wheel-session-agent-detection.md)

FR-005: `/wheel-status` and `/wheel-stop` MUST work regardless of ownership — any agent can check status or stop a workflow. (from: wheel-session-agent-detection.md)

### Non-Functional Requirements

NFR-001: The guard check MUST add less than 10ms per hook invocation — a single `jq` read + compare.

NFR-002: The guard logic MUST live in a shared `lib/guard.sh` function to avoid duplicating across 6 hook scripts.

## User Stories

- As a **pipeline operator**, I want to run a wheel workflow inside a `/build-prd` pipeline without subagents corrupting the workflow state, so that wheel can be used for structured pipeline steps.
- As a **developer**, I want to start a workflow in one terminal and have subagents in the same session not interfere, so that background agents don't accidentally advance my workflow.

## Success Criteria

1. A wheel workflow started by agent X is unaffected by hook events from agent Y
2. A wheel workflow started in session A is unaffected by events from session B
3. `/wheel-status` and `/wheel-stop` work from any session
4. Hook latency increase is imperceptible (<10ms)

## Tech Stack

- Bash 5.x (hook scripts, guard library)
- `jq` (JSON parsing for session_id/agent_id extraction and comparison)
- Existing wheel engine infrastructure (state.sh, dispatch.sh, engine.sh)

## Risks & Open Questions

1. **First-hook stamping**: Since `/wheel-run` runs as a skill (no hook input), the owner fields get stamped by the first hook event after state creation. There's a small window where another agent could stamp first. Mitigation: the skill creates state.json, so the first hook from that same agent should fire next.
2. **Is `session_id` stable across reconnects?** If a user disconnects and reconnects, the session_id may change, orphaning the workflow. `/wheel-stop` is exempt from the guard so the user can always kill it.
