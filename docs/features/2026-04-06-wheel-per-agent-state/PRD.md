# Feature PRD: Wheel Per-Agent State Files

**Date**: 2026-04-06
**Status**: Draft

## Parent Product

[docs/PRD.md](../../PRD.md) — kiln Claude Code plugin. This feature extends the **plugin-wheel** workflow engine.

Builds on: [wheel-session-guard](../2026-04-05-wheel-session-guard/PRD.md) which added ownership fields to state.json.

## Feature Overview

Move wheel's workflow state from a single hardcoded `.wheel/state.json` to per-agent state files named `state_{session_id}_{agent_id}.json`. This enables multiple agents in the same session to each run their own workflow concurrently without interference.

## Problem / Motivation

Wheel currently uses a single `.wheel/state.json` file. This creates two problems:

1. **Only one workflow at a time** — if Agent A starts a workflow, Agent B cannot start its own. This makes wheel unusable in multi-agent contexts like pipelines where multiple agents need independent workflows.

2. **Ownership is an afterthought** — the session guard feature added `owner_session_id` and `owner_agent_id` fields, but they're stamped after creation via first-hook stamping. The skill (`/wheel-run`) doesn't know the agent_id at creation time, so it writes empty owner fields and hopes the first hook stamps them correctly.

The root cause: `/wheel-run` runs as a skill which has access to `session_id` but NOT `agent_id`. Only hook input JSON contains both. The state file needs to be created with ownership baked in from the start.

## Goals

- Multiple agents can each run their own independent workflow concurrently
- Ownership is encoded in the state filename, not in JSON fields stamped after the fact
- Two-phase creation: skill creates with session_id, first hook renames with agent_id
- No new infrastructure (no MCP servers, no activation scripts, no fake tool calls)

## Non-Goals

- Multi-agent collaboration on a single workflow (one workflow = one agent)
- Workflow handoff between agents
- Changes to workflow JSON schema — this is purely a runtime/state concern
- New directories or folder hierarchies — flat files in `.wheel/`
- MCP tools or activation scripts to pass workflow name to hooks

## Target Users

- **Pipeline operators** running multi-agent pipelines (e.g., `/build-prd`) where subagents need independent workflows
- **Developers** running a workflow in one agent while other agents do unrelated work in the same session

## Core User Stories

- As a **pipeline operator**, I want each agent in my pipeline to run its own wheel workflow so that a specifier agent, implementer agent, and QA agent can each follow different workflows concurrently.
- As a **developer**, I want to start a workflow and have subagents in the same session start their own workflows without blocking or corrupting mine.
- As a **developer**, I want `/wheel-status` to show all active workflows across all agents so I can see the full picture.
- As a **developer**, I want `/wheel-stop` to be able to stop any agent's workflow, not just my own.

## Functional Requirements

### State File Naming

FR-001: State files MUST be named `state_{session_id}.json` at creation (by the skill) and renamed to `state_{session_id}_{agent_id}.json` by the first hook event that has both identifiers. If `agent_id` is empty (main orchestrator), the file remains `state_{session_id}.json`.

FR-002: `/wheel-run` MUST pass the current `session_id` to `state_init`, which creates the file as `.wheel/state_{session_id}.json`. The skill does NOT set `agent_id`.

FR-003: The first hook event after state creation MUST detect the un-renamed `state_{session_id}.json`, extract `agent_id` from hook input, and rename it to `state_{session_id}_{agent_id}.json`. If `agent_id` is empty, no rename occurs.

### Hook State Resolution

FR-004: Every hook handler MUST construct its expected state filename from `session_id` and `agent_id` in the hook input JSON. It checks for `state_{session_id}_{agent_id}.json` first, then falls back to `state_{session_id}.json` (pre-rename). If neither exists, pass through with `{"decision": "approve"}`.

FR-005: Guard logic is replaced by filename-based ownership. If the hook's constructed state file exists, the hook is the owner and proceeds. No JSON field comparison needed.

### Concurrent Workflows

FR-006: Multiple `state_*.json` files MAY exist simultaneously in `.wheel/`. Each hook invocation MUST only read and write its own state file, never another agent's.

FR-007: `/wheel-run` MUST check for an existing `state_{session_id}*.json` file for the current session before creating a new one. If found, block with an error (one workflow per agent, but the skill only knows session_id at this point — the hook rename handles agent-level uniqueness).

### Skills (status/stop)

FR-008: `/wheel-status` MUST glob `state_*.json` in `.wheel/` and display all active workflows with their owner session/agent IDs.

FR-009: `/wheel-stop` MUST accept an optional identifier to target a specific workflow. With no argument, it stops all workflows (or the only one if just one exists). It archives completed state files to `.wheel/history/` as before.

### Engine and Kickstart

FR-010: `engine_kickstart` MUST use the session_id-only filename (`state_{session_id}.json`) since it runs inside the skill before any hook fires.

FR-011: `state_init` MUST accept `session_id` as a parameter and use it to construct the state filename. The `owner_session_id` field in the JSON is set at creation; `owner_agent_id` is set empty and populated on first hook rename.

## Absolute Musts

1. **Tech stack**: Bash 5.x, jq, existing wheel engine libs (state.sh, workflow.sh, dispatch.sh, engine.sh, context.sh, lock.sh)
2. **No new infrastructure**: No MCP servers, no activation scripts, no new dependencies
3. **Backward-compatible archive**: Completed state files archive to `.wheel/history/` with the same naming as today
4. **Flat files only**: All state files live directly in `.wheel/`, no subdirectories

## Tech Stack

Inherited from product — no additions or overrides:
- Bash 5.x (hook scripts, guard library)
- `jq` (JSON parsing for session_id/agent_id extraction)
- Existing wheel engine infrastructure (state.sh, dispatch.sh, engine.sh, context.sh, lock.sh, workflow.sh)
- `.wheel/state_*.json` (file-based JSON state)

## Impact on Existing Features

- **state.sh**: `state_init` signature changes to accept `session_id`, builds filename from it
- **guard.sh**: Simplified or removed — ownership is implicit in the filename
- **All 6 hooks**: Construct state filename from hook input instead of hardcoding `.wheel/state.json`. Add rename logic for first-hook detection.
- **engine.sh**: `engine_kickstart` and `engine_init` accept state filename or session_id
- **wheel-run skill**: Passes session_id to state_init, uses session_id-based filename for kickstart
- **wheel-status skill**: Globs `state_*.json` instead of reading single file
- **wheel-stop skill**: Globs `state_*.json`, supports targeting specific workflow
- **No workflow JSON schema changes**
- **No changes to dispatch.sh, workflow.sh, context.sh, lock.sh** (they receive state_file path as parameter)

## Success Metrics

1. Two or more agents can each run independent workflows concurrently with zero state corruption
2. `/wheel-status` correctly lists all active workflows across agents
3. `/wheel-stop` can stop any individual workflow or all workflows
4. Hook latency increase is imperceptible (<10ms over current guard)
5. All existing single-agent workflow tests still pass

## Risks / Unknowns

1. **Session ID availability in skills**: The skill needs access to session_id. This was confirmed to work in the current session (session_id was populated in state.json). If session_id is not available in skill context, the fallback is a generated UUID — unique but not correlatable.
2. **Race on rename**: Two hooks from different agents could both see `state_{session_id}.json` and try to rename simultaneously. Mitigation: the rename is atomic on POSIX (`mv`), and only the first `mv` succeeds — the second gets "file not found" and falls back to checking its own filename.
3. **Orphaned state files**: If an agent crashes without completing, its state file stays in `.wheel/`. Mitigation: `/wheel-stop` can clean up any file, and `/wheel-status` shows stale workflows.
4. **Main orchestrator (no agent_id)**: When the main agent runs a workflow, agent_id is empty. The file stays as `state_{session_id}.json`. If a subagent in the same session also starts a workflow, its file is `state_{session_id}_{agent_id}.json` — no collision.

## Assumptions

- Claude Code hook input JSON contains `session_id` at the top level (confirmed working)
- Claude Code hook input JSON contains `agent_id` at the top level for subagents (empty string for main orchestrator)
- `session_id` is accessible to skills via some mechanism (environment variable, or extractable from the conversation context)
- `mv` (rename) is atomic on the target filesystem (standard POSIX guarantee)

## Open Questions

1. How exactly does the skill access `session_id`? Is it an environment variable, or does it need to be extracted from another source?
2. Should orphaned state files be auto-cleaned after a timeout, or is manual `/wheel-stop` sufficient?
