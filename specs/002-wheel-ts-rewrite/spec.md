# Spec: Wheel Plugin TypeScript Rewrite

**Feature Branch**: `002-wheel-ts-rewrite`
**Created**: 2026-04-29
**Status**: Draft
**Input**: PRD at `docs/features/2026-04-29-wheel-typescript-rewrite/PRD.md`
**Parent Spec**: `specs/wheel/spec.md` (all 15 FRs inherited)

## Technical Context

**Language/Version**: TypeScript (strict mode), Node.js 20+
**Primary Dependencies**: `fs`, `path`, `crypto`, `os` (Node.js built-ins); `jsonc-parser` for JSON tolerance
**Storage**: Filesystem — `.wheel/state_*.json` (existing schema, unchanged)
**Testing**: Vitest (unit), `kiln:test` (integration), `wheel-test` (end-to-end)
**Target Platform**: macOS, Linux, Windows (WSL2 / Git Bash)
**Project Type**: Claude Code plugin / CLI tool
**Performance Goals**: Hook invocation ≤ 500ms (NFR-002, current baseline preserved)
**Scale/Scope**: ~6,500 lines shell → TypeScript; all 15 wheel specs preserved

## What This Spec Covers

The PRD defines the product-level requirements (why, what). This spec defines the technical design (how). It covers:
- Directory structure and file layout
- Source-to-dist compilation pipeline
- Hook invocation compatibility (shell shim vs node direct)
- Shared utilities API (`src/shared/`)
- Core library API (typed equivalents of shell functions)
- Interface contracts for all exported functions
- Testing strategy

## Constraints

- Hook invocation form must work without modification on Windows (WSL2 / Git Bash)
- State file schema must be byte-for-byte identical to shell version
- `workflow.json` parsing must tolerate U+0000–U+001F bytes (current harness behavior)
- No new runtime dependencies beyond Node.js

## Key Design Decisions

See `research.md` for alternatives evaluated.

### 1. Hook Invocation: Node Direct Over Shell Shim

Claude Code `hooks/hooks.json` supports `"type": "command"` with a shell command string. If the command is `node /path/to/hook.js`, Node.js executes directly without a shell.

**Decision**: Test node-direct invocation in Phase 1. If it fails, fall back to shell shim.

### 2. State Persistence: `fs.promises` + `crypto.randomUUID()`

Atomic write: `tmpfile` + `mv` (same as shell). Lock: `fs.mkdir` with `{ recursive: false }` (same as shell `mkdir -Z`).

**Decision**: Match shell behavior exactly for state I/O. No WAL, no SQLite.

### 3. JSON Parsing: `jsonc-parser` Over Native `JSON.parse`

Claude Code's harness emits literal control bytes inside `tool_input.command` values. `JSON.parse` rejects these; `jsonc-parser` with `allowTrailingComma` + `allowBareSingleString` tolerates them (same as current Python fallback).

**Decision**: Use `jsonc-parser` for hook input parsing. Use `JSON.parse` for workflow JSON (user-provided, clean).

### 4. Shared Utilities: `src/shared/` Subdirectory

jq wrappers, state ops, fs utils, and error types live in `src/shared/` within `plugin-wheel/`. Published as part of `@yoshisada/wheel` npm package; other plugins import from the installed wheel package's `dist/shared/`.

**Decision**: Keep shared utilities inside `plugin-wheel/` (not a separate package). Publish as sub-export of main wheel package.

## Project Structure

```
plugin-wheel/
├── src/
│   ├── shared/                 # jq wrappers, state ops, fs, errors
│   │   ├── jq.ts
│   │   ├── state.ts
│   │   ├── fs.ts
│   │   ├── error.ts
│   │   └── index.ts
│   ├── hooks/                 # Hook entry points
│   │   ├── post-tool-use.ts
│   │   ├── stop.ts
│   │   ├── teammate-idle.ts
│   │   ├── subagent-start.ts
│   │   ├── subagent-stop.ts
│   │   └── session-start.ts
│   ├── lib/                   # Core logic (mirrors existing .sh files)
│   │   ├── state.ts           # ~600 lines
│   │   ├── engine.ts          # ~350 lines
│   │   ├── dispatch.ts        # ~2500 lines
│   │   ├── workflow.ts        # ~900 lines
│   │   ├── context.ts
│   │   ├── guard.ts
│   │   ├── lock.ts
│   │   ├── log.ts
│   │   ├── preprocess.ts
│   │   ├── registry.ts
│   │   └── resolve_inputs.ts
│   ├── bin/                   # CLI tools
│   │   ├── validate-workflow.ts
│   │   ├── wheel-status.ts
│   │   ├── flag-needs-input.ts
│   │   └── wheel-log.ts
│   └── index.ts               # Main entry (routes by process.argv[1])
├── dist/                      # Compiled output (npm published)
├── hooks/                     # Shell shims (only if node-direct fails)
│   └── *.sh
├── scripts/                   # Unchanged (harness, agents, render)
├── skills/                    # Unchanged
├── tests/                     # Unchanged (kiln:test fixtures)
├── package.json
├── tsconfig.json
└── vitest.config.ts
```

## Interface Contracts

See `contracts/interfaces.md` (Phase 1 output).

## Functional Requirements

Inherited from `specs/wheel/spec.md` FR-001 through FR-028, plus:

- **FR-T001**: All 6 hook handlers must produce identical behavior to their shell counterparts
- **FR-T002**: State file schema unchanged — all existing `.wheel/state_*.json` files remain valid
- **FR-T003**: `hooks/hooks.json` uses `dist/` paths after build, `src/` paths before build
- **FR-T004**: Vitest unit tests cover `src/shared/` and `src/lib/` with ≥80% coverage
- **FR-T005**: All 4 `kiln:test` fixtures pass against TypeScript implementation
- **FR-T006**: All 12 `wheel-test` workflows pass against TypeScript implementation

## What Is NOT In Scope

- Rewriting `kiln:test` harness
- Rewriting `wheel-test` skill
- Changing workflow JSON schema
- Dropping any hook or step type
- Publishing separate `plugin-shared` npm package