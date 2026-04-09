# Implementation Plan: Wheel Team Primitives

**Branch**: `build/wheel-team-primitives-20260409` | **Date**: 2026-04-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/wheel-team-primitives/spec.md`

## Summary

Add four new step types (`team-create`, `teammate`, `team-wait`, `team-delete`) to the wheel workflow engine that enable parallel agent execution via Claude Code agent teams. Implementation extends the existing hook-driven engine with new dispatch handlers in `dispatch.sh`, team state management in `state.sh`, and cascade stop logic in `post-tool-use.sh`. The existing step type pattern (dispatch_step case/esac routing, state tracking, hook-based advancement) is preserved — new handlers follow the same structure as existing `dispatch_agent`, `dispatch_command`, `dispatch_workflow`, etc.

## Technical Context

**Language/Version**: Bash 5.x  
**Primary Dependencies**: jq (JSON parsing), Claude Code agent teams API (TeamCreate, TaskCreate, TaskList, TaskUpdate, TeamDelete, Agent, SendMessage)  
**Storage**: File-based JSON state (`.wheel/state_*.json`)  
**Testing**: Manual integration testing via workflow execution  
**Target Platform**: macOS/Linux (Claude Code runtime)  
**Project Type**: Plugin (Claude Code workflow engine)  
**Performance Goals**: Teammate spawn < 5 seconds, team state < 10KB with 10 agents  
**Constraints**: No new dependencies; all operations must be idempotent  
**Scale/Scope**: 4 new step types, ~8 new functions in dispatch.sh, ~4 new functions in state.sh

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| Spec-First (I) | PASS | spec.md exists with 31 FRs, acceptance scenarios, success criteria |
| 80% Coverage (II) | N/A | No test suite for plugin itself; testing via workflow execution |
| PRD as Source (III) | PASS | All 31 FRs trace to PRD |
| Hooks Enforce (IV) | PASS | Not modifying hook enforcement — adding new step handlers within existing hooks |
| E2E Testing (V) | N/A | Plugin testing is done via pipeline execution on consumer projects |
| Small Changes (VI) | PASS | Each step type is a bounded handler; files stay under 500 lines |
| Interface Contracts (VII) | PASS | contracts/interfaces.md will define all function signatures |
| Incremental Tasks (VIII) | PASS | Tasks broken by step type with phase commits |

## Project Structure

### Documentation (this feature)

```text
specs/wheel-team-primitives/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 — architecture decisions
├── data-model.md        # Phase 1 — state file schema extensions
├── quickstart.md        # Phase 1 — usage examples
├── contracts/
│   └── interfaces.md    # Phase 1 — function signatures
├── checklists/
│   └── requirements.md  # Quality checklist
└── tasks.md             # Phase 2 — task breakdown
```

### Source Code (repository root)

```text
plugin-wheel/
├── lib/
│   ├── dispatch.sh      # MODIFY — add dispatch_team_create, dispatch_teammate, dispatch_team_wait, dispatch_team_delete handlers + case branches
│   ├── state.sh         # MODIFY — add team state management functions (state_set_team, state_get_team, state_add_teammate, state_get_teammates)
│   ├── engine.sh        # MODIFY — add team-* types to engine_kickstart case + engine_handle_hook post_tool_use handler
│   ├── context.sh       # MODIFY — add context/assignment file writing for teammates
│   ├── guard.sh         # NO CHANGE — existing per-agent state resolution handles teammate state files
│   ├── workflow.sh       # MODIFY — add team step validation to workflow_validate_references
│   └── lock.sh          # NO CHANGE
├── hooks/
│   ├── post-tool-use.sh # MODIFY — add cascade stop for team agents in deactivate.sh handler
│   ├── stop.sh          # NO CHANGE — delegates to engine_handle_hook which routes to dispatch_step
│   └── ...              # NO CHANGE
└── ...
```

**Structure Decision**: All changes are within the existing `plugin-wheel/lib/` and `plugin-wheel/hooks/` directories. No new files — all new functions are added to existing modules following the established pattern.

## Implementation Phases

### Phase 1: Step Type Handlers (FR-001 through FR-014, FR-020-023)

**Goal**: Implement all four step type dispatch handlers.

**Files modified**:
- `plugin-wheel/lib/dispatch.sh` — Add `dispatch_team_create()`, `dispatch_teammate()`, `dispatch_team_wait()`, `dispatch_team_delete()`, and case branches in `dispatch_step()`

**Approach**:
Each handler follows the established pattern from `dispatch_agent()`, `dispatch_command()`, etc.:
1. Read state + step status
2. On `stop` hook: transition from pending → working, execute step logic
3. On `post_tool_use` hook: detect completion, mark done, advance cursor
4. On completion: resolve next index, advance cursor, chain to next auto-executable step

**Handler details**:

- **dispatch_team_create**: On stop hook when pending: call TeamCreate (via instruction injection telling the agent to call TeamCreate), record team name in state under `teams.{step-id}`. Mark done, advance cursor. Since TeamCreate is an LLM tool call, this handler injects the instruction and waits for the PostToolUse event confirming team creation.

- **dispatch_teammate**: On stop hook when pending: read `loop_from` output if present (parse JSON array, distribute round-robin with `max_agents` cap), then spawn agent(s) via instruction injection. Each spawn: write context.json and assignment.json to output dir, create TaskCreate entry, call Agent tool with `run_in_background: true`. Mark step done immediately after spawning (fire-and-forget). Advance cursor.

- **dispatch_team_wait**: On stop hook when pending: mark working. On each hook invocation while working: poll TaskList, check all teammate tasks. If all done/failed: write summary to output file, copy outputs if `collect_to` set, mark done, advance cursor. If not all done: return block with status message (30-second natural polling via hook cadence).

- **dispatch_team_delete**: On stop hook when pending: send shutdown to all agents, call TeamDelete, mark done, advance cursor. If teammates still running: force-terminate first.

### Phase 2: Engine Integration (FR-024 through FR-031)

**Goal**: Wire the new step types into the engine's hook system and state management.

**Files modified**:
- `plugin-wheel/lib/state.sh` — Add team state functions
- `plugin-wheel/lib/engine.sh` — Add team types to kickstart and hook handler
- `plugin-wheel/lib/context.sh` — Add teammate context/assignment writing
- `plugin-wheel/lib/workflow.sh` — Add team step reference validation
- `plugin-wheel/hooks/post-tool-use.sh` — Add cascade stop for team agents

**Approach**:

- **State management** (state.sh): Add functions for team CRUD in state file. Teams stored under `teams.{step-id}` with team name, teammate task IDs, and statuses. Keep minimal (references only, not full outputs) to stay under 10KB.

- **Engine routing** (engine.sh): Add `team-create|teammate|team-wait|team-delete` to `engine_kickstart()` case statement and to `engine_handle_hook()` post_tool_use handler. Team-create and teammate are kickstartable (execute inline like command steps). Team-wait is NOT kickstartable (needs polling). Team-delete is kickstartable.

- **Context passing** (context.sh): Add `context_write_teammate_files()` that writes `context.json` (from `context_from` step outputs) and `assignment.json` (from `assign` payload) to `.wheel/outputs/team-{team-name}/{agent-name}/`. Add synthetic `_context` and `_assignment` step ID resolution.

- **Workflow validation** (workflow.sh): Validate that `teammate` steps reference valid `team-create` step IDs via their `team` field. Validate `loop_from` references existing step IDs.

- **Cascade stop** (post-tool-use.sh): In the deactivate.sh handler, after stopping parent workflows, also send shutdown to all agents on teams owned by the stopped workflow (read team names from state file's `teams` key).

## Complexity Tracking

No constitution violations. All changes follow existing patterns.
