# Tasks — Wheel TS Dispatcher Cascade

**Spec**: `specs/wheel-ts-dispatcher-cascade/spec.md`
**Plan**: `specs/wheel-ts-dispatcher-cascade/plan.md`
**Contracts**: `specs/wheel-ts-dispatcher-cascade/contracts/interfaces.md`

Execution rules (Constitution Articles VII + VIII):
- Mark `[X]` IMMEDIATELY after completing a task — not in batches.
- Commit after each phase (groups indicated by phase headers below).
- Every function reference in implementation MUST match `contracts/interfaces.md` exactly.
- Every code line MUST reference its FR ID in a sparse load-bearing comment.

---

## Phase 0 — Read & survey (no commit)

- [ ] **T-001** — Read `plugin-wheel/src/lib/dispatch.ts` end-to-end. Note where `dispatchCommand` / `dispatchLoop` / `dispatchBranch` mark `done` / `failed` — those are the cascade insertion points.
- [ ] **T-002** — Read `plugin-wheel/src/hooks/post-tool-use.ts handleActivation` (lines ~290–425). Identify the `while`-loop kickstart that FR-005 replaces.
- [ ] **T-003** — Read `plugin-wheel/src/lib/engine.ts engineHandleHook` + `maybeArchiveTerminalWorkflow`. Confirm post-dispatch advance + archive logic.
- [ ] **T-004** — Read shell wheel `dispatch_step` at `~/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.842/lib/dispatch.sh` for parity reference.
- [ ] **T-005** — Confirm `wheelLog` exists in `plugin-wheel/src/lib/log.ts` and what phase types it accepts. If strict-typed, prepare to extend `WheelLogPhase` union.

## Phase 1 — Helpers, contracts, depth threading (FR-001, FR-006)

- [ ] **T-010** — Add `AUTO_EXECUTABLE_STEP_TYPES` constant + `isAutoExecutable(step)` exported helper to `dispatch.ts`. Match contract §1 exactly. Add comment `// FR-001 — single source of truth for cascade-eligible step types.`
- [ ] **T-011** — Add `CASCADE_DEPTH_CAP = 1000` constant to `dispatch.ts`. Comment `// FR-006`.
- [ ] **T-012** — Add `cascadeNext` module-private function to `dispatch.ts` matching contract §4. Include the six numbered behaviors from the contract. FR-002/003/004/006/008/009 references in body comments.
- [ ] **T-013** — Extend `dispatchStep` exported signature to accept `depth?: number = 0`. Match contract §3. Backwards-compat verified: existing callers omit `depth`.
- [ ] **T-014** — Thread `depth` through to `dispatchCommand`, `dispatchLoop`, `dispatchBranch` calls inside `dispatchStep`'s switch. Other dispatchers do not need it (they don't cascade).
- [ ] **T-015** — Extend `WheelLogPhase` union (or equivalent) in `log.ts` with `'dispatch_cascade'`, `'dispatch_cascade_halt'`, `'cursor_advance'` if not already permissive. FR-009.
- [ ] **T-016** — `vitest run plugin-wheel/src/lib/dispatch.test.ts` — confirm no regressions from helper additions.
- [ ] **T-017** — Commit: `feat(wheel-ts): isAutoExecutable + cascadeNext + depth threading (FR-001/006/009)`.

## Phase 2 — `dispatchCommand` cascade tail (FR-002, FR-008)

- [ ] **T-020** — In `dispatchCommand` success path: replace `return { decision: 'approve' };` after the `done` set with `return cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, depth);` UNLESS step is `terminal: true`. Comment: `// FR-002 — cascade to next step after success.`
- [ ] **T-021** — In `dispatchCommand` failure path: emit `wheelLog({phase: 'dispatch_cascade_halt', step_id, step_type, reason: 'failed', state_file: stateFile})` BEFORE the `return { decision: 'approve' }`. Comment: `// FR-008 — cascade halts on failure.`
- [ ] **T-022** — Verify `dispatchCommand` still passes existing tests (`vitest run plugin-wheel/src/lib/dispatch.test.ts`).
- [ ] **T-023** — Verify `dispatchCommand` line count: `awk '/^async function dispatchCommand/,/^}/' plugin-wheel/src/lib/dispatch.ts | wc -l`. Target ≤ 76 lines (SC-004 soft cap).
- [ ] **T-024** — Commit: `feat(wheel-ts): dispatchCommand cascade tail (FR-002, FR-008)`.

## Phase 3 — `dispatchLoop` cascade tail (FR-003)

- [ ] **T-030** — In the `if (currentIteration >= maxIterations)` block, when `onExhaustion === 'continue'` and step set to `done`: replace `return { decision: 'approve' };` with `return cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, depth);`. Comment: `// FR-003 — cascade after loop exhausted.`
- [ ] **T-031** — In the early-condition-met block (`condExit === 0`): replace `return { decision: 'approve' };` after `stateSetCursor(stateFile, stepIndex + 1)` with the cascade call. Comment: `// FR-003 — cascade after loop condition met.`
- [ ] **T-032** — In the substep `command` iteration block, when `reIteration >= reMaxIter` and step is set `done`: also cascade. Comment: `// FR-003 — cascade after final loop iteration completes.`
- [ ] **T-033** — Substep `agent` path: NO cascade (still returns `block`). Verify behavior unchanged.
- [ ] **T-034** — Verify `vitest run plugin-wheel/src/lib/dispatch.test.ts` still green.
- [ ] **T-035** — Commit: `feat(wheel-ts): dispatchLoop cascade tail (FR-003)`.

## Phase 4 — `dispatchBranch` cascade tail (FR-004)

- [ ] **T-040** — After `stateModule.stateSetCursor(stateFile, targetIndex)`: read fresh state, fetch target step, replace `return { decision: 'approve' };` with `return cascadeNext(hookType, hookInput, stateFile, targetIndex, depth);`. Comment: `// FR-004 — cascade to branch target.`
- [ ] **T-041** — In the `if (!targetId || targetId === 'END')` early-return path: cascadeNext from `stepIndex + 1`. Comment: `// FR-004 — branch with no target falls through.`
- [ ] **T-042** — Verify `vitest run plugin-wheel/src/lib/dispatch.test.ts` still green.
- [ ] **T-043** — Commit: `feat(wheel-ts): dispatchBranch cascade tail (FR-004)`.

## Phase 5 — `handleActivation` cascade trigger + archive helper extract (FR-005)

- [ ] **T-050** — In `plugin-wheel/src/lib/engine.ts`: extract the body of `maybeArchiveTerminalWorkflow` into a new exported function `maybeArchiveAfterActivation(stateFile: string): Promise<void>` that takes `stateFile` as a parameter. Keep the module-scoped wrapper `maybeArchiveTerminalWorkflow()` that reads `STATE_FILE` and delegates — engine's existing call sites unchanged. Match contract §9.
- [ ] **T-051** — In `plugin-wheel/src/hooks/post-tool-use.ts handleActivation`: REMOVE lines ~387–420 (the manual `while` loop kickstart). REPLACE with:
  ```typescript
  // FR-005 — post-init cascade. Single dispatchStep call; cascade tails handle the rest.
  if (workflow.steps.length > 0 && isAutoExecutable(workflow.steps[0] as any)) {
    try {
      await dispatchStep(workflow.steps[0] as any, 'post_tool_use', hookInput, stateFile, 0, 0);
    } catch (err) {
      console.error('DEBUG: handleActivation cascade error:', err);
    }
  }
  // FR-005 — terminal-cursor archive after cascade.
  await maybeArchiveAfterActivation(stateFile);
  ```
- [ ] **T-052** — Add `import { isAutoExecutable } from '../lib/dispatch.js';` and `import { maybeArchiveAfterActivation } from '../lib/engine.js';` (or wherever T-050 placed it) at the top of `post-tool-use.ts`.
- [ ] **T-053** — Verify the kickstart removal does not break `dispatch.test.ts` or any other vitest file.
- [ ] **T-054** — Commit: `feat(wheel-ts): replace kickstart with FR-005 cascade trigger + maybeArchiveAfterActivation`.

## Phase 6 — Composition step cascade boundary (FR-001 Composite, US-5)

- [ ] **T-060** — Read `dispatchWorkflow` lines ~199–270 in `dispatch.ts`. Identify whether the child workflow's first step gets dispatched after child stateInit.
- [ ] **T-061** — If child cascade is NOT triggered: after child `stateInit` + `workflow_definition` persistence, add a `dispatchStep(childSteps[0], 'post_tool_use', hookInput, childStateFile, 0, 0)` call IFF `isAutoExecutable(childSteps[0])`. Comment: `// FR-001 Composite — child cascade kicked off in child state.`
- [ ] **T-062** — Parent cascade behavior at composition step: `dispatchWorkflow` returns approve after activating the child. Parent's `cascadeNext` is NOT called from within `dispatchWorkflow` (the parent cascade has already paused before reaching this dispatcher). Document with comment.
- [ ] **T-063** — Verify existing `dispatchWorkflow` tests still pass.
- [ ] **T-064** — Commit: `feat(wheel-ts): composition cascade boundary (FR-001 Composite, US-5)`.

## Phase 7 — Vitest fixtures (FR-010)

- [ ] **T-070** — Create `plugin-wheel/src/lib/dispatch-cascade.test.ts`. Use the same scaffolding pattern as `dispatch.test.ts` (tmpdir, real state file I/O).
- [ ] **T-071** — **Test 1** — `dispatchCommand cascades through chained command steps` — workflow with 3 `command` steps; activation triggers cascade; final state cursor=3, all `done`, archived to `history/success/`. Validates US-1, FR-002.
- [ ] **T-072** — **Test 2** — `dispatchCommand stops cascade at agent step` — `command → command → agent → command`; activation cascades through both commands, stops at agent (cursor=2, agent=working). Trailing command pending. Then write agent output file, fire `post_tool_use`, verify trailing command runs and archives. Validates US-2.
- [ ] **T-073** — **Test 3** — `dispatchCommand cascade halts on step failure` — `command(success) → command(false) → command`. Step 0=done, step 1=failed, step 2=pending. Archive to `history/failure/`. Validates US-3, FR-008.
- [ ] **T-074** — **Test 4** — `dispatchBranch cascades to target` — `branch → step-A | step-B`, both targets `command`. Cascade jumps to target, runs trailing command, archives. Validates FR-004.
- [ ] **T-075** — **Test 5** — `dispatchLoop cascades after loop completion` — loop with command substep + max_iterations=3 + post-loop command. Loop runs, then trailing command runs, archives. Validates FR-003.
- [ ] **T-076** — **Test 6** — `cascade depth cap halts gracefully` — workflow with 1001 trivial command steps (`command: 'true'`, no `terminal`); each step builds programmatically. Cascade halts at depth 1000. State preserved at in-flight cursor. `wheel.log` has `dispatch_cascade_halt` with `reason=depth_cap`. Validates FR-006.
- [ ] **T-077** — **Test 7** — `composition cascade pauses at workflow step, resumes after child archive` — parent `command → workflow(child) → command`. Verify first command runs in parent state, child workflow activates, child cascades to terminal, parent's trailing command runs after child archive (next hook fire). Validates US-5, FR-001 Composite.
- [ ] **T-078** — Each test references its FR + US in a comment per Constitution Article I.
- [ ] **T-079** — `vitest run plugin-wheel/src/lib/dispatch-cascade.test.ts` — all 7 pass.
- [ ] **T-080** — `vitest run --coverage plugin-wheel/src/lib/` — confirm ≥ 80% line + branch on changed lines per Article II.
- [ ] **T-081** — Commit: `test(wheel-ts): dispatcher cascade vitest fixtures (FR-010)`.

## Phase 8 — Build, deploy, `/wheel:wheel-test` (SC-001/002/003)

- [ ] **T-090** — Build TS: `cd plugin-wheel && npm run build` (or whatever the build script is — check `plugin-wheel/package.json`).
- [ ] **T-091** — Deploy to plugin cache: `rm -rf ~/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.842/dist/* && cp -r plugin-wheel/dist/. ~/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.842/dist/`.
- [ ] **T-092** — Run `/wheel:wheel-test`. Wait for completion.
- [ ] **T-093** — Inspect `.wheel/logs/test-run-<latest>.md`. Verify SC-001 (Phase 1–3 100% pass, 10/10 fixtures).
- [ ] **T-094** — Verify SC-002 (`count-to-100` wall-clock < 5 s) from per-workflow duration column of report.
- [ ] **T-095** — Verify SC-003: `ls .wheel/state_*.json 2>/dev/null | wc -l` returns 0.
- [ ] **T-096** — Verify SC-004: `awk '/^async function dispatchCommand/,/^}/' plugin-wheel/src/lib/dispatch.ts | wc -l` ≤ 76 lines (soft).
- [ ] **T-097** — Verify FR-001 invariant: `git grep -nE "type === 'command'|type === 'loop'|type === 'branch'" plugin-wheel/src/lib/dispatch.ts plugin-wheel/src/hooks/post-tool-use.ts` returns 0 hits inside cascade tails / kickstart paths (the `dispatchStep` switch's case-string comparisons are NOT cascade tails; those are exempt).
- [ ] **T-098** — If any Phase 1–3 fixture fails: diagnose, fix, re-run. Commit fixes individually.

## Phase 9 — Audit + retro hand-off

- [ ] **T-100** — Run `/kiln:audit` (PRD compliance audit). Address any gaps or document blockers per `specs/wheel-ts-dispatcher-cascade/blockers.md` if unfixable.
- [ ] **T-101** — Confirm all FR-001..FR-010 are referenced by at least one test or comment (Article I traceability).
- [ ] **T-102** — Confirm `contracts/interfaces.md` signatures match implementation byte-for-byte.
- [ ] **T-103** — SendMessage to audit-compliance teammate via SendMessage tool when impl is done.
- [ ] **T-104** — Mark task #2 (Implement) completed in TaskUpdate after all of T-100..T-102 are green.

---

## Dependency graph

- Phase 0: prerequisites for all later phases (read-only).
- Phase 1: prerequisites for Phases 2/3/4/5/6 (cascadeNext + depth threading must exist).
- Phase 2/3/4: parallelizable — each cascades a different dispatcher.
- Phase 5: depends on Phase 1 (uses isAutoExecutable + dispatchStep depth param).
- Phase 6: depends on Phase 1 + Phase 5 (composition cascade uses same primitives).
- Phase 7: depends on Phases 1–6 (tests exercise the full cascade behavior).
- Phase 8: depends on Phase 7 (build+deploy after tests green).
- Phase 9: depends on Phase 8 (audit after E2E green).

## Acceptance summary (mirror of spec §8)

A reviewer can declare implementation done iff:
1. All `[X]` boxes above are checked.
2. SC-001 (Phase 1–3 100% pass) confirmed in `.wheel/logs/test-run-*.md`.
3. SC-002, SC-003, SC-004 confirmed.
4. FR-001 single-source invariant (T-097) confirmed.
5. 80% coverage gate (T-080) confirmed.
6. `contracts/interfaces.md` signature-match confirmed.
