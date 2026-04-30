# Implementation Plan: Wheel TypeScript Rewrite

**Branch**: `002-wheel-ts-rewrite` | **Date**: 2026-04-29 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/002-wheel-ts-rewrite/spec.md`
**Parent**: `specs/wheel/spec.md` (FR-001–FR-028)

## Summary

Rewrite `plugin-wheel` from ~6,500 lines of shell to TypeScript with Node.js runtime. Preserve all 6 hooks, all 11 step types, identical state file schema, and all integration test fixtures. Create `src/shared/` for cross-plugin code reuse (jq wrappers, state ops, fs utils, errors). Enable unit testing of core logic. All 15 existing wheel FRs are carried forward.

## Technical Context

**Language/Version**: TypeScript (strict mode), Node.js 20+
**Primary Dependencies**: `fs/promises`, `child_process`, `path`, no external npm deps beyond TypeScript
**Storage**: Filesystem — `.wheel/state_*.json` (unchanged schema), workflow JSON files
**Testing**: Vitest (unit, >=80% coverage gate), `kiln:test` harness (integration, 4 fixtures), `wheel-test` (12 workflows)
**Target Platform**: Linux, macOS, Windows (via Git Bash / WSL2 with `node` binary)
**Project Type**: CLI plugin with hook entry points
**Performance Goals**: Hook invocation <= 500ms cold, <= 100ms hot path (NFR-002)
**Constraints**: Zero regression on existing behavior; all 15 wheel FRs preserved; state schema byte-for-byte identical

## Constitution Check

| Gate | Status | Notes |
|------|--------|-------|
| **§I — Spec-first** | ✅ PASS | `spec.md` committed before any `src/` work |
| **§II — 80% coverage** | ✅ PASS | FR-013, FR-014 mandate >=80% on `src/shared/` and `src/lib/` |
| **§III — PRD source of truth** | ✅ PASS | PRD is parent; no spec contradictions |
| **§IV — Hooks enforce rules** | ✅ PASS | Hooks unchanged for consumers |
| **§V — E2E testing** | ✅ PASS | `kiln:test` + `wheel-test` are E2E integration tests |
| **§VI — Small focused changes** | ✅ PASS | 6 phased tasks, each bounded by module |
| **§VII — Interface contracts** | ✅ PASS | `contracts/interfaces.md` pre-existing with exact signatures |
| **§VIII — Incremental completion** | ✅ PASS | Tasks will be checked off one-at-a-time |

## Project Structure

### Documentation (this feature)

```
specs/002-wheel-ts-rewrite/
├── plan.md              # This file
├── spec.md              # User stories + FRs
├── tasks.md             # Phase-by-phase task breakdown (/tasks command output)
├── contracts/
│   └── interfaces.md    # Exact function signatures (pre-existing, complete)
└── checklists/
    └── requirements.md # Spec quality validation
```

### Source Code (plugin-wheel/)

```
plugin-wheel/
├── src/
│   ├── shared/                    # FR-005: Cross-plugin importable utilities
│   │   ├── index.ts                # Barrel export
│   │   ├── jq.ts                   # jqQuery, jqQueryRaw, jqUpdate (pure TS, no jq CLI)
│   │   ├── fs.ts                   # atomicWrite, mkdirp, fileRead, fileExists
│   │   ├── state.ts                # stateRead, stateWrite
│   │   └── error.ts                # WheelError, StateNotFoundError, ValidationError, LockError
│   ├── hooks/                     # FR-007: One file per hook type
│   │   ├── post-tool-use.ts
│   │   ├── stop.ts
│   │   ├── teammate-idle.ts
│   │   ├── subagent-start.ts
│   │   ├── subagent-stop.ts
│   │   └── session-start.ts
│   ├── lib/                        # FR-006: TypeScript ports of lib/*.sh
│   │   ├── state.ts                # stateInit, stateSetCursor, stateSetStepStatus, etc.
│   │   ├── engine.ts               # engineInit, engineKickstart, engineCurrentStep, engineHandleHook
│   │   ├── dispatch.ts             # dispatchAgent, dispatchCommand, dispatchWorkflow, etc.
│   │   ├── workflow.ts             # workflowLoad, workflowGetStep, etc.
│   │   ├── context.ts              # contextBuild
│   │   ├── guard.ts                # guardCheck
│   │   ├── lock.ts                 # acquireLock, releaseLock, withLock
│   │   ├── log.ts                  # Hook event logging
│   │   ├── preprocess.ts          # Token substitution (${WHEEL_PLUGIN_*} etc.)
│   │   ├── registry.ts             # buildSessionRegistry, resolvePluginPath
│   │   └── resolve_inputs.ts       # resolveInputs
│   └── index.ts                   # FR-008: Unified CLI router (optional)
├── dist/                          # tsc output (published to npm)
│   ├── shared/                    # npm-importable by other plugins
│   ├── hooks/                     # Referenced by hooks/hooks.json
│   └── lib/
├── hooks/                        # Shell shims (Phase 1 fallback only)
│   └── *.sh                       # Fallback if node binary not natively invoked
├── bin/                           # Unchanged CLI tools
├── skills/                        # Unchanged
├── tests/                         # Unchanged (kiln:test harness)
├── package.json                   # FR-018: build, test, test:unit, test:harness scripts
└── tsconfig.json                  # FR-018: strict mode
```

**Structure Decision**: All source lives under `plugin-wheel/src/`. `dist/` is the build output. `src/shared/` is the only cross-plugin interface. `src/shared/` has zero imports from `src/lib/` or `src/hooks/` (Invariant I-6 from contracts).

## Complexity Tracking

No constitution violations requiring justification.

## Research Notes

No NEEDS CLARIFICATION items — all unknowns resolved from existing shell implementation:

1. **jq replacement**: Pure TypeScript JSON traversal in `jq.ts` — no `jq` CLI dependency needed for reading state/workflow JSON. `jqQuery` uses recursive property access; `jqUpdate` returns a new JSON string.
2. **Hook invocation**: Shell shim (`hooks/*.sh`) acts as Phase 1 fallback. Test in Phase 1 whether Claude Code natively invokes `node` binaries.
3. **Atomic writes**: `fs.rename` on POSIX is atomic. On Windows, `atomicWrite` uses `fs.writeFile` to a temp path then `fs.rename` — same pattern as shell version.
4. **Locking**: `mkdir`-based locking (`lock.ts`) is portable — works on Linux, macOS, Windows Git Bash. `fs.mkdir` with `{ recursive: true }` and check for `EEXIST` on Windows.
5. **Cross-plugin import**: `src/shared/index.ts` exports all shared types. Published as part of `dist/shared/` in npm package. Other plugins add `plugin-wheel` as npm dependency.

## Phases

### Phase 1: Shared Utilities + Hook Compatibility (FR-005, FR-009, FR-010, FR-017)

1. Write `plugin-wheel/src/shared/jq.ts` — pure-TS jq wrappers (jqQuery, jqQueryRaw, jqUpdate)
2. Write `plugin-wheel/src/shared/fs.ts` — atomicWrite, mkdirp, fileRead, fileExists
3. Write `plugin-wheel/src/shared/error.ts` — WheelError, StateNotFoundError, ValidationError, LockError
4. Write `plugin-wheel/src/shared/state.ts` — stateRead, stateWrite
5. Write `plugin-wheel/src/shared/index.ts` — barrel export
6. Write unit tests: `src/shared/*.test.ts` (Vitest, >=80% coverage)
7. Write `plugin-wheel/tsconfig.json` (strict mode) and `package.json`
8. Compile `src/shared/` to `dist/shared/`
9. **Hook invocation test**: invoke `node dist/hooks/post-tool-use.js` directly with valid input. Does Claude Code natively invoke `node`?
10. If no native `node` support: write `hooks/*.sh` shell shims as Phase 1 fallback
11. Integration verify: shared utilities work standalone

### Phase 2: State Layer (FR-002, FR-006)

1. Write `plugin-wheel/src/lib/state.ts` — all state operations matching `lib/state.sh`
2. Write unit tests `src/lib/state.test.ts` (Vitest, >=80% coverage)
3. Integration verify: state read/write produces byte-for-byte identical schema vs shell version
4. Profile: state read latency <= 100ms for 100-step workflow

### Phase 3: Hook Entry Points (FR-001, FR-007)

1. Write all 6 `src/hooks/*.ts` files
2. Each hook reads stdin, calls `engineHandleHook`, writes JSON to stdout
3. Write `src/index.ts` optional unified router
4. Integration verify: all 6 hooks fire and respond correctly

### Phase 4: Core Engine + Dispatch (FR-003, FR-006)

1. Write `plugin-wheel/src/lib/workflow.ts` — workflowLoad, workflowGetStep, etc.
2. Write `plugin-wheel/src/lib/engine.ts` — engineInit, engineKickstart, engineCurrentStep, engineHandleHook
3. Write `plugin-wheel/src/lib/dispatch.ts` — all dispatch functions
4. Write `plugin-wheel/src/lib/context.ts` — contextBuild
5. Write `plugin-wheel/src/lib/guard.ts` — guardCheck
6. Write `plugin-wheel/src/lib/lock.ts` — acquireLock, releaseLock, withLock
7. Write `plugin-wheel/src/lib/log.ts` — hook event logging
8. Write `plugin-wheel/src/lib/preprocess.ts` — token substitution
9. Write `plugin-wheel/src/lib/registry.ts` — buildSessionRegistry, resolvePluginPath
10. Write `plugin-wheel/src/lib/resolve_inputs.ts` — resolveInputs
11. Unit tests for `src/lib/engine.test.ts`, `src/lib/dispatch.test.ts` (Vitest, >=80% coverage)
12. Integration verify: 3-step linear workflow completes

### Phase 5: Full Integration + Test Pass (FR-011, FR-012, FR-017)

1. Run all 4 `kiln:test` fixtures — verify no regression
2. Run all 12 `wheel-test` workflows — verify no regression
3. Hook latency profiling: <= 500ms cold, <= 100ms hot
4. State schema comparison: diff shell vs TypeScript outputs

### Phase 6: Shared Library Accessibility (FR-015, FR-016)

1. Verify `dist/shared/` exports are correct npm package
2. Document import instructions in `plugin-wheel/README.md`
3. Smoke test: import shared utilities from a test file in `plugin-kiln`
4. npm publish dry-run

## Key Files to Modify

| File | Change |
|------|--------|
| `plugin-wheel/src/shared/*.ts` | New — TypeScript ports |
| `plugin-wheel/src/hooks/*.ts` | New — TypeScript hook handlers |
| `plugin-wheel/src/lib/*.ts` | New — TypeScript engine ports |
| `plugin-wheel/src/index.ts` | New — unified router |
| `plugin-wheel/tsconfig.json` | New — TypeScript config |
| `plugin-wheel/package.json` | Update — add build scripts, npm config |
| `plugin-wheel/hooks/*.sh` | Update — shell shims (Phase 1 fallback) |
| `plugin-wheel/hooks/hooks.json` | Update — reference `dist/hooks/*.js` |

## Open Questions (answered by research)

| Question | Resolution |
|----------|------------|
| Do we keep shell shims permanently? | Phase 1 fallback. Test native `node` invocation; keep shims only if needed. |
| How do we publish? | Single npm package `@yoshisada/wheel` with `dist/shared/` as named export. |
| Windows compatibility? | `node` binary via Git Bash / WSL2 — Node.js is already a Claude Code prerequisite. |
