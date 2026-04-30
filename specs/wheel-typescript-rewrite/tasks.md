---

description: "Task breakdown for Wheel TypeScript Rewrite"
---

# Tasks: Wheel TypeScript Rewrite

**Input**: Design documents from `specs/002-wheel-ts-rewrite/`
**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `contracts/interfaces.md`
**Feature**: `002-wheel-ts-rewrite`
**Parent Spec**: `specs/wheel/spec.md` (FR-001–FR-028)

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: User story label (US1–US5), or setup/foundational/polish phases have no story label
- Include exact file paths in descriptions
- Include `// FR-NNN` comment on every new/changed function
- Include scenario reference comment on every new/changed test

## Phase 1: Project Setup

**Purpose**: TypeScript project configuration and build tooling

- [ ] T001 Create `plugin-wheel/tsconfig.json` with `"strict": true`, `"target": "ES2022"`, `"module": "NodeNext"`, `"outDir": "dist"`, `"rootDir": "src"`, `"declaration": true`, `"sourceMap": true` (FR-018)
- [ ] T002 Create `plugin-wheel/package.json` with `"name": "@yoshisada/wheel"`, `"version": "1.0.0"`, scripts: `build`, `test`, `test:unit`, `test:harness` (FR-019)
- [ ] T003 Create `plugin-wheel/src/index.ts` unified CLI router per `contracts/interfaces.md §16` (FR-008)

---

## Phase 2: Shared Utilities — `src/shared/` (FR-005)

**Purpose**: Cross-plugin importable TypeScript utilities. Zero dependencies on `src/lib/` or `src/hooks/`.

**Independent Test**: `vitest run src/shared/` passes with >=80% coverage. Kiln or shelf can import `jq.ts`, `state.ts`, `fs.ts`, `error.ts` from `dist/shared/` without TypeScript errors.

### Implementation

- [ ] T004 [P] Write `plugin-wheel/src/shared/error.ts` — `WheelError`, `StateNotFoundError`, `ValidationError`, `LockError` classes per `contracts/interfaces.md §4` (FR-005)
- [ ] T005 [P] Write `plugin-wheel/src/shared/fs.ts` — `atomicWrite`, `mkdirp`, `fileRead`, `fileExists` per `contracts/interfaces.md §2` (FR-005, FR-010)
- [ ] T006 [P] Write `plugin-wheel/src/shared/jq.ts` — `jqQuery<T>`, `jqQueryRaw`, `jqUpdate` per `contracts/interfaces.md §1` (FR-005, FR-010)
- [ ] T007 [P] Write `plugin-wheel/src/shared/state.ts` — `stateRead`, `stateWrite` per `contracts/interfaces.md §3` (FR-005, FR-002)
- [ ] T008 [P] Write `plugin-wheel/src/shared/index.ts` — barrel export of all shared utilities (FR-015)
- [ ] T009 [P] Write `plugin-wheel/src/shared/*.test.ts` — Vitest unit tests for jq, fs, state, error modules. Target >=80% line + branch coverage. Each test file MUST have a `// Scenario: <N>` comment referencing the acceptance scenario it validates (FR-013, FR-005)

**Checkpoint**: Phase 2 complete — `src/shared/` compiles and all unit tests pass.

---

## Phase 3: State Layer — `src/lib/state.ts` (FR-002, FR-006)

**Purpose**: Typed port of `lib/state.sh`. All state read-modify-write operations on `.wheel/state_*.json`.

**Independent Test**: `vitest run src/lib/state.test.ts` passes with >=80% coverage. State file schema is byte-for-byte identical to shell-generated state files for the same workflow.

### Implementation

- [ ] T010 Write `plugin-wheel/src/lib/state.ts` — all exported functions matching `contracts/interfaces.md §5`: `stateInit`, `stateGetCursor`, `stateSetCursor`, `stateGetStepStatus`, `stateSetStepStatus`, `stateGetAgentStatus`, `stateSetAgentStatus`, `stateSetStepOutput`, `stateAppendCommandLog`, `stateGetCommandLog`, `stateSetTeam`, `stateGetTeam`, `stateAddTeammate`, `stateUpdateTeammateStatus`, `stateGetTeammates`, `stateRemoveTeam`, `stateSetAwaitingUserInput`, `stateClearAwaitingUserInput`, `stateSetResolvedInputs`, `stateSetContractEmitted`, `stateGetContractEmitted` (FR-006, FR-002, FR-009)
- [ ] T011 Write `plugin-wheel/src/lib/state.test.ts` — Vitest unit tests for all state operations. Target >=80% coverage. Each test MUST have a `// Scenario: <N>` comment referencing the acceptance scenario it validates (FR-014)
- [ ] T012 Verify state schema byte-for-byte identity: run a workflow against shell version, run same workflow against TypeScript version, diff both `.wheel/state_*.json` files — no differences (FR-002, SC-004)

**Checkpoint**: Phase 3 complete — state layer tests pass and schema identity verified.

---

## Phase 4: Hook Entry Points — `src/hooks/*.ts` (FR-001, FR-007)

**Purpose**: Six standalone CLI hook handlers. Each reads hook JSON from stdin, calls `engineHandleHook`, writes JSON to stdout.

**Independent Test**: Each hook binary (`dist/hooks/*.js`) responds correctly to valid Claude Code hook input. All 6 hooks fire without error.

### Implementation

- [ ] T013 [P] Write `plugin-wheel/src/hooks/post-tool-use.ts` — `type: "command"` entry point per `contracts/interfaces.md §15` (FR-007, FR-001)
- [ ] T014 [P] Write `plugin-wheel/src/hooks/stop.ts` — Stop hook entry point (FR-007, FR-001)
- [ ] T015 [P] Write `plugin-wheel/src/hooks/teammate-idle.ts` — TeammateIdle hook entry point (FR-007, FR-001)
- [ ] T016 [P] Write `plugin-wheel/src/hooks/subagent-start.ts` — SubagentStart hook entry point (FR-007, FR-001)
- [ ] T017 [P] Write `plugin-wheel/src/hooks/subagent-stop.ts` — SubagentStop hook entry point (FR-007, FR-001)
- [ ] T018 [P] Write `plugin-wheel/src/hooks/session-start.ts` — SessionStart (resume) hook entry point (FR-007, FR-001)
- [ ] T019 Hook invocation test: invoke `node dist/hooks/post-tool-use.js` directly with valid stdin JSON — verify exits 0, produces valid `HookOutput` JSON (FR-009, SC-002)
- [ ] T020 If native node invocation fails: write `plugin-wheel/hooks/*.sh` shell shims as Phase 1 fallback per `plan.md` (FR-009)

**Checkpoint**: Phase 4 complete — all 6 hooks compile, run, and produce valid output.

---

## Phase 5: Core Engine + Dispatch — `src/lib/` (FR-003, FR-006, FR-007)

**Purpose**: TypeScript ports of all `lib/*.sh` functions. Engine kickstart, cursor advance, step routing.

**Independent Test**: `vitest run src/lib/engine.test.ts src/lib/dispatch.test.ts` passes with >=80% coverage. 3-step linear workflow completes end-to-end.

### Implementation

- [ ] T021 [P] Write `plugin-wheel/src/lib/workflow.ts` — `workflowLoad`, `workflowGetStep`, `workflowStepCount`, `workflowGetBranchTarget` per `contracts/interfaces.md §8` (FR-006)
- [ ] T022 [P] Write `plugin-wheel/src/lib/lock.ts` — `acquireLock`, `releaseLock`, `withLock` using mkdir semantics per `contracts/interfaces.md §10` (FR-006)
- [ ] T023 [P] Write `plugin-wheel/src/lib/preprocess.ts` — `preprocess` for `${WHEEL_PLUGIN_*}` and `${WORKFLOW_PLUGIN_DIR}` token substitution per `contracts/interfaces.md §12` (FR-006)
- [ ] T024 [P] Write `plugin-wheel/src/lib/registry.ts` — `buildSessionRegistry`, `resolvePluginPath` per `contracts/interfaces.md §13` (FR-006)
- [ ] T025 [P] Write `plugin-wheel/src/lib/log.ts` — hook event logging (FR-006)
- [ ] T026 [P] Write `plugin-wheel/src/lib/engine.ts` — `engineInit`, `engineKickstart`, `engineCurrentStep`, `engineHandleHook` per `contracts/interfaces.md §6` (FR-006, FR-001)
- [ ] T027 [P] Write `plugin-wheel/src/lib/context.ts` — `contextBuild` per `contracts/interfaces.md §9` (FR-006)
- [ ] T028 [P] Write `plugin-wheel/src/lib/guard.ts` — `guardCheck` per `contracts/interfaces.md §11` (FR-006, FR-004/FR-005)
- [ ] T029 Write `plugin-wheel/src/lib/resolve_inputs.ts` — `resolveInputs` per `contracts/interfaces.md §14` (FR-006)
- [ ] T030 Write `plugin-wheel/src/lib/dispatch.ts` — all dispatch functions: `dispatchStep`, `dispatchAgent`, `dispatchCommand`, `dispatchWorkflow`, `dispatchTeamCreate`, `dispatchTeammate`, `dispatchTeamWait`, `dispatchTeamDelete`, `dispatchBranch`, `dispatchLoop`, `dispatchParallel`, `dispatchApproval`, `_hydrateAgentStep` per `contracts/interfaces.md §7` (FR-006, FR-003)
- [ ] T031 [P] Write `plugin-wheel/src/lib/engine.test.ts` — Vitest unit tests for engine functions. Target >=80% coverage. Each test MUST have a `// Scenario: <N>` comment (FR-014)
- [ ] T032 [P] Write `plugin-wheel/src/lib/dispatch.test.ts` — Vitest unit tests for dispatch functions. Target >=80% coverage. Each test MUST have a `// Scenario: <N>` comment (FR-014)
- [ ] T033 Integration verify: 3-step linear agent workflow completes end-to-end via TypeScript engine, no errors (FR-003, SC-001)

**Checkpoint**: Phase 5 complete — engine + dispatch compile and unit tests pass.

---

## Phase 6: Full Integration — `kiln:test` + `wheel-test` (FR-011, FR-012, FR-017)

**Purpose**: Zero-regression integration verification. All 4 harness fixtures + all 12 wheel-test workflows must pass.

**Independent Test**: `npm run test:harness` passes. `/wheel:wheel-test` passes.

### Implementation

- [ ] T034 Run all 4 `kiln:test` harness fixtures against TypeScript implementation — verify no regression vs shell baseline (FR-011, SC-001)
- [ ] T035 Run all 12 `wheel-test` workflows against TypeScript implementation — verify no regression vs shell baseline (FR-012, SC-002)
- [ ] T036 Hook latency profiling: measure wall-clock time from hook input received to JSON response written. Cold start <= 500ms, hot path <= 100ms (FR-017, SC-005)
- [ ] T037 State schema diff: run a complex workflow with branching and loops against both shell and TypeScript versions. Diff the resulting `.wheel/state_*.json` files — zero differences (FR-002, SC-004)

**Checkpoint**: Phase 6 complete — all integration tests pass, no regression.

---

## Phase 7: Shared Library Accessibility (FR-015, FR-016, FR-020)

**Purpose**: `src/shared/` is properly typed, exported, and importable by other plugins via npm.

**Independent Test**: `npm pack --dry-run` succeeds. Kiln or shelf can `import { jqQuery } from '@yoshisada/wheel/shared'` without TypeScript errors.

### Implementation

- [ ] T038 Update `plugin-wheel/package.json` with npm package configuration: `exports` field mapping `dist/shared/` as named export, `main`: `dist/index.js`, `types`: `dist/index.d.ts` (FR-020)
- [ ] T039 Document import instructions in `plugin-wheel/README.md` — how other plugins import shared utilities from `@yoshisada/wheel/shared` (FR-016)
- [ ] T040 Smoke test: write a test file in `plugin-kiln` that imports shared utilities from `plugin-wheel/dist/shared/` — verify TypeScript compiles without errors (FR-016, SC-003)
- [ ] T041 npm publish dry-run: `npm publish --dry-run --access public` — verify package structure is correct (FR-020)

**Checkpoint**: Phase 7 complete — npm package is publishable and importable.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1**: No dependencies — start immediately
- **Phase 2 (src/shared/)**: Depends on Phase 1 — BLOCKS all subsequent phases
- **Phase 3 (src/lib/state.ts)**: Depends on Phase 2
- **Phase 4 (src/hooks/*.ts)**: Depends on Phase 3 (needs state + engine for routing)
- **Phase 5 (src/lib/*.ts)**: Depends on Phase 3 and Phase 4 — core engine + dispatch need state layer and hook routing
- **Phase 6 (integration)**: Depends on Phase 5
- **Phase 7 (shared library)**: Depends on Phase 2 — verifies `src/shared/` is npm-ready

### User Story Mapping

| Phase | User Story | Priority |
|-------|-----------|----------|
| Phase 2 (src/shared/) | US3 — Shared Utilities Importable | P2 |
| Phase 3 (state) | US1 — Preserve Existing Behavior | P1 |
| Phase 4 (hooks) | US1 + US2 — Hook Compatibility | P1 |
| Phase 5 (engine + dispatch) | US1 — Preserve Existing Behavior | P1 |
| Phase 6 (integration) | US1 + US4 — Full Integration + Unit Testability | P1, P2 |
| Phase 7 (shared library) | US3 — Shared Library Accessibility | P2 |
| Cross-cutting | US2 — Cross-Platform Execution | P1 |
| Cross-cutting | US5 — No Hook Latency Regression | P2 |

### Parallel Opportunities

- **T004–T008**: All 5 `src/shared/` modules can be written in parallel (no circular imports, shared module has zero deps on lib/hooks)
- **T013–T018**: All 6 hook files can be written in parallel (each is a standalone CLI)
- **T021–T028**: All `src/lib/` files except dispatch.ts and resolve_inputs.ts can be written in parallel
- **T031–T032**: Both test files can be written in parallel after implementation

---

## Independent Test Criteria

| Phase | Criterion |
|-------|-----------|
| Phase 2 | `vitest run src/shared/` passes, coverage >=80%, another plugin can import shared utilities |
| Phase 3 | `vitest run src/lib/state.test.ts` passes, coverage >=80%, state schema identical |
| Phase 4 | `node dist/hooks/*.js` each respond to valid input, all 6 exit 0 |
| Phase 5 | `vitest run src/lib/engine.test.ts src/lib/dispatch.test.ts` pass, coverage >=80%, 3-step linear workflow completes |
| Phase 6 | All 4 `kiln:test` fixtures pass, all 12 `wheel-test` workflows pass, no regression |
| Phase 7 | npm pack dry-run succeeds, shared utilities importable by kiln or shelf |

---

## Notes

- All FRs from `spec.md` are covered: FR-001–FR-020 across phases
- All 15 existing wheel FRs (FR-001–FR-028 from `specs/wheel/spec.md`) are preserved via FR-001/FR-002/FR-003
- `contracts/interfaces.md` pre-existed with exact signatures — tasks map 1:1 to contracts
- TypeScript `strict: true` enforced from Phase 1 — no `any` types allowed
- `src/shared/` invariant (zero imports from `src/lib/` or `src/hooks/`) enforced by project references in tsconfig
- Shell shims (`hooks/*.sh`) are Phase 1 fallback only — test native `node` invocation first
