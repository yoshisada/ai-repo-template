# Implementation Plan: Wheel TypeScript Rewrite

**Branch**: `002-wheel-ts-rewrite` | **Date**: 2026-04-29 | **Spec**: [spec.md](./spec.md)
**Input**: PRD at `docs/features/2026-04-29-wheel-typescript-rewrite/PRD.md`

## Summary

Rewrite `plugin-wheel` (~6,500 lines shell → TypeScript) for cross-platform portability (Node.js, no bash dependency), type safety, and unit testability. All existing wheel behavior preserved: workflow schema, state file schema, 6 hooks, 12 step types. Tests: Vitest unit + `kiln:test` integration + `wheel-test` end-to-end.

## Technical Context

**Language/Version**: TypeScript (strict mode) / Node.js 20+
**Primary Dependencies**: `jsonc-parser` (JSON tolerance), Node.js built-ins (`fs`, `path`, `crypto`, `os`)
**Storage**: Filesystem — `.wheel/state_*.json` (existing schema, unchanged)
**Testing**: Vitest (unit), `kiln:test` (integration), `wheel-test` (end-to-end)
**Target Platform**: macOS, Linux, Windows (WSL2 / Git Bash)
**Project Type**: Claude Code plugin / CLI tool
**Performance Goals**: Hook invocation ≤ 500ms (NFR-002, current baseline preserved)
**Scale/Scope**: 6,500 lines shell → TypeScript across 6 phases

## Constitution Check

| Gate | Status | Notes |
|---|---|---|
| Spec committed before code | PASS | This plan IS the spec artifact |
| FRs reference spec FRs | PASS | All 15 wheel FRs inherited from `specs/wheel/spec.md` |
| Interface contracts before impl | PENDING | `contracts/interfaces.md` Phase 1 output |
| ≥80% test coverage | PENDING | Vitest unit tests, Phase 4 |
| E2E tests exist | PASS | `kiln:test` (4 fixtures) + `wheel-test` (12 workflows) |

## Project Structure

### Source (TypeScript)

```text
plugin-wheel/
├── src/
│   ├── shared/                 # Shared utilities
│   │   ├── jq.ts              # jq wrapper: query, update, exists
│   │   ├── state.ts           # state read/write/validate
│   │   ├── fs.ts              # atomic write, tmp file, path utils
│   │   ├── error.ts           # WheelError, StateNotFound, Validation
│   │   └── index.ts           # re-exports
│   ├── hooks/                 # Hook entry points (6 handlers)
│   │   ├── post-tool-use.ts
│   │   ├── stop.ts
│   │   ├── teammate-idle.ts
│   │   ├── subagent-start.ts
│   │   ├── subagent-stop.ts
│   │   └── session-start.ts
│   ├── lib/                   # Core wheel logic
│   │   ├── state.ts           # typed state operations
│   │   ├── engine.ts          # kickstart, cursor advance
│   │   ├── dispatch.ts        # agent dispatch, team wait/delete
│   │   ├── workflow.ts        # workflow parse, step lookup
│   │   ├── context.ts         # context_build
│   │   ├── guard.ts           # resolve_state_file, ownership
│   │   ├── lock.ts            # mkdir-based locking
│   │   ├── log.ts             # wheel log
│   │   ├── preprocess.ts      # preprocess_workflow
│   │   ├── registry.ts        # agent registry
│   │   └── resolve_inputs.ts  # input resolution
│   ├── bin/                   # CLI tools
│   │   ├── validate-workflow.ts
│   │   ├── wheel-status.ts
│   │   ├── flag-needs-input.ts
│   │   └── wheel-log.ts
│   └── index.ts               # Main entry (routes by hook name)
├── dist/                      # Compiled output
├── hooks/                     # Shell shims (fallback only)
├── scripts/                   # Unchanged (harness, agents, render)
├── skills/                    # Unchanged
├── tests/                     # Unchanged (kiln:test fixtures)
├── package.json
├── tsconfig.json
└── vitest.config.ts
```

### Build Output

```
plugin-wheel/
├── dist/
│   ├── shared/                # shared utilities (importable by other plugins)
│   │   ├── jq.js
│   │   ├── state.js
│   │   ├── fs.js
│   │   ├── error.js
│   │   └── index.js
│   ├── hooks/                 # hook binaries invoked by Claude Code
│   │   ├── post-tool-use.js
│   │   ├── stop.js
│   │   └── ...
│   ├── lib/                   # compiled library
│   ├── bin/                   # compiled CLI tools
│   └── index.js
└── hooks/                     # shell shims only if node-direct fails
```

## Phase Plan

### Phase 0 — Project Setup + Hook Compatibility Testing
**Goal**: Confirm how Claude Code invokes hooks; scaffold project

1. Add `package.json`, `tsconfig.json`, `vitest.config.ts` to `plugin-wheel/`
2. Install `jsonc-parser` as only new dependency
3. Test: can `hooks/hooks.json` reference `node /path/to/dist/hook.js` directly?
4. If node-direct fails: create minimal shell shim (`#!/bin/sh` → `exec node ...`)
5. Create `src/index.ts` as routing entry point
6. Compile and verify `tsc` produces valid `dist/`

**Artifacts**: `package.json`, `tsconfig.json`, `vitest.config.ts`, `src/index.ts`, shell shims if needed

**Unknowns (NEEDS CLARIFICATION)**:
- Does Claude Code `hooks/hooks.json` invoke `node` directly? Will test in Phase 1.

### Phase 1 — Shared Utilities + Hook Entry Skeleton
**Goal**: `src/shared/` typed + all 6 hooks compilable

1. `src/shared/jq.ts` — typed wrappers for `jq` queries (`jqQuery<T>`, `jqUpdate`, `jqTest`)
2. `src/shared/state.ts` — `stateRead`, `stateWrite`, `stateValidate` (matches shell API)
3. `src/shared/fs.ts` — `atomicWrite`, `tmpFile`, `pathJoin` (cross-platform path)
4. `src/shared/error.ts` — `WheelError`, `StateNotFoundError`, `ValidationError`, `WorkflowError`
5. `src/shared/index.ts` — re-exports
6. `src/hooks/*.ts` — 6 hook entry points (stub until Phase 3)
7. `contracts/interfaces.md` — all function signatures

**Unit tests**: `src/shared/*.test.ts` with Vitest

### Phase 2 — State Layer
**Goal**: `src/lib/state.ts` typed and tested

1. Convert `lib/state.sh` (~608 lines) → `src/lib/state.ts`
2. Preserve: atomic write (tmp + mv), lock pattern, error codes, all `state_*` functions
3. Unit tests with mocked `.wheel/` directories
4. Integration test: create state, read it back, verify byte-for-byte identical schema

**Artifacts**: `src/lib/state.ts`, `tests/unit/state.test.ts`

### Phase 3 — Hook Entry Points (Full Implementation)
**Goal**: All 6 hooks fully implemented in TypeScript

1. `src/hooks/post-tool-use.ts` — full implementation (FR-022/023 logging, activate intercept)
2. `src/hooks/stop.ts` — full stop handler (FR-004)
3. `src/hooks/teammate-idle.ts` — full teammate idle (FR-005)
4. `src/hooks/subagent-start.ts` — subagent start (FR-006)
5. `src/hooks/subagent-stop.ts` — subagent stop (FR-007)
6. `src/hooks/session-start.ts` — session start with resume (FR-008)

**Integration test**: Verify all hooks fire correctly in `kiln:test` harness

### Phase 4 — Core Engine
**Goal**: `src/lib/engine.ts` + `src/lib/dispatch.ts` typed and tested

1. `src/lib/engine.ts` (~358 lines) — `engine_kickstart`, step routing, block/continue
2. `src/lib/dispatch.ts` (~2513 lines) — `dispatch_agent`, `dispatch_command`, `dispatch_loop`, `dispatch_branch`, `dispatch_team_wait`, `dispatch_team_delete`
3. `src/lib/workflow.ts` (~917 lines) — workflow parsing, step lookup, validation
4. Remaining `src/lib/*.ts` — guard, lock, log, preprocess, registry, resolve_inputs, context

**Unit tests**: Pure functions in engine + dispatch

### Phase 5 — Integration + Full Test Pass
**Goal**: All tests green

1. `npm run test:harness` — all 4 `kiln:test` fixtures pass
2. `/wheel:wheel-test` — all 12 `wheel-test` workflows pass
3. No regression vs shell version (behavior identical)
4. Hook invocation latency ≤ 500ms

**Artifacts**: Final integration test report

### Phase 6 — Shared Utilities Accessibility
**Goal**: Other plugins can import from wheel's dist/shared/

1. Verify `exports` field in `package.json` exposes `dist/shared/`
2. Document import instructions in `docs/features/2026-04-29-wheel-typescript-rewrite/PRD.md`
3. Smoke test: verify kiln or shelf can import shared utilities

## Hook Invocation Compatibility

The critical unknown is how Claude Code invokes hook commands. Three paths:

**Path A (preferred)**: Claude Code invokes directly via `execve`:
```json
{ "command": "node /path/to/dist/hooks/post-tool-use.js" }
```

**Path B (fallback)**: Claude Code wraps in `/bin/sh`:
```json
{ "command": "bash /path/to/dist/hooks/post-tool-use.js" }
```
Requires shebang: `#!/usr/bin/env node`

**Path C (guaranteed)**: Explicit shell wrapper:
```sh
#!/bin/sh
exec node /path/to/dist/hooks/post-tool-use.js "$@"
```
```json
{ "command": "bash /path/to/hooks/post-tool-use.sh" }
```

Phase 1 tests Path A first. If it fails, we know immediately which fallback to implement.

## Cross-Platform Concerns

| Concern | Shell approach | TypeScript approach |
|---|---|---|
| Line endings | `sed -i` behaves differently | Use `\n` only; normalize on read |
| Path separator | Hardcoded `/` | `path.join()` always |
| `mktemp` | Unix-only | `os.tmpdir()` + `crypto.randomUUID()` |
| Exit codes | `exit 1` | `process.exit(1)` |
| Env var reading | `$VAR` | `process.env.VAR ?? ''` |
| jq dependency | External binary | Wrapped via `child_process.spawn` or pure JS reimplementation |

**jq strategy**: Phase 1 evaluates two options:
1. `child_process.spawn('jq', ...)` — existing binary required
2. Pure JS JSON path (e.g., `jsonpath-plus`) — no external dependency

Option 2 is preferred but `jq` is already listed as an NFR dependency in `specs/wheel/spec.md`. Decision deferred to Phase 1 testing.

## Complexity Tracking

No violations of the constitution are anticipated. Single project, focused scope, incremental phases.

## Open Items

1. **jq binary vs pure JS** — test in Phase 1; both approaches viable
2. **Shell shim permanence** — decide after Phase 1 hook compatibility test
3. **CI Windows matrix** — WSL2 vs GitHub Actions Windows runner vs manual