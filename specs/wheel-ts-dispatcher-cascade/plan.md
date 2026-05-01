# Implementation Plan — Wheel TS Dispatcher Cascade

**Spec**: `specs/wheel-ts-dispatcher-cascade/spec.md`
**Contracts**: `specs/wheel-ts-dispatcher-cascade/contracts/interfaces.md`
**Research**: `specs/wheel-ts-dispatcher-cascade/research.md`

## Foundation note (READ FIRST)

This PRD folds into the `build/wheel-wait-all-redesign-20260430 → 002-wheel-ts-rewrite` branch chain. The pipeline branch is `build/wheel-ts-dispatcher-cascade-20260501`, branched from the wait-all-redesign tip. **Existing in-progress code on this branch is the FOUNDATION the implementer extends — not something to discard.**

Concretely: the implementer reads `plugin-wheel/src/lib/dispatch.ts` and `plugin-wheel/src/hooks/post-tool-use.ts` on this branch and extends them with FR-001 through FR-010. The existing kickstart loop in `handleActivation` is REPLACED (not deleted in isolation — replaced with the FR-005 cascade trigger). All other dispatcher logic is preserved, with cascade tails appended at success/failure boundaries.

This plan operationalizes the PRD's FRs. It introduces no new design — every choice traces back to a PRD FR.

## 1. Architecture

### Where the cascade lives

```
PostToolUse hook (post-tool-use.ts)
  ├── handleActivation(activateLine, hookInput)
  │     ├── stateInit + persist workflow_definition
  │     └── if isAutoExecutable(steps[0]):
  │           dispatchStep(steps[0], 'post_tool_use', hookInput, stateFile, 0, /*depth=*/0)   ← FR-005
  │
  └── handleNormalPath(hookInput, stateFile)
        └── engineHandleHook(...)  (engine.ts)
              ├── dispatchStep(step, hookType, hookInput, STATE_FILE, cursor)
              │    ├── dispatchCommand → success/failure → cascadeNext(...)   ← FR-002
              │    ├── dispatchLoop    → loop done/skipped → cascadeNext(...) ← FR-003
              │    ├── dispatchBranch  → target resolved → cascadeNext(...)   ← FR-004
              │    ├── dispatchAgent / dispatchTeamCreate / ... → blocking, no cascade
              │    └── dispatchWorkflow → composition: child cascade inside child state
              └── maybeArchiveTerminalWorkflow()                              ← unchanged (wait-all FR-009)
```

### Single-source-of-truth helper

```typescript
// plugin-wheel/src/lib/dispatch.ts (top of file, near HookType / HookInput)

const AUTO_EXECUTABLE_STEP_TYPES = new Set(['command', 'loop', 'branch'] as const);

/** FR-001: Catalog of step types that participate in cascade. The ONLY enumeration. */
export function isAutoExecutable(step: WorkflowStep): boolean {
  return AUTO_EXECUTABLE_STEP_TYPES.has(step.type as any);
}
```

### Shared cascade-tail helper

```typescript
// plugin-wheel/src/lib/dispatch.ts

/**
 * FR-002 / FR-003 / FR-004 — shared cascade tail.
 *
 * Called from dispatchCommand / dispatchLoop / dispatchBranch after they
 * mark their step done. Advances cursor to nextIndex, decides whether to
 * recurse (auto-executable) or return (blocking / terminal / depth-cap).
 *
 * Idempotency contract (FR-008): cursor advance precedes dispatch. If
 * dispatch crashes, state is at {cursor=nextIndex, step.status=pending}
 * — next hook fire retries the right step.
 */
async function cascadeNext(
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  nextIndex: number,
  depth: number
): Promise<HookOutput> {
  const stateModule = await import('./state.js');
  const state = await stateRead(stateFile);

  if (nextIndex >= state.steps.length) {
    await stateModule.stateSetCursor(stateFile, nextIndex);
    await wheelLog({ phase: 'dispatch_cascade_halt', step_id: '', step_type: '', reason: 'end_of_workflow', state_file: stateFile });
    return { decision: 'approve' };
  }

  const nextStep = state.steps[nextIndex] as any;
  const fromStepId = (state.steps[Math.max(0, nextIndex - 1)] as any)?.id ?? '';
  const fromStepType = (state.steps[Math.max(0, nextIndex - 1)] as any)?.type ?? '';

  // FR-002 step 6 — advance cursor FIRST (idempotency).
  await stateModule.stateSetCursor(stateFile, nextIndex);
  await wheelLog({ phase: 'cursor_advance', from_cursor: nextIndex - 1, to_cursor: nextIndex, state_file: stateFile });

  if (depth >= CASCADE_DEPTH_CAP) {
    await wheelLog({
      phase: 'dispatch_cascade_halt',
      step_id: nextStep.id, step_type: nextStep.type,
      reason: 'depth_cap',
      state_file: stateFile,
    });
    return { decision: 'approve' };
  }

  if (!isAutoExecutable(nextStep)) {
    await wheelLog({
      phase: 'dispatch_cascade_halt',
      step_id: nextStep.id, step_type: nextStep.type,
      reason: 'blocking_step',
      state_file: stateFile,
    });
    return { decision: 'approve' };
  }

  await wheelLog({
    phase: 'dispatch_cascade',
    from_step_id: fromStepId, from_step_type: fromStepType,
    to_step_id: nextStep.id, to_step_type: nextStep.type,
    hook_type: hookType, state_file: stateFile,
  });

  return dispatchStep(nextStep as WorkflowStep, hookType, hookInput, stateFile, nextIndex, depth + 1);
}

const CASCADE_DEPTH_CAP = 1000; // FR-006
```

### `dispatchStep` gains a `depth` parameter

The exported signature gains an optional `depth = 0` parameter at the end. Existing callers (engine, post-tool-use) call without `depth` and get 0 by default — backwards compatible.

```typescript
export async function dispatchStep(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
  depth: number = 0
): Promise<HookOutput> { ... }
```

## 2. Phases

### Phase 0 — Read & catalog (no code yet)
- Read `plugin-wheel/src/lib/dispatch.ts` end-to-end.
- Read `plugin-wheel/src/hooks/post-tool-use.ts handleActivation` lines ~290–425.
- Read shell `dispatch_step` (`~/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.842/lib/dispatch.sh`) for parity reference.
- Confirm helpers `wheelLog`, `stateSetCursor`, `stateRead`, `stateWrite` from `state.ts` / `log.ts`. If `wheelLog` doesn't exist with the needed phase types, add a thin wrapper.

### Phase 1 — Helpers & contracts (FR-001, FR-006)
- Add `isAutoExecutable(step)` exported helper in `dispatch.ts`.
- Add `CASCADE_DEPTH_CAP = 1000` constant + `cascadeNext` helper.
- Update `dispatchStep` signature to accept `depth`.
- Commit: "feat(wheel-ts): add isAutoExecutable + cascadeNext helpers (FR-001, FR-006)"

### Phase 2 — `dispatchCommand` cascade tail (FR-002, FR-008, FR-009)
- After the `done` set: call `cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, depth)` and return its result, UNLESS step is `terminal: true` (return as today).
- After the `failed` set: emit `dispatch_cascade_halt` with `reason=failed`, return without cascading.
- Commit: "feat(wheel-ts): dispatchCommand cascade tail (FR-002, FR-008)"

### Phase 3 — `dispatchLoop` cascade tail (FR-003)
- Inside both `done` boundaries (loop exhausted with `on_exhaustion=continue`, condition met early): call `cascadeNext` and return its result.
- Iteration in progress: existing return semantics (advance loop counter, return approve). NO cascade.
- Substep type `agent`: existing block return. NO cascade.
- Commit: "feat(wheel-ts): dispatchLoop cascade tail (FR-003)"

### Phase 4 — `dispatchBranch` cascade tail (FR-004)
- After resolving target index + marking off-target `skipped` + setting cursor to target: read the target step. Call `cascadeNext(hookType, hookInput, stateFile, targetIndex, depth)` IF auto-executable; otherwise return as today. Note: cascadeNext expects `nextIndex` semantics — for branch, we already set cursor to target; pass `targetIndex` directly.
- The `if (!targetId || targetId === 'END')` early-return path: cursor advances to `stepIndex + 1`; cascade from there if next step is auto-executable.
- Commit: "feat(wheel-ts): dispatchBranch cascade tail (FR-004)"

### Phase 5 — `handleActivation` post-init cascade (FR-005)
- Replace the `while` loop kickstart (lines ~387–420 of `post-tool-use.ts`) with:
  ```typescript
  if (workflow.steps.length > 0 && isAutoExecutable(workflow.steps[0])) {
    try {
      await dispatchStep(workflow.steps[0] as any, 'post_tool_use', hookInput, stateFile, 0, 0);
    } catch (err) {
      console.error('DEBUG: handleActivation cascade error:', err);
    }
  }
  // After cascade, terminal-cursor archive must run — call shared maybeArchive helper.
  await maybeArchiveAfterActivation(stateFile);
  ```
- Add `maybeArchiveAfterActivation(stateFile)` — extracts the engine's terminal-archive logic into a shared helper (or call `engineHandleHook` semantics inline). Implementation choice: extract `maybeArchiveTerminalWorkflow` into `state.ts` or a new `archive.ts` so both `engineHandleHook` and `handleActivation` share it. (Engine currently uses module-scoped `STATE_FILE`; refactor to take `stateFile` as a parameter.)
- Delete the manual cursor-advance + while-loop body (lines ~387–420). Net source-line change: post-tool-use.ts shrinks; dispatch.ts grows by ≤30 lines for cascade helpers + tails.
- Commit: "feat(wheel-ts): replace handleActivation kickstart with cascade trigger (FR-005)"

### Phase 6 — `dispatchWorkflow` composition cascade boundary (FR-001 Composite, US-5)
- The existing `dispatchWorkflow` activates a child state file. After child activation, cascade in the PARENT pauses (return without recursing). When the child later archives (via wait-all redesign FR-009), the parent's cursor advances and the next parent-hook fire dispatches the parent's trailing step, which cascades from there.
- Implementation: NO change to `dispatchWorkflow` cascade — but the child workflow's first step MUST cascade inside the child state. This already happens because the child uses the same `dispatchStep` entry point (the activation path is in `dispatchWorkflow` itself; verify it triggers `cascadeNext` for the child's step 0 if auto-executable).
- Confirm by reading `dispatchWorkflow` lines ~199–270 — if the child cascade isn't kicked off, add a single `dispatchStep(childSteps[0], 'post_tool_use', ..., childStateFile, 0, 0)` call after child stateInit.
- Commit: "feat(wheel-ts): composition step cascade boundary (FR-001 Composite, US-5)"

### Phase 7 — Vitest fixtures (FR-010)
- Create `plugin-wheel/src/lib/dispatch-cascade.test.ts` with all 7 test cases from spec FR-010.
- Tests use real state file I/O in `tmpdir()` workspaces (mirrors existing `dispatch.test.ts` style).
- Each test references its FR + US in a comment per Constitution Article I.
- Commit: "test(wheel-ts): vitest fixtures for dispatcher cascade (FR-010)"

### Phase 8 — Build + cache deploy + `/wheel:wheel-test`
- `npm run build` (or equivalent) inside `plugin-wheel/` → produces `plugin-wheel/dist/`.
- Deploy to plugin cache: `cp -r plugin-wheel/dist/. ~/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.842/dist/` (per PRD Assumptions §5).
- Run `/wheel:wheel-test`.
- Inspect `.wheel/logs/test-run-<ts>.md`. Verify SC-001 / SC-002 / SC-003.
- Confirm `git grep -nE "type === 'command'\|type === 'loop'\|type === 'branch'"` returns no hits inside cascade tails (FR-001 invariant).
- Commit if any fixture regressions surfaced and were fixed: "fix(wheel-ts): <surface>"

### Phase 9 — Audit + retro hand-off
- All seven vitest cases pass.
- 80% coverage gate on changed lines.
- PRD audit (`/kiln:audit`) green.
- Hand off to retrospective.

## 3. File list

### New
- `plugin-wheel/src/lib/dispatch-cascade.test.ts` — vitest fixtures (FR-010).
- `specs/wheel-ts-dispatcher-cascade/contracts/interfaces.md` — interface contracts (this PRD).

### Modified
- `plugin-wheel/src/lib/dispatch.ts` — add `isAutoExecutable`, `cascadeNext`, `CASCADE_DEPTH_CAP`, `depth` param on `dispatchStep`, cascade tails in `dispatchCommand` / `dispatchLoop` / `dispatchBranch`. ≤ 30 lines net growth on `dispatchCommand` (SC-004 soft target).
- `plugin-wheel/src/hooks/post-tool-use.ts` — replace `handleActivation` kickstart `while` loop with single `dispatchStep` call + `maybeArchiveAfterActivation`. Net line decrease.
- `plugin-wheel/src/lib/engine.ts` — extract `maybeArchiveTerminalWorkflow` to take `stateFile` parameter so both `engineHandleHook` and `handleActivation` share it. (May be a tiny refactor — extract function body, keep module-scoped wrapper for engine compat.)
- `plugin-wheel/src/lib/log.ts` (if needed) — add `dispatch_cascade`, `dispatch_cascade_halt`, `cursor_advance` phase types. If `wheelLog` is already typed permissively, no change needed.

### Unchanged (verify, do not edit)
- `plugin-wheel/src/lib/state.ts`, `workflow.ts`, `archive-workflow.ts`, `lock.ts`, `registry.ts`, `resolve_inputs.ts`, `preprocess.ts`, `guard.ts`, `context.ts`, `index.ts`.
- All shell wheel files (`plugin-wheel/scripts/*.sh`, `plugin-wheel/lib/*.sh`).
- All workflow JSON schema files.
- All other plugin (`plugin-kiln`, `plugin-clay`, `plugin-shelf`, `plugin-trim`).

## 4. Tech stack

Inherited from `002-wheel-ts-rewrite`. TypeScript strict, Node 20+, `fs/promises`, `path`, `child_process`, `util.promisify`, vitest. No new external deps.

## 5. Risks (Implementation-time)

- **R-engine-extract**: extracting `maybeArchiveTerminalWorkflow` from module-scoped `STATE_FILE` to parameter-passed style might break engine's existing `STATE_FILE = ''` pattern (which prevents re-entrant archives). Mitigation: keep the module-scoped variable + wrapper in engine, but add a parameter-taking sibling helper that `handleActivation` calls. Both call the same archive helper from `state.ts`.
- **R-depth-cap-test**: synthesizing a 1001-step workflow for vitest test #6 may be slow. Mitigation: build the workflow JSON in-memory (array.from + map), don't run real shell commands — use `command: 'true'` for each step.
- **R-composition-test**: test #7 (composition) requires both parent + child workflow JSON. Mitigation: write minimal child fixture inline; use the same patterns as `dispatch.test.ts`'s existing dispatchWorkflow tests.
- **R-cache-deploy-staleness**: cache deploy via `cp -r` may leave stale files. Mitigation: `rm -rf <cache>/dist/* && cp -r plugin-wheel/dist/. <cache>/dist/`. Document in Phase 8.

## 6. Rollback

If the cascade breaks something (Phase 4 fixture regression, unexpected workflow stalls), revert with `git revert <range>`. The cascade is opt-in per dispatcher — reverting just the cascade-tail commits restores the prior behavior. The kickstart-replacement commit (Phase 5) is the only commit that removes existing behavior; revert it last.
