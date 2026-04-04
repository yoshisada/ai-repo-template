# Implementation Plan: Wheel Skill-Based Activation

**Branch**: `build/wheel-skill-activation-20260404` | **Date**: 2026-04-04 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/wheel-skill-activation/spec.md`

## Summary

Add three skills (`/wheel-run`, `/wheel-stop`, `/wheel-status`) to the wheel plugin and replace the auto-discovery guard clause in all six hook scripts with a single `state.json` existence check. This makes wheel opt-in: hooks are dormant until a user explicitly starts a workflow.

## Technical Context

**Language/Version**: Bash 3.2+ (macOS) / 5.x (Linux)  
**Primary Dependencies**: jq (JSON manipulation), existing wheel lib/ modules  
**Storage**: Filesystem — `.wheel/state.json`, `.wheel/history/`  
**Testing**: Manual validation (no test framework for shell skills)  
**Target Platform**: macOS, Linux (Claude Code plugin)  
**Project Type**: Claude Code plugin (skills + hooks)  
**Constraints**: Hook guard clause < 5ms, no new runtime dependencies  

## Constitution Check

| Gate | Status | Notes |
|------|--------|-------|
| Spec exists before code | PASS | spec.md created |
| Plan exists before code | PASS | this file |
| Interface contracts | PASS | contracts/interfaces.md defines skill I/O and hook guard signatures |
| Tasks before implementation | PENDING | tasks.md next |

## Project Structure

### Documentation (this feature)

```text
specs/wheel-skill-activation/
├── spec.md
├── plan.md              # This file
├── contracts/
│   └── interfaces.md    # Skill I/O and hook guard contracts
├── tasks.md             # Task breakdown
└── agent-notes/         # Agent friction notes
```

### Source Code (plugin-wheel/)

```text
plugin-wheel/
├── skills/
│   ├── wheel-run/
│   │   └── SKILL.md          # NEW — /wheel-run skill definition
│   ├── wheel-stop/
│   │   └── SKILL.md          # NEW — /wheel-stop skill definition
│   └── wheel-status/
│       └── SKILL.md          # NEW — /wheel-status skill definition
├── hooks/
│   ├── stop.sh               # MODIFIED — new guard clause, remove auto-discovery
│   ├── teammate-idle.sh      # MODIFIED — new guard clause, remove auto-discovery
│   ├── subagent-start.sh     # MODIFIED — new guard clause, remove auto-discovery
│   ├── subagent-stop.sh      # MODIFIED — new guard clause, remove auto-discovery
│   ├── session-start.sh      # MODIFIED — new guard clause (already has state.json check, simplify)
│   └── post-tool-use.sh      # MODIFIED — new guard clause (already has state.json check, simplify)
├── lib/
│   └── workflow.sh           # MODIFIED — add workflow_validate_unique_ids()
└── package.json              # MODIFIED — add skills/ to files array
```

**Structure Decision**: All changes are within `plugin-wheel/`. Three new skill directories, six modified hook files, one modified lib file, one modified package.json.

## Design Decisions

### Hook Guard Clause Pattern

Every hook script currently has ~10 lines of auto-discovery logic (find workflows/, WHEEL_WORKFLOW env var, engine_init). This is replaced with a 4-line guard:

```bash
# Guard: exit early if no workflow is active (FR-004)
if [[ ! -f ".wheel/state.json" ]]; then
  echo '{"decision": "allow"}'
  exit 0
fi
```

For `post-tool-use.sh`, the guard uses plain `exit 0` (no JSON output needed for PostToolUse hooks).

After the guard, the hook proceeds to load the workflow file path FROM state.json (not from auto-discovery), source the engine, and handle the hook.

### Workflow File Resolution After Guard

Once state.json exists, hooks need the workflow file path. Two options:
1. Store the workflow file path in state.json (added by `/wheel-run`)
2. Have hooks look it up from the workflow name in state.json

**Decision**: Store `workflow_file` in state.json. This is set by `/wheel-run` and read by hooks. This avoids hooks needing to search for the file and ensures consistency.

### Skill Structure

Skills are Markdown files (`SKILL.md`) with embedded shell commands. They use `$ARGUMENTS` for user input. The skill instructs the LLM to execute specific shell commands — the LLM reads the SKILL.md and follows the instructions.

### Validation Strategy

`/wheel-run` reuses `workflow_load()` for structural validation (required fields, branch targets) and adds `workflow_validate_unique_ids()` for the unique-step-ID check (FR-006). This keeps validation centralized in `lib/workflow.sh`.

## Complexity Tracking

No constitution violations. All changes are within plugin-wheel/, touching one bounded area (activation gating). No new abstractions beyond the three skills.
