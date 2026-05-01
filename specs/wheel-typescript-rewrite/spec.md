# Feature Specification: Wheel TypeScript Rewrite

**Feature Branch**: `build/wheel-typescript-rewrite-20260429`
**Created**: 2026-04-29
**Status**: Draft
**Parent Spec**: `specs/wheel/spec.md` (FR-001–FR-028)
**PRD**: `docs/features/2026-04-29-wheel-typescript-rewrite/PRD.md`

## User Scenarios & Testing

### User Story 1 - Preserve All Existing Wheel Behavior (Priority: P1)

As a plugin developer and workflow author, I want every existing workflow to continue working unchanged after the rewrite, so my pipelines are not disrupted.

**Why this priority**: This is the entire constraint of the rewrite — zero regression. If any existing behavior changes, the rewrite fails its primary mandate.

**Independent Test**: Run all 12 `wheel-test` workflows against the TypeScript implementation. Run all 4 `kiln:test` harness fixtures. Compare outputs against shell baseline.

**Acceptance Scenarios**:

1. **Given** a linear 3-step agent workflow, **When** executed via the TypeScript hooks, **Then** all 3 steps complete in order with identical state.json schema as the shell version
2. **Given** a parallel fan-out/fan-in step, **When** all agents complete, **Then** the TypeScript engine detects fan-in via mkdir-based locking and advances the cursor
3. **Given** a session that ends mid-step, **When** resumed via `SessionStart(resume)`, **Then** the TypeScript engine reads state.json and resumes from the correct step
4. **Given** a `PostToolUse(Bash)` event during an agent step, **When** the hook fires, **Then** the command is appended to the step's `command_log` in state.json
5. **Given** a `type: command` step, **When** the engine reaches it, **Then** the shell command executes inline, output/exit_code/timestamp are recorded, and the cursor advances without LLM involvement

---

### User Story 2 - Cross-Platform Execution (Priority: P1)

As a developer on Windows, Linux, or macOS, I want wheel workflows to run without a bash dependency, so I don't need Git Bash or WSL just to use wheel.

**Why this priority**: Platform lock-in was a stated problem in the PRD. The Node.js runtime is already required by Claude Code, making it the natural cross-platform substrate.

**Independent Test**: Invoke `node dist/hooks/post-tool-use.js` directly (bypassing shell shim) on each platform with valid hook input. Verify it produces identical output to the shell version.

**Acceptance Scenarios**:

1. **Given** Claude Code invokes `node dist/hooks/post-tool-use.js` directly, **When** valid hook JSON is passed on stdin, **Then** the hook produces the correct JSON response and exits 0
2. **Given** the Node.js binary is available but bash is not (simulated), **When** `node dist/hooks/*.js` is invoked, **Then** all 6 hooks return valid responses and update state.json correctly
3. **Given** Windows Git Bash with node available, **When** the workflow runs, **Then** state.json schema matches the shell version byte-for-byte

---

### User Story 3 - Shared Utilities Importable by Other Plugins (Priority: P2)

As a kiln or shelf developer, I want to import wheel's typed jq wrappers, state operations, and error types from `plugin-wheel/dist/shared/`, so I can eliminate the copy-pasted jq wrappers that currently exist in those plugins.

**Why this priority**: Eliminates the repeated logic problem cited in the PRD. Kiln and shelf both have jq-wrapping code that should be shared.

**Independent Test**: Import `jq.ts`, `state.ts`, `fs.ts`, `error.ts` from `plugin-wheel/dist/shared/` in a test file. Verify TypeScript compiles without errors and runtime behavior matches shell equivalents.

**Acceptance Scenarios**:

1. **Given** `plugin-wheel/dist/shared/jq.js` is published to npm, **When** kiln imports `jqQuery()` with valid JSON and a jq path, **Then** the result matches the shell `jq` output for the same inputs
2. **Given** `plugin-wheel/dist/shared/error.js` is imported, **When** a state operation fails, **Then** a `WheelError` subclass is thrown with `code` and `context` fields
3. **Given** `plugin-wheel/dist/shared/fs.js` is imported, **When** `atomicWrite()` is called, **Then** the file is written atomically (write-to-tmp-then-mv) and no partial file is readable on disk

---

### User Story 4 - Unit-Testable Core Logic (Priority: P2)

As a developer, I want the core wheel logic (dispatch, engine, state operations) to have unit tests, so I can catch regressions without running full integration tests.

**Why this priority**: The teammate_idle lookup priority bug (commit `4b4388f8`) was found via integration test, not unit test. Unit tests enable faster feedback.

**Independent Test**: Run `vitest` on `src/lib/` and `src/shared/`. Verify >=80% line and branch coverage on new TypeScript code.

**Acceptance Scenarios**:

1. **Given** `src/lib/state.test.ts` exists, **When** `stateGetCursor()`, `stateSetCursor()`, `stateSetStepStatus()` are tested with valid and invalid inputs, **Then** all assertions pass and coverage >= 80%
2. **Given** `src/lib/engine.test.ts` exists, **When** `engineCurrentStep()` is tested with workflow states (pending, running, complete), **Then** all assertions pass
3. **Given** `src/shared/jq.test.ts` exists, **When** `jqQuery()` and `jqUpdate()` are tested against known jq CLI outputs, **Then** all assertions pass
4. **Given** `src/lib/dispatch.test.ts` exists, **When** `dispatchAgent()`, `dispatchCommand()`, `dispatchWorkflow()` are tested with mocked state, **Then** all assertions pass

---

### User Story 5 - No Hook Latency Regression (Priority: P2)

As a workflow author, I want hook invocations to complete within 500ms, so the LLM is not idle waiting for wheel to respond.

**Why this priority**: NFR-002 of the existing wheel spec requires hook latency <= 500ms. The TypeScript rewrite must not regress this.

**Independent Test**: Profile hook invocations before and after. Measure wall-clock time from hook input received to JSON response written.

**Acceptance Scenarios**:

1. **Given** a cold-start `PostToolUse` hook invocation, **When** the TypeScript binary processes it, **Then** the total elapsed time is <= 500ms
2. **Given** a hot-path `PostToolUse` hook invocation (state already loaded), **When** the TypeScript binary processes it, **Then** the total elapsed time is <= 100ms

---

### Edge Cases

- What happens when state.json is corrupted or missing mid-workflow? TypeScript implementation should throw `StateNotFoundError` or `ValidationError`, matching shell behavior.
- What happens when two `SubagentStop` hooks fire simultaneously for the same parallel step? mkdir-based locking in `lock.ts` must prevent double-advance.
- What happens when jq returns a parse error? TypeScript implementation throws `ValidationError` with context.
- What happens when the Node.js binary is not available? Shell shim fallback handles this in Phase 1.
- What happens when `plugin-wheel/dist/shared/` is not yet published and another plugin imports it? npm dependency chain must be resolved before Phase 6.

## Requirements

### Functional Requirements

**Preservation (carries all 15 wheel FRs from specs/wheel/spec.md)**

- **FR-001**: All 6 hook handlers (`PostToolUse`, `Stop`, `TeammateIdle`, `SubagentStart`, `SubagentStop`, `SessionStart`) in `src/hooks/*.ts` MUST behave identically to the shell versions in `hooks/*.sh`
- **FR-002**: State file schema at `.wheel/state_*.json` MUST be byte-for-byte identical to the shell-generated schema. No new fields, no removed fields, no type changes.
- **FR-003**: `workflow.json` schema unchanged — all step types (`agent`, `command`, `parallel`, `approval`, `branch`, `loop`, `workflow`, `team-create`, `teammate`, `team-wait`, `team-delete`) work identically
- **FR-004**: `hooks/hooks.json` compatible with the plugin auto-merge system — references `dist/hooks/*.js` binaries after build

**TypeScript Implementation**

- **FR-005**: `src/shared/` contains typed wrappers for jq operations, state persistence, atomic fs writes, and custom error types
- **FR-006**: `src/lib/` contains TypeScript ports of all `lib/*.sh` functions: `state.ts`, `engine.ts`, `dispatch.ts`, `workflow.ts`, `context.ts`, `guard.ts`, `lock.ts`, `log.ts`, `preprocess.ts`, `registry.ts`, `resolve_inputs.ts`
- **FR-007**: `src/hooks/` contains one TypeScript file per hook type, each routing to the appropriate `src/lib/` function
- **FR-008**: `src/index.ts` serves as the entry point, routing by hook name from CLI arguments

**Cross-Platform**

- **FR-009**: Windows: works via `node dist/hooks/*.js` binary (WSL2 or Git Bash shell). If Claude Code does not natively invoke `node` binaries, a shell shim in `hooks/*.sh` acts as a fallback
- **FR-010**: All file I/O uses Node.js `fs` module (no shell command substitution)

**Testing**

- **FR-011**: All 4 `kiln:test` fixtures pass with TypeScript implementation (no regression vs shell baseline)
- **FR-012**: All 12 `wheel-test` workflows pass with TypeScript implementation
- **FR-013**: Unit tests for `src/shared/` (Vitest) achieve >=80% line and branch coverage
- **FR-014**: Unit tests for `src/lib/state.ts`, `src/lib/engine.ts`, `src/lib/dispatch.ts` achieve >=80% line and branch coverage

**Shared Library**

- **FR-015**: `src/shared/` is properly typed with TypeScript interfaces and exported via `src/shared/index.ts`
- **FR-016**: Kiln or shelf can import shared utilities from `plugin-wheel/dist/shared/` via npm dependency
- **FR-017**: Hook invocation latency <= current baseline (500ms NFR-002)

**Build & Packaging**

- **FR-018**: `tsconfig.json` with strict mode enabled, `tsc` compiles `src/` to `dist/`
- **FR-019**: `package.json` with scripts: `build`, `test`, `test:unit`, `test:harness`
- **FR-020**: npm package published to npm registry with `dist/shared/` as a named export

### Key Entities

- **StateFile**: JSON file at `.wheel/state_*.json` — schema preserved verbatim from shell. Contains `workflow_name`, `workflow_version`, `workflow_file`, `workflow_definition`, `status`, `cursor`, `owner_session_id`, `owner_agent_id`, `started_at`, `updated_at`, `steps[]`, `teams{}`, `session_registry`.
- **WorkflowDefinition**: JSON file in `workflows/` directory — schema unchanged. Contains `name`, `version`, `requires_plugins`, `steps[]`.
- **Step**: A single unit of work. Types: `agent`, `command`, `parallel`, `approval`, `branch`, `loop`, `workflow`, `team-create`, `teammate`, `team-wait`, `team-delete`.
- **SharedTypes**: TypeScript interfaces for `WheelState`, `Step`, `Agent`, `CommandLogEntry`, `Team`, `Teammate`, `WorkflowDefinition`, `ResolvedInputs`, `HookInput`, `HookOutput`.
- **ErrorTypes**: TypeScript error classes: `WheelError`, `StateNotFoundError`, `ValidationError`, `LockError`.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All 4 `kiln:test` harness fixtures pass with TypeScript implementation — verified via `npm run test:harness`
- **SC-002**: All 12 `wheel-test` workflows pass with TypeScript implementation — verified via `/wheel:wheel-test`
- **SC-003**: `src/shared/` is importable by another plugin via npm — verified by a test import in `plugin-kiln` or `plugin-shelf`
- **SC-004**: State file schema is byte-for-byte identical — verified by diffing shell-generated and TypeScript-generated state files for the same workflow
- **SC-005**: Hook invocation latency <= 500ms on cold start, <= 100ms on hot path — verified by profiling before/after comparison
- **SC-006**: Unit test coverage >= 80% on `src/shared/` and `src/lib/state.ts`, `engine.ts`, `dispatch.ts` — verified by `vitest --coverage`

## Assumptions

- Claude Code plugin system natively invokes hook commands via `hooks/hooks.json` — the `type: "command"` form supports both shell and Node.js binaries
- Node.js 20+ is available on all target platforms (it is a Claude Code prerequisite)
- The npm dependency chain (`plugin-wheel` → other plugins importing `dist/shared/`) is resolved before Phase 6
- The existing `workflow.json` schema does not require jq for parsing in TypeScript — `JSON.parse()` replaces `jq` for reading workflow files
- TypeScript strict mode is enabled without breaking changes to the existing behavior
- The shell shim (`hooks/*.sh`) is used only as a Phase 1 fallback while testing whether Claude Code natively invokes `node` binaries
