# Implementation Plan: Wheel Session Guard

**Branch**: `build/wheel-session-guard-20260405` | **Date**: 2026-04-05 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/wheel-session-guard/spec.md`

## Summary

Add ownership tracking to `.wheel/state.json` so only the originating agent can advance a workflow. Create a shared `lib/guard.sh` with a guard function, update `state_init` to include ownership fields, update all 6 hook scripts to call the guard before processing, and use first-hook stamping to capture the owner context since `/wheel-run` is a skill without hook input.

## Technical Context

**Language/Version**: Bash 5.x  
**Primary Dependencies**: `jq` (JSON parsing), existing wheel engine libs (state.sh, workflow.sh, dispatch.sh, engine.sh, context.sh, lock.sh)  
**Storage**: `.wheel/state.json` (file-based JSON state)  
**Testing**: Manual E2E verification (no automated test framework for shell hooks)  
**Target Platform**: macOS/Linux (Claude Code plugin environment)  
**Project Type**: CLI plugin (Claude Code hook scripts)  
**Performance Goals**: Guard check < 10ms per invocation (single `jq` read + compare)  
**Constraints**: No external dependencies beyond `jq` and bash builtins  
**Scale/Scope**: 6 hook scripts + 1 new library file + 1 modified library function + 1 modified skill

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| Spec-First Development | PASS | spec.md exists with FRs, user stories, acceptance scenarios |
| 80% Test Coverage | N/A | Shell hook scripts — no automated test framework in this plugin repo |
| PRD as Source of Truth | PASS | PRD at docs/features/2026-04-05-wheel-session-guard/PRD.md is authoritative |
| Hooks Enforce Rules | PASS | Not modifying kiln hooks — modifying wheel hooks (different plugin) |
| E2E Testing Required | N/A | Plugin scripts tested via manual workflow execution |
| Small, Focused Changes | PASS | Each file change is bounded; guard.sh is < 50 lines |
| Interface Contracts | PASS | contracts/interfaces.md will define guard function signature |
| Incremental Task Completion | PASS | Tasks will be marked [X] incrementally |

## Project Structure

### Documentation (this feature)

```text
specs/wheel-session-guard/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── interfaces.md    # Guard function signatures
└── tasks.md             # Phase 2 output (/tasks command)
```

### Source Code (repository root)

```text
plugin-wheel/
├── lib/
│   ├── guard.sh         # NEW — shared session guard function (FR-006)
│   ├── state.sh         # MODIFIED — state_init adds owner fields (FR-001)
│   └── engine.sh        # MODIFIED — source guard.sh in engine init
├── hooks/
│   ├── stop.sh          # MODIFIED — call guard before processing (FR-002)
│   ├── post-tool-use.sh # MODIFIED — call guard before processing (FR-002)
│   ├── subagent-start.sh # MODIFIED — call guard before processing (FR-002)
│   ├── subagent-stop.sh # MODIFIED — call guard before processing (FR-002)
│   ├── teammate-idle.sh # MODIFIED — call guard before processing (FR-002)
│   └── session-start.sh # MODIFIED — call guard before processing (FR-002)
└── skills/
    └── wheel-run/
        └── SKILL.md     # MODIFIED — document ownership context (FR-004)
```

**Structure Decision**: All changes live within the existing `plugin-wheel/` directory. One new file (`lib/guard.sh`), modifications to existing files. No new directories.

## Phases

### Phase 1: Guard Library + State Schema (Foundation)

**Goal**: Create the guard function and extend state.json with ownership fields.

1. **Create `plugin-wheel/lib/guard.sh`** (FR-006, FR-002, FR-003, FR-007)
   - Define `guard_check()` function that:
     - Reads `owner_session_id` and `owner_agent_id` from state.json
     - Extracts `session_id` and `agent_id` from hook input JSON
     - If ownership fields are empty (not yet stamped), stamps them (FR-004) and returns 0 (allow)
     - If `session_id` missing from hook input, returns 1 (pass-through)
     - Compares `session_id` — if no match, returns 1 (pass-through)
     - If `owner_agent_id` is set and `agent_id` differs, returns 1 (pass-through)
     - Otherwise returns 0 (allow — this is the owner)

2. **Modify `plugin-wheel/lib/state.sh`** (FR-001)
   - Update `state_init()` to include `owner_session_id: ""` and `owner_agent_id: ""` in the initial state JSON

3. **Modify `plugin-wheel/lib/engine.sh`**
   - Add `source "${WHEEL_LIB_DIR}/guard.sh"` to the module loading block

### Phase 2: Hook Integration (All 6 Hooks)

**Goal**: Every hook calls the guard before processing.

4. **Modify all 6 hook scripts** (FR-002)
   - For each hook (`stop.sh`, `post-tool-use.sh`, `subagent-start.sh`, `subagent-stop.sh`, `teammate-idle.sh`, `session-start.sh`):
     - After reading HOOK_INPUT and sourcing engine.sh, call `guard_check "$STATE_FILE" "$HOOK_INPUT"`
     - If guard returns 1 (non-owner), output the appropriate pass-through JSON and exit 0
     - If guard returns 0 (owner), continue with existing logic
   - The guard call is placed after `engine_init` (which sets STATE_FILE) but before `engine_handle_hook`

### Phase 3: Skill Update + Verification

**Goal**: Update the wheel-run skill and verify end-to-end.

5. **Update `plugin-wheel/skills/wheel-run/SKILL.md`** (FR-004)
   - Document that ownership is stamped by the first hook event after state creation
   - No code change needed in the skill itself — the guard's first-hook stamping handles it

6. **Verification**
   - Manually verify state.json includes ownership fields after `/wheel-run`
   - Verify guard pass-through for non-owner events
   - Verify `/wheel-status` and `/wheel-stop` still work from any agent (FR-005)

## File Ownership (for parallel agents)

| File | Owner |
|------|-------|
| `plugin-wheel/lib/guard.sh` | implementer |
| `plugin-wheel/lib/state.sh` | implementer |
| `plugin-wheel/lib/engine.sh` | implementer |
| `plugin-wheel/hooks/*.sh` (all 6) | implementer |
| `plugin-wheel/skills/wheel-run/SKILL.md` | implementer |

All files owned by a single implementer — no parallel agent conflicts.

## Complexity Tracking

No constitution violations requiring justification. All changes are small, focused, and within a single bounded area.
