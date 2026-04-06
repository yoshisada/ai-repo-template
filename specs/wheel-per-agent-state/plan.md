# Implementation Plan: Wheel Per-Agent State Files

**Branch**: `build/wheel-per-agent-state-20260406` | **Date**: 2026-04-06 | **Spec**: [spec.md](spec.md)
**PRD**: `docs/features/2026-04-06-wheel-per-agent-state/PRD.md`

## Summary

Move wheel's workflow state from a single hardcoded `.wheel/state.json` to per-agent state files named `state_{session_id}_{agent_id}.json`. The skill creates with session_id only; the first hook renames with agent_id. Ownership is implicit in the filename, replacing the JSON-field guard logic.

## Technical Context

**Language/Version**: Bash 5.x
**Primary Dependencies**: jq, existing wheel engine libs (state.sh, workflow.sh, dispatch.sh, engine.sh, context.sh, lock.sh)
**Storage**: `.wheel/state_*.json` (file-based JSON state)
**Testing**: Manual verification (no test suite for the plugin itself)
**Target Platform**: macOS / Linux (Claude Code host)
**Project Type**: Claude Code plugin (shell scripts + markdown)
**Constraints**: <10ms hook latency increase, no new dependencies, flat files only in `.wheel/`

## Constitution Check

| Gate | Status | Notes |
|------|--------|-------|
| Spec-first | PASS | spec.md created before implementation |
| Interface contracts | PASS | contracts/interfaces.md defined below |
| Incremental tasks | PASS | tasks.md will be created |
| Small focused changes | PASS | Each file change is bounded |

## Project Structure

### Documentation (this feature)

```text
specs/wheel-per-agent-state/
├── spec.md
├── plan.md
├── contracts/
│   └── interfaces.md
├── tasks.md
└── agent-notes/
```

### Source Code (files that change)

```text
plugin-wheel/
├── lib/
│   ├── state.sh          # FR-011: state_init accepts session_id, builds filename
│   └── guard.sh          # FR-005: Simplified to resolve_state_file + rename logic
├── hooks/
│   ├── stop.sh           # FR-004: Construct state filename from hook input
│   ├── post-tool-use.sh  # FR-004: Construct state filename from hook input
│   ├── subagent-start.sh # FR-003/004: Construct filename + first-hook rename
│   ├── subagent-stop.sh  # FR-004: Construct state filename from hook input
│   ├── teammate-idle.sh  # FR-004: Construct state filename from hook input
│   └── session-start.sh  # FR-004: Construct state filename from hook input
├── skills/
│   ├── wheel-run/SKILL.md    # FR-002/007: Pass session_id, check for existing
│   ├── wheel-status/SKILL.md # FR-008: Glob state_*.json, display all
│   └── wheel-stop/SKILL.md   # FR-009: Glob state_*.json, target specific
└── lib/
    └── engine.sh         # FR-010: engine_init/kickstart accept session_id-based filename
```

### Files NOT changing

- `plugin-wheel/lib/dispatch.sh` — already receives state_file as parameter
- `plugin-wheel/lib/workflow.sh` — no state file logic
- `plugin-wheel/lib/context.sh` — no state file logic
- `plugin-wheel/lib/lock.sh` — no state file logic

## Design Decisions

### D1: guard.sh becomes state file resolver

Current `guard.sh` does JSON-field comparison for ownership. With filename-based ownership, guard logic reduces to: "construct the expected filename, check if it exists." The `guard_check` function is replaced by `resolve_state_file` which:
1. Extracts session_id and agent_id from hook input
2. Checks for `state_{session_id}_{agent_id}.json` (if agent_id non-empty)
3. Falls back to `state_{session_id}.json`
4. If neither exists, returns 1 (pass-through)
5. On first-hook detection (found session-only file, have agent_id), renames it

### D2: engine_init no longer hardcodes STATE_FILE

Currently `engine_init` sets `STATE_FILE="${STATE_DIR}/state.json"`. It must accept the state filename as a parameter or construct it from session_id. Since hooks construct the filename from hook input before calling `engine_init`, we pass the resolved state file path.

### D3: All 6 hooks share a common preamble

Instead of each hook checking `if [[ ! -f ".wheel/state.json" ]]`, they all:
1. Read hook input
2. Call `resolve_state_file` to get the correct state filename
3. If no state file found, pass through
4. Read workflow_file from the resolved state file
5. Proceed with engine_init using the resolved path

### D4: wheel-run checks session_id glob

`/wheel-run` currently checks `if [[ -f ".wheel/state.json" ]]`. It must now check `ls .wheel/state_${session_id}*.json 2>/dev/null` to see if this session already has a workflow running.

## Phases

### Phase 1: Core Library Changes (state.sh, guard.sh, engine.sh)

Update `state_init` to accept session_id and build the filename. Replace `guard_check` with `resolve_state_file` in guard.sh. Update `engine_init` to accept a state file path.

### Phase 2: Hook Updates (all 6 hooks)

Update all 6 hooks to use the new `resolve_state_file` preamble instead of hardcoded `state.json` checks.

### Phase 3: Skill Updates (wheel-run, wheel-status, wheel-stop)

Update skills to work with per-agent state files.
