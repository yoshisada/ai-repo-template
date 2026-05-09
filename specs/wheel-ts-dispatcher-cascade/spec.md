# Feature Spec: Wheel TS Dispatcher Cascade — Inline Step Chaining for Parity with Shell

**Branch**: `build/wheel-ts-dispatcher-cascade-20260501`
**PRD**: `docs/features/2026-05-01-wheel-ts-dispatcher-cascade/PRD.md`
**Constitution**: `.specify/memory/constitution.md` (v2.0.0)
**Status**: Spec — pending plan

## 1. Overview

Add an **inline step cascade** to the TypeScript wheel dispatchers so that a sequence of auto-executable steps (`command`, `loop`, `branch`, plus child `workflow` activation) runs back-to-back inside a single hook invocation, halting only when it hits a blocking step type (`agent`, `team-create`, `teammate`, `team-wait`, `team-delete`, `parallel`, `approval`) or a terminal/failed step. This restores parity with the shell wheel's `dispatch_step` recursion and unblocks `/wheel:wheel-test` Phases 1–3 (currently 0/13 pass; baseline 60s phase timeouts).

This work folds into the in-progress `002-wheel-ts-rewrite` branch chain on top of the wait-all redesign (`build/wheel-wait-all-redesign-20260430`). The implementer **extends** existing dispatch.ts / post-tool-use.ts on this branch — the in-progress code is the foundation, not something to discard. No engine contract changes, no workflow-JSON schema changes, no shell-wheel changes.

## 2. User Stories (Given / When / Then)

### US-1 — Activation cascades through chained command steps
**Given** a workflow with three sequential `command` steps and `bash activate.sh <wf>.json` is the activation trigger,
**When** the activation `PostToolUse` hook fires,
**Then** all three command steps execute inside that single hook fire, the workflow archives to `.wheel/history/success/`, no orphan `state_*.json` remains, and wall-clock is < 5 s.

### US-2 — Cascade stops cleanly at a blocking step
**Given** a workflow `command → command → agent → command`,
**When** activation fires,
**Then** both `command` steps run inline, the cascade stops at the `agent` step (cursor=2, agent step=working, trailing `command` not executed), and the hook returns control. After the agent's output file is later written and the next `post_tool_use` hook fires, the trailing `command` runs inline and the workflow archives.

### US-3 — Cascade halts on step failure (no zombie advance)
**Given** a workflow `command(success) → command(fails) → command`,
**When** activation fires,
**Then** step 0 = done, step 1 = failed, step 2 stays pending (never dispatched), the workflow archives to `.wheel/history/failure/`, and no orphan state file remains.

### US-4 — Phase 1 / 2 / 3 of `/wheel:wheel-test` go green
**Given** the working-tree TS dist is deployed to the plugin cache,
**When** `/wheel:wheel-test` runs the full fixture set,
**Then** Phases 1–3 (`count-to-100`, `loop-test`, `team-sub-fail`, `agent-chain`, `branch-multi`, `command-chain`, `example`, `sync`, `team-sub-worker`, `composition-mega`) report 100 % pass with no orphan state files. Phase 4 fixtures' status is unchanged by this PRD.

### US-5 — Composition cascade enters the child workflow
**Given** a workflow whose step N is `type: workflow` (composition) and the child workflow's first step is auto-executable,
**When** the parent's cascade reaches step N,
**Then** the child workflow is activated, the child's first step cascades inside the child's state, the parent's cascade pauses (returns control to the hook), and when the child later archives the parent's cursor advances and the parent's cascade resumes on the next hook fire.

### US-6 — Internals reader sees a clear cascade tail
**Given** a developer opens `dispatchCommand` / `dispatchLoop` / `dispatchBranch` in TS source,
**When** they read the function,
**Then** they see an explicit "if next step is auto-executable, dispatch it; otherwise advance cursor and return" tail using a single `isAutoExecutable(step)` helper — no per-dispatcher type duplication, no surprise control flow.

## 3. Functional Requirements

Each FR maps directly to the PRD's FR-1 through FR-10 (same numbering for traceability).

### FR-001 — Auto-executable step type catalog (single source of truth)
A single helper, `isAutoExecutable(step: WorkflowStep): boolean`, MUST be the only classifier of auto-executable vs blocking step types. Catalog:
- **Auto-executable** (cascade continues): `command`, `loop`, `branch`.
- **Blocking** (cascade STOPS, returns control): `agent`, `team-create`, `teammate`, `team-wait`, `team-delete`, `parallel`, `approval`.
- **Composite** (cascade enters child): `workflow` — handled by `dispatchWorkflow`'s own cascade; the parent's cascade pauses on this step type and resumes on parent-cursor-advance after child archive.

No per-dispatcher type checks may duplicate this list. Acceptance: `git grep -nE "type === 'command'|type === 'loop'|type === 'branch'"` returns 0 hits inside the cascade tails (the helper is the only place that enumerates).

### FR-002 — `dispatchCommand` cascade tail
After `dispatchCommand` marks step `done` (success path) OR `failed` (error path):
1. If step is `terminal: true` OR was set `failed`: return without cascading. Engine archive logic handles termination.
2. Read fresh state.
3. Compute `nextIndex = cursor + 1`.
4. If `nextIndex >= state.steps.length`: advance cursor to `nextIndex` (so the engine's terminal-cursor archive trigger fires). Return.
5. Read `nextStep = state.steps[nextIndex]`.
6. **Advance cursor first** (idempotent retry contract — if dispatch then crashes, next hook fire dispatches the right step).
7. If `isAutoExecutable(nextStep)`: tail-call `dispatchStep(nextStep, hookType, hookInput, stateFile, nextIndex)`. Recurse.
8. Otherwise: return without recursing. The next hook fire will dispatch the blocking step.

### FR-003 — `dispatchLoop` cascade tail
Same shape as FR-002, with these boundaries:
- If the loop has just completed all iterations (`done` path): cascade as in FR-002.
- If the loop body skipped (`done` path with no iteration): cascade as in FR-002.
- If the loop is still iterating (substep type `command`, hasn't met max): the loop body runs as today — DO NOT cascade until the loop step itself becomes `done`/`failed`.
- If the loop's substep type is `agent`: blocking — return without cascade.

### FR-004 — `dispatchBranch` cascade tail
After `dispatchBranch` resolves the target step (FR-002 same shape, target index from existing `if_zero`/`if_nonzero` handling):
1. Mark current step `done`, mark off-target step `skipped` (existing behavior).
2. Set cursor to the target index (existing behavior).
3. Read `targetStep = state.steps[targetIndex]`.
4. If `isAutoExecutable(targetStep)`: tail-call `dispatchStep(targetStep, hookType, hookInput, stateFile, targetIndex)`. Recurse.
5. Else: return.

### FR-005 — `handleActivation` post-init cascade (replaces the manual kickstart loop)
The existing manual `while`-loop kickstart in `plugin-wheel/src/hooks/post-tool-use.ts handleActivation` (lines ~387–420) MUST be replaced with a single call to `dispatchStep(steps[0], 'post_tool_use', hookInput, stateFile, 0)` — provided step 0 is auto-executable. The cascade tail in the dispatchers (FR-002/003/004) handles the rest.

If step 0 is blocking: do NOT call dispatchStep here. Set cursor=0, return. The Stop / PostToolUse hook will handle dispatch on the next agent turn.

After cascade returns, `handleActivation` MUST NOT manually advance cursor — the dispatchers own that. After cascade returns, if cursor is terminal, run the same `maybeArchiveTerminalWorkflow` logic that `engineHandleHook` uses (extracted to a shared helper, OR called via `engineHandleHook`-equivalent post-dispatch path).

### FR-006 — Recursion bound (graceful cap)
Cascade depth is bounded by step count. Implementation MUST add an explicit depth parameter (default 0) to `dispatchStep` and reject (with a `wheel.log` warning + graceful return — NOT throw) when depth ≥ 1000. State at the in-flight cursor is preserved; the next hook fire resumes. No iteration-count cap — only cascade-recursion-depth cap.

### FR-007 — Hook-type pass-through
The cascade MUST pass the same `hookType` it received into the recursive `dispatchStep` call — no remapping. If `handleActivation` calls cascade with `'post_tool_use'`, every nested dispatch sees `'post_tool_use'`. If `engineHandleHook` calls dispatch with `'stop'` and that dispatch cascades, every nested dispatch sees `'stop'`.

### FR-008 — Failure semantics (cascade halts on `failed`)
If a cascaded dispatcher sets a step `failed`, the cascade MUST halt — no recursive call. The terminal-archive logic (engine + `maybeArchiveTerminalWorkflow`) detects the failure and archives to `.wheel/history/failure/`. Match shell behavior. Idempotency contract: cursor is advanced BEFORE the dispatch runs (FR-002 step 6 ordering), so a mid-dispatch crash leaves state at `{cursor=N, step[N].status=working}` and the next hook fire retries that step.

### FR-009 — Logging (`wheel.log` cascade events)
Every cascade transition MUST emit a `wheel.log` line (via existing `wheelLog(...)` helper from `plugin-wheel/src/lib/log.ts`) with these phases:
- `dispatch_cascade` — fields: `from_step_id`, `to_step_id`, `from_step_type`, `to_step_type`, `hook_type`, `state_file`. Emitted on each cascade hop.
- `dispatch_cascade_halt` — fields: `step_id`, `step_type`, `reason` (`blocking_step` | `terminal` | `failed` | `end_of_workflow` | `depth_cap`). Emitted once per cascade chain when it stops.
- `cursor_advance` — already-existing pattern; reuse if available, otherwise add. Fields: `from_cursor`, `to_cursor`, `state_file`.

These lines are the debugging breadcrumb trail — a reviewer reading `wheel.log` after a workflow run can reconstruct the exact cascade path and the halt reason.

### FR-010 — Test fixtures (vitest + E2E)
**Vitest** (new file `plugin-wheel/src/lib/dispatch-cascade.test.ts`):

1. `dispatchCommand cascades through chained command steps` — workflow with three `command` steps; activation triggers cascade; final state shows cursor past end, all three steps `done`, workflow archived to `history/success/`. Validates US-1.
2. `dispatchCommand stops cascade at agent step` — workflow `command → command → agent → command`; activation cascades through both `command`s, stops at `agent` (cursor=2, agent step `working`). Trailing `command` is `pending`. Then test writes the agent's output file, fires `post_tool_use`, verifies the trailing `command` cascade-runs to terminal. Validates US-2.
3. `dispatchCommand cascade halts on step failure` — workflow `command(success) → command(fails) → command`. After cascade, step 0=done, step 1=failed, step 2=pending. Workflow archived to `history/failure/`. Validates US-3.
4. `dispatchBranch cascades to target` — workflow `branch → step-A | step-B`; both targets are `command`. Cascade jumps to target, runs trailing command, archives. Validates FR-004.
5. `dispatchLoop cascades after loop completion` — loop with command substep + max_iterations=3 + post-loop command. Loop runs 3 iterations, cascades to post-loop command, archives. Validates FR-003.
6. `cascade depth cap halts gracefully` — synthetic workflow with 1001 trivial command steps OR a self-referential branch loop. Cascade halts at depth 1000, logs `dispatch_cascade_halt` with reason `depth_cap`, leaves state in a resumable shape. Validates FR-006.
7. `composition cascade pauses at workflow step, resumes after child archive` — parent `command → workflow(child) → command`. Cascade runs first command, dispatches child workflow (which itself cascades to terminal), parent cascade pauses. After child archive triggers parent cursor advance (per wait-all redesign FR-009), next hook fire cascades parent's trailing command. Validates US-5.

**E2E** (re-enabled): `/wheel:wheel-test` Phases 1–3 fixtures pass under this PRD. No fixture file changes — the behavior change is what makes them pass. Validates US-4.

## 4. Success Criteria

| ID | Description | Baseline | Target | Verification |
|---|---|---|---|---|
| **SC-001** | `/wheel:wheel-test` Phase 1–3 pass rate | 0/13 (per `.wheel/logs/test-run-20260501T194556Z.md`) | 100% (10/10 expected results, ignoring 4 Phase-4 fixtures) | Run `/wheel:wheel-test`, inspect `.wheel/logs/test-run-*.md`. Exit 0, no orphan state. |
| **SC-002** | `count-to-100` wall-clock | 60 s timeout = test never completes | < 5 s wall-clock | Per-workflow duration column of test report. |
| **SC-003** | Orphan state files after `/wheel:wheel-test` | 14+ orphans | 0 orphans | `ls .wheel/state_*.json 2>/dev/null \| wc -l` returns 0. |
| **SC-004** | `dispatchCommand` source size delta | 46 lines (per `awk '/^async function dispatchCommand/,/^}/' plugin-wheel/src/lib/dispatch.ts \| wc -l` on this branch HEAD) | ≤ 46 + 30 = ≤ 76 lines (soft target — complexity guardrail, not a hard cap) | `wc -l` diff on the function. |

Thresholds reconciled against `specs/wheel-ts-dispatcher-cascade/research.md §Baseline`.

## 5. Out of Scope (Non-goals)

- Shell wheel changes (shell already cascades correctly).
- Dispatcher contract redesign (signatures unchanged).
- Wait-all team-wait redesign (separate PRD `2026-04-30-wheel-wait-all-redesign`).
- Other parity gaps (validation, registry, lock semantics, log paths) — separate PRDs if they surface.
- `engineHandleHook` refactor — engine continues to handle Stop/SubagentStop/TeammateIdle and post-dispatch cursor advance for non-cascade paths.
- Activation-contract change — `activate.sh` stays a no-op; cascade lives inside `handleActivation` after state init.
- Workflow JSON schema change — none.
- Iteration-count cap for loops — only recursion-depth cap.

## 6. Constraints (Absolute Musts)

1. TypeScript strict, Node 20+, `fs/promises`, `path`, no new external npm deps.
2. No regression in shell wheel (this PRD modifies TS only).
3. Lands inside the `002-wheel-ts-rewrite` branch chain (peer to / fast-follow on `wheel-wait-all-redesign`).
4. `/wheel:wheel-test` Phases 1–3 are the acceptance gate.
5. No new step-type registry — `isAutoExecutable` is a single helper, not an abstraction layer.
6. Cascade is opt-in per dispatcher (each dispatcher calls its own cascade tail). `dispatchAgent` does NOT cascade — it stays blocking and the post-agent cascade is driven by the existing post_tool_use detect-output-file path. Q1 from the PRD is resolved here: dispatchAgent's "output file detected → mark done → advance cursor" path is the post-agent trigger; engineHandleHook routes the next hook fire to dispatchStep on the new cursor, which cascades from there.

## 7. Open Questions Resolved at Spec Time

- **Q1 (post-agent cascade owner)** → `dispatchAgent` advances cursor on output detection (existing behavior); next hook fire's `engineHandleHook` calls `dispatchStep` on the new cursor; that dispatcher's cascade tail runs the trailing chain. No code change in `dispatchAgent`.
- **Q2 (depth cap warning)** → log `dispatch_cascade_halt` with `reason=depth_cap`, halt cascade gracefully, leave state at the in-flight cursor (FR-006).
- **Q3 (composition child archive → parent resume)** → parent cursor advance is the wait-all redesign's FR-009 contract; this PRD does NOT extend it. Composition cascade in the parent simply pauses at the `workflow` step and resumes on the next parent-hook fire after the child archives. Verified by US-5 / FR-010 fixture #7.
- **Q4 (composition in-scope?)** → in scope. The composition step's "enter child cascade" path is part of FR-001's "Composite" case and FR-010 fixture #7.

## 8. Acceptance Gate

A reviewer can declare this spec satisfied iff all of:
- All seven vitest cases (FR-010) pass under `vitest run plugin-wheel/src/lib/dispatch-cascade.test.ts`.
- `/wheel:wheel-test` reports SC-001 (100% Phase 1–3 pass) on the cache-deployed dist.
- SC-002 (count-to-100 < 5 s) confirmed in test report.
- SC-003 (0 orphans) confirmed by `ls .wheel/state_*.json | wc -l`.
- SC-004 (≤ 76 lines on `dispatchCommand`) confirmed; soft — overrun acceptable with documented justification.
- `git grep -nE "type === 'command'|type === 'loop'|type === 'branch'"` returns 0 hits inside cascade tails (FR-001 single-source-of-truth invariant).
- 80% coverage gate on changed lines per Constitution Article II.
- Every exported function in `contracts/interfaces.md` matches its signature exactly per Constitution Article VII.
- Every cascade-tail edit references an FR ID in a sparse load-bearing comment per Constitution Principle I.
