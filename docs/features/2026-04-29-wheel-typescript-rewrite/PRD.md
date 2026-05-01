# Feature PRD: Wheel Plugin TypeScript Rewrite

**Parent**: `specs/wheel/spec.md`
**Slug**: `wheel-typescript-rewrite`
**Date**: 2026-04-29
**Status**: Draft

## Summary

Rewrites `plugin-wheel` from ~6,500 lines of shell to TypeScript with cross-platform Node.js runtime, a shared library for use across all five plugins, and full test coverage via `wheel-test` + unit tests.

## Problem

Three convergent problems with the current shell implementation:

1. **Platform lock-in** — Shell scripts fail on Windows without Git Bash / WSL. Node.js is already a Claude Code prerequisite.
2. **Repeated logic** — Kiln, shelf, and wheel all copy-paste the same jq-wrapping, state-read/write, and error-handling patterns across plugins.
3. **Unreliable testing** — Shell logic bugs are caught late. The `teammate_idle` lookup priority bug (commit `4b4388f8`) is representative: found via integration test, not unit test.

## What This Feature Does

Preserves all existing wheel behavior (all workflow step types, all six hooks, identical state file schema) while:
- Replacing shell libraries with typed TypeScript
- Creating a shared `plugin-shared/` library for cross-plugin code reuse
- Enabling unit testing of core logic (dispatch, engine, state operations)
- Eliminating platform dependency on bash

## What Stays the Same

| Item | Detail |
|---|---|
| Workflow JSON schema | Identical — no migration needed for existing workflows |
| State file format | `.wheel/state_*.json` — same JSON schema |
| All 6 hooks | `PostToolUse`, `Stop`, `TeammateIdle`, `SubagentStart`, `SubagentStop`, `SessionStart` |
| All 15 `specs/wheel*` FRs | Preserved verbatim |
| `wheel-test` skill | Unchanged — integration tests the final behavior |
| `kiln:test` harness | Unchanged — same 4 test fixtures, same assertions |
| `hooks/hooks.json` | Same structure, references `dist/` binaries |

## What Changes

### Before → After

| Layer | Before | After |
|---|---|---|
| Hook entry points | Shell shims (`hooks/*.sh`) | Node.js binaries (`dist/hooks/*.js`) + optional shell shims |
| Core libraries | Shell (`lib/*.sh`, ~6,500 lines) | TypeScript (`src/lib/*.ts`) |
| State persistence | `jq` + file I/O in shell | Typed `fs` operations in TypeScript |
| Cross-plugin shared | None (each plugin has its own copy) | `plugin-shared/` library |
| Testing | `kiln:test` (integration only) | Unit tests (Vitest) + `kiln:test` (integration) |
| Package manager | None | npm |
| Build | None | `tsc` → `dist/` |

### Hook Entry Point Strategy

Claude Code hooks are invoked as processes via `hooks/hooks.json`. The invocation form must work cross-platform:

1. Test: does Claude Code natively invoke `node` binaries?
   - If yes: `hooks/hooks.json` → `"command": "node {PLUGIN_DIR}/dist/hooks/post-tool-use.js"`
   - If no: shell shim → `#!/usr/bin/env node` shebang test, fallback to `sh -c "node ..."`

2. Shell shim (if needed, Phase 1):
   ```sh
   #!/bin/sh
   exec node "$PLUGIN_DIR/dist/hooks/post-tool-use.js" "$@"
   ```
   `sh` is available on Windows via Git Bash / MSYS2 / WSL. This is the minimum shell surface.

### Shared Utilities Within `plugin-wheel/`

The shared jq wrappers, state operations, fs utils, and error types live in `src/shared/` within `plugin-wheel/`. Other plugins import from `plugin-wheel/dist/shared/` as a npm dependency (published alongside the main package):

```typescript
// plugin-wheel/src/shared/state.ts
export async function stateRead(path: string): Promise<State>
export async function stateWrite(path: string, state: State): Promise<void>

// plugin-wheel/src/shared/jq.ts
export function jqQuery<T>(json: unknown, path: string): T
export function jqUpdate(json: unknown, path: string, value: unknown): string

// plugin-wheel/src/shared/fs.ts
export async function atomicWrite(path: string, content: string): Promise<void>

// plugin-wheel/src/shared/error.ts
export class WheelError extends Error { code: string; context: Record<string, unknown> }
export class StateNotFoundError extends WheelError { ... }
export class ValidationError extends WheelError { ... }
```

Kiln and shelf add `plugin-wheel` as a dependency and import from `plugin-wheel/dist/shared/` — eliminating their copy-pasted jq wrappers.

### Directory Structure

```
plugin-wheel/
├── src/
│   ├── shared/                # Shared utilities (jq, state, fs, errors)
│   │   ├── state.ts
│   │   ├── jq.ts
│   │   ├── fs.ts
│   │   ├── error.ts
│   │   └── index.ts
│   ├── hooks/                 # TypeScript hook handlers
│   │   ├── post-tool-use.ts
│   │   ├── stop.ts
│   │   ├── teammate-idle.ts
│   │   ├── subagent-start.ts
│   │   ├── subagent-stop.ts
│   │   └── session-start.ts
│   ├── lib/                   # Core wheel logic
│   │   ├── state.ts
│   │   ├── engine.ts
│   │   ├── dispatch.ts
│   │   ├── workflow.ts
│   │   ├── context.ts
│   │   ├── guard.ts
│   │   ├── lock.ts
│   │   ├── log.ts
│   │   ├── preprocess.ts
│   │   ├── registry.ts
│   │   └── resolve_inputs.ts
│   └── index.ts               # Entry point (routes by hook name)
├── dist/                      # Compiled JS (published to npm)
├── hooks/                     # Shell shims only if needed
│   └── *.sh
├── bin/                       # CLI tools
├── skills/                    # Unchanged
├── tests/                     # Unchanged
├── package.json
└── tsconfig.json
```

## Functional Requirements

| ID | Requirement |
|---|---|
| FR-001 | All 6 hook handlers (`PostToolUse`, `Stop`, `TeammateIdle`, `SubagentStart`, `SubagentStop`, `SessionStart`) must behave identically to the shell version |
| FR-002 | State file schema unchanged — `.wheel/state_*.json` format identical |
| FR-003 | `workflow.json` schema unchanged — all step types work |
| FR-004 | `hooks/hooks.json` compatible with plugin auto-merge system |
| FR-005 | Windows: must work via `node` binary (WSL2 or Git Bash shell) |
| FR-006 | All 4 `kiln:test` fixtures pass |
| FR-007 | All 12 `wheel-test` workflows pass |
| FR-008 | Wheel's shared utilities (`src/shared/`) are importable by other plugins |
| FR-009 | Hook invocation latency ≤ current baseline (500ms NFR-002) |

## Non-Goals

- Not changing the workflow JSON schema — backwards compatible with all existing workflows
- Not dropping any hook type or step type
- Not rewriting `kiln:test` harness — it tests final behavior, not implementation
- Not requiring Windows-native support without shell layer

## Phase Plan

### Phase 1 — Shared Utilities + Hook Compatibility
- Extract `src/shared/` with jq wrappers, state ops, fs utils, error types
- Unit tests for shared utilities
- Test hook invocation compatibility (does Claude Code invoke `node` directly?)
- Shell shim if needed

### Phase 2 — State Layer
- `src/lib/state.ts` — typed state read/write
- Preserve atomic write (tmp + mv), lock pattern, error codes
- Unit tests + integration test

### Phase 3 — Hook Entry Points
- `src/hooks/*.ts` — all 6 hooks translated to TypeScript
- Call into `src/lib/` for all logic
- Integration test: all hooks fire correctly

### Phase 4 — Core Engine
- `src/lib/engine.ts` — kickstart, cursor advance, step routing
- `src/lib/dispatch.ts` — agent dispatch, team wait, team delete, command/loop/branch
- Unit tests for pure functions
- Integration test: 3-step linear workflow completes

### Phase 5 — Full Integration
- All 4 `kiln:test` fixtures pass
- All 12 `wheel-test` workflows pass
- No regression vs shell version

### Phase 6 — Shared Library Accessibility
- `src/shared/` is properly typed and exported
- CI test confirms kiln or shelf can import shared utilities from wheel's dist
- Documentation: how other plugins import shared utilities

## Success Criteria

| Criterion | Verification |
|---|---|
| All 4 `kiln:test` tests pass | `npm run test:harness` |
| All 12 `wheel-test` workflows pass | `/wheel:wheel-test` skill |
| `plugin-shared/` imported by ≥1 plugin | Import statement in kiln or shelf |
| Windows compatibility | Runs in WSL2 or Git Bash without modification |
| No state schema change | All existing `.wheel/state_*.json` files valid |
| Hook latency ≤ 500ms | Profiled before/after comparison |

## Risks

| Risk | Mitigation |
|---|---|
| Claude Code doesn't natively invoke `node` | Test in Phase 1; shell shim fallback ready |
| Performance regression | Profile before/after; optimize hot paths |
| Consumers have stale local `.claude/hooks/` copies | Document cleanup step; check in Phase 5 CI |
| Cross-plugin import creates coupling | `plugin-shared/` has no dependencies on any plugin |

## Open Questions

1. Do we keep shell shims permanently, or require Node.js as the only runtime?
2. What's the CI matrix for Windows — WSL2, GitHub Actions Windows runner, or manual only?
3. Do we keep `hooks/hooks.json` in the plugin root (for auto-merge), or move it to `dist/` after build?
4. How do we publish — as one npm package `@yoshisada/wheel` with `dist/shared/` as a sub-export, or separate packages?

## Tech Stack

- **Language**: TypeScript (strict mode)
- **Runtime**: Node.js 20+ (required by Claude Code)
- **Build**: `tsc` (no bundler — CLI tools, not web)
- **Testing**: Vitest (unit), `kiln:test` (integration)
- **Package manager**: npm
