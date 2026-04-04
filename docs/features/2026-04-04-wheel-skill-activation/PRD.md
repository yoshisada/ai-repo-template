# Feature PRD: Wheel Skill-Based Activation

**Date**: 2026-04-04
**Status**: Draft
**Parent PRD**: [docs/features/2026-04-03-wheel/PRD.md](../2026-04-03-wheel/PRD.md)

## Background

Wheel's hook handlers currently auto-discover workflow JSON files in `workflows/` and activate on every Claude Code session. This means any project with wheel installed immediately has its Stop hook intercepting the session — there is no way to use Claude Code normally alongside wheel. Workflows should only run when the user explicitly triggers them via a skill command.

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [Wheel workflows should activate via skill, not auto-fire on every session](.kiln/issues/2026-04-04-wheel-skill-activation.md) | — | improvement | high |

## Problem Statement

Wheel is unusable in practice because it hijacks every Claude Code session in any project where it's installed. A user who has wheel set up but wants to do normal coding work — ask questions, edit files, run commands — gets blocked by the Stop hook injecting workflow instructions. There is no on/off switch.

The fix is to gate hook activation behind an explicit start command. Hooks check for `.wheel/state.json` — if it doesn't exist, they pass through silently. A skill creates state.json to start the workflow; another skill removes it to stop.

## Goals

- Workflows only activate when explicitly started via `/wheel-run`
- Users can stop a running workflow mid-execution via `/wheel-stop`
- Users can check workflow progress via `/wheel-status`
- Hooks pass through silently (no latency, no side effects) when no workflow is active
- Existing hook logic is unchanged — only the guard clause at the top of each hook changes

## Non-Goals

- **Not changing workflow definition format** — JSON workflows stay as-is
- **Not adding new step types** — this is purely activation/deactivation
- **Not adding a workflow registry or catalog** — the skill takes a file path argument

## Requirements

### Functional Requirements

- **FR-001** (from: wheel-skill-activation.md): Create `/wheel-run <name>` skill that reads `workflows/<name>.json`, validates it, creates `.wheel/state.json`, and outputs the first step instruction so hooks can take over
- **FR-002** (from: wheel-skill-activation.md): Create `/wheel-stop` skill that removes `.wheel/state.json`, making all hooks dormant. Optionally archive the completed/aborted workflow log to `.wheel/history/`
- **FR-003** (from: wheel-skill-activation.md): Create `/wheel-status` skill that reads `.wheel/state.json` and prints: workflow name, current step (index/total), step status, last command log entry, and elapsed time
- **FR-004** (from: wheel-skill-activation.md): Update every hook's guard clause to check `[[ ! -f ".wheel/state.json" ]]` instead of auto-discovering workflow files. If state.json doesn't exist, output `{"decision": "allow"}` and exit immediately
- **FR-005** (from: wheel-skill-activation.md): Remove workflow auto-discovery logic from `stop.sh` (lines 24-33 that scan `workflows/` for JSON files)
- **FR-006** (from: wheel-skill-activation.md): `/wheel-run` must validate the workflow JSON before creating state.json — check that all step IDs are unique, required fields exist per step type, and `context_from` references point to valid step IDs
- **FR-007** (from: wheel-skill-activation.md): `/wheel-run` must refuse to start if `.wheel/state.json` already exists (a workflow is already running). Suggest `/wheel-stop` first or `/wheel-status` to check progress

### Non-Functional Requirements

- **NFR-001**: Hook guard clause check must add < 5ms latency (single file existence check)
- **NFR-002**: Skills must work with the existing plugin structure — `plugin-wheel/skills/<name>/SKILL.md`
- **NFR-003**: Backwards compatible — existing workflows and state.json format unchanged

## User Stories

1. **As a developer**, I want to start a workflow only when I choose to, so wheel doesn't interfere with normal Claude Code usage.
2. **As a developer**, I want to stop a running workflow if I need to do something else, without losing the workflow definition.
3. **As a developer**, I want to check workflow progress without reading raw JSON, so I know which step is active and what's been done.

## Success Criteria

- Claude Code session in a wheel-installed project starts normally (no hook interception) when no workflow is active
- `/wheel-run example` creates state.json and the workflow proceeds through all steps via hook injection
- `/wheel-stop` immediately deactivates hooks — next Stop event passes through
- `/wheel-status` accurately reports current step and progress
- Hook latency is unmeasurable (< 5ms) when no workflow is active

## Tech Stack

- Markdown (SKILL.md skill definitions)
- Bash (hook guard clauses, inline shell in skills)
- jq (state.json reading in /wheel-status)
- Existing wheel plugin infrastructure

## Risks & Open Questions

1. **Skill discovery**: Do skills in `plugin-wheel/skills/` auto-register as `/wheel-run` etc., or do they need explicit naming in plugin.json?
2. **State.json ownership**: If `/wheel-run` creates state.json, does `engine_init()` in the hooks still need to call `state_init()`? Or does the skill handle all initialization and hooks only read?
3. **Concurrent workflows**: Should `/wheel-run` support running multiple workflows (each with its own state file), or is single-workflow-per-session sufficient for v1?
