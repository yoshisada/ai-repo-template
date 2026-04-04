# Implementation Plan: Wheel — Hook-based Workflow Engine Plugin

**Branch**: `build/wheel-20260403` | **Date**: 2026-04-03 | **Spec**: [specs/wheel/spec.md](spec.md)
**Input**: Feature specification from `specs/wheel/spec.md`

## Summary

Build a deterministic, hook-driven workflow engine for Claude Code as the `@yoshisada/wheel` plugin. The engine uses a Bash state machine (`engine.sh`) with `jq` for JSON manipulation, driven by 6 Claude Code hook handlers (Stop, TeammateIdle, SubagentStart, SubagentStop, SessionStart, PostToolUse). Workflow definitions are JSON files; all runtime state persists in `.wheel/state.json`. The engine supports linear steps, parallel fan-out/fan-in, command steps, branch/loop control flow, approval gates, and session resumption.

## Technical Context

**Language/Version**: Bash 3.2+ (macOS default) / 5.x (Linux), Node.js 18+ (init.mjs only)
**Primary Dependencies**: `jq` (JSON manipulation), standard Unix tools (`mkdir`, `date`, `mktemp`)
**Storage**: Filesystem — `.wheel/state.json` for state, `mkdir` for locks
**Testing**: Shell-based integration tests (run workflows, assert state.json contents)
**Target Platform**: macOS (Bash 3.2+), Linux (Bash 5.x)
**Project Type**: Claude Code plugin (hooks + skills + scaffold)
**Performance Goals**: Hook execution < 500ms per invocation
**Constraints**: No runtime dependencies beyond bash, jq, and standard Unix tools; standalone (no kiln dependency)
**Scale/Scope**: Single workflow per session, steps in the tens (not hundreds)

## Constitution Check

| Gate | Status | Notes |
|------|--------|-------|
| Spec-first (I) | PASS | spec.md created with user stories and FRs |
| 80% coverage (II) | N/A | Shell scripts — coverage via integration tests |
| PRD as source of truth (III) | PASS | All FRs trace to PRD |
| Hooks enforce rules (IV) | PASS | This feature IS the hooks |
| E2E testing (V) | PASS | Example workflow serves as E2E test |
| Small focused changes (VI) | PASS | Each hook handler is a focused script |
| Interface contracts (VII) | PASS | contracts/interfaces.md will define all functions |
| Incremental task completion (VIII) | PASS | Tasks will be marked [X] as completed |

## Project Structure

### Documentation (this feature)

```text
specs/wheel/
├── spec.md              # Feature specification
├── plan.md              # This file
├── contracts/
│   └── interfaces.md    # Function signatures for all modules
└── tasks.md             # Task breakdown
```

### Source Code (repository root)

```text
plugin-wheel/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest
│   └── marketplace.json     # Distribution config
├── hooks/
│   ├── stop.sh              # FR-004: Stop hook — inject next step instruction
│   ├── teammate-idle.sh     # FR-005: TeammateIdle hook — gate agents
│   ├── subagent-start.sh    # FR-006: SubagentStart hook — inject context
│   ├── subagent-stop.sh     # FR-007: SubagentStop hook — mark done, fan-in
│   ├── session-start.sh     # FR-008: SessionStart(resume) hook — reload state
│   └── post-tool-use.sh     # FR-022: PostToolUse(Bash) hook — command audit log
├── lib/
│   ├── engine.sh            # FR-001: Core state machine engine
│   ├── state.sh             # FR-002: State read/write helpers (atomic writes)
│   ├── workflow.sh          # FR-012: Workflow definition parser/validator
│   ├── lock.sh              # FR-010: mkdir-based atomic locking
│   ├── dispatch.sh          # FR-003/019/024/025: Step type dispatcher
│   └── context.sh           # FR-027/028: Context injection and output capture
├── bin/
│   └── init.mjs             # FR-016: Scaffold script for consumer projects
├── scaffold/
│   ├── settings-hooks.json  # Hook configuration to merge into consumer .claude/settings.json
│   └── example-workflow.json # Example 3-step workflow
├── workflows/               # Example workflows shipped with plugin
│   └── example.json         # FR-012: Example linear+command workflow
├── package.json             # FR-015: npm package @yoshisada/wheel
└── README.md                # Usage documentation
```

### Consumer Project Structure (after init)

```text
consumer-project/
├── .wheel/
│   ├── state.json           # Runtime state (gitignored)
│   └── .locks/              # Atomic lock directory (gitignored)
├── workflows/
│   └── example.json         # Copied from scaffold
└── .claude/
    └── settings.json        # Hooks added by init.mjs
```

**Structure Decision**: Plugin structure mirrors kiln's pattern (`plugin-wheel/` directory with `.claude-plugin/`, `hooks/`, `lib/`, `bin/`, `scaffold/`). All engine logic lives in `lib/` as sourced Bash functions. Each hook handler in `hooks/` is a thin dispatcher that sources `lib/engine.sh` and calls the appropriate function.

## Architecture Decisions

### AD-001: Bash + jq over Node.js for engine

The engine is pure Bash + jq. Rationale:
- Hooks execute on every tool use — startup latency matters. Bash scripts have near-zero startup vs Node.js cold start.
- `jq` handles all JSON manipulation natively, avoiding custom parsing.
- NFR-004 requires no runtime dependencies beyond bash/jq/Unix tools.
- The init scaffold (`bin/init.mjs`) is the only Node.js component, matching kiln's pattern for npm distribution.

### AD-002: Atomic state writes via tmp+rename

All state.json writes go to a temp file first, then `mv` (rename) to the final path (NFR-001). This prevents partial writes from corrupting state during crashes.

### AD-003: mkdir-based locking for parallel fan-in

`mkdir` is atomic on all Unix filesystems. The lock directory path encodes the step ID. The last agent to complete acquires the lock and advances the step. Failed `mkdir` means another agent already advanced.

### AD-004: JSON for workflow definitions

JSON over YAML to avoid adding a YAML parser dependency. `jq` handles JSON natively. Workflow files are small enough that JSON readability is acceptable.

### AD-005: Command step chaining via exec

Consecutive command steps chain by re-exec'ing the hook script (`exec "$0"`), avoiding LLM round-trips. This keeps deterministic operations fast.

### AD-006: Hook handlers as thin dispatchers

Each hook script in `hooks/` is a thin wrapper: parse stdin JSON, source `lib/engine.sh`, call the relevant function, output the hook response JSON. All logic lives in `lib/` for testability and reuse.

## Complexity Tracking

No constitution violations to justify.
