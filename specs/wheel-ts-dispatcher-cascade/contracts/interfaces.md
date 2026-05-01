# Interface Contracts — Wheel TS Dispatcher Cascade

Per Constitution Article VII: every signature here is the single source of truth. Implementation MUST match exactly. If a signature needs to change, this file MUST be updated FIRST.

All interfaces live in `plugin-wheel/src/lib/dispatch.ts` unless otherwise noted.

## 1. `isAutoExecutable` — single-source-of-truth helper (FR-001)

```typescript
/**
 * FR-001 — classifier for cascade participation.
 * Returns true iff the step type is in {'command', 'loop', 'branch'}.
 * The ONLY enumeration of auto-executable types in the codebase. Cascade
 * tails MUST call this helper rather than inline-comparing step.type.
 */
export function isAutoExecutable(step: WorkflowStep): boolean;
```

- **Sync.** No I/O, pure predicate.
- Module: `plugin-wheel/src/lib/dispatch.ts`.
- Used by: `cascadeNext`, `handleActivation`.

## 2. `CASCADE_DEPTH_CAP` — cascade recursion bound (FR-006)

```typescript
/** FR-006 — hard cap on cascade recursion depth. Graceful halt at this depth. */
export const CASCADE_DEPTH_CAP: 1000;
```

- Module: `plugin-wheel/src/lib/dispatch.ts`.
- Module-private is acceptable IFF unit tests in the same file reach it. If tests need it externally, export.

## 3. `dispatchStep` — entry-point signature (extended with depth)

```typescript
/**
 * Public entry point for dispatching a single workflow step. Routes to the
 * type-specific dispatcher (dispatchCommand / dispatchLoop / dispatchBranch /
 * dispatchAgent / ...). The optional `depth` parameter tracks cascade
 * recursion (FR-006); callers external to dispatch.ts SHOULD omit it (default 0).
 */
export async function dispatchStep(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
  depth?: number
): Promise<HookOutput>;
```

- **Async.** Returns `HookOutput` (existing type, unchanged).
- The `depth?` parameter is the ONLY new addition. Existing callers (`engineHandleHook`, `handleActivation`, tests) remain backwards-compatible.

## 4. `cascadeNext` — shared cascade tail (FR-002, FR-003, FR-004, FR-006, FR-008, FR-009)

```typescript
/**
 * Module-internal cascade tail. Called from dispatchCommand / dispatchLoop /
 * dispatchBranch after they mark their step done.
 *
 * Contract:
 *  1. Reads fresh state.
 *  2. If nextIndex >= steps.length: advances cursor, logs 'dispatch_cascade_halt'
 *     with reason='end_of_workflow', returns approve.
 *  3. Advances cursor to nextIndex (idempotent retry contract — FR-008 step ordering).
 *  4. If depth >= CASCADE_DEPTH_CAP: logs reason='depth_cap', returns approve.
 *  5. If !isAutoExecutable(nextStep): logs reason='blocking_step', returns approve.
 *  6. Logs 'dispatch_cascade'; recursively calls dispatchStep with depth+1; returns its result.
 *
 * Module: plugin-wheel/src/lib/dispatch.ts (module-private; not exported).
 */
async function cascadeNext(
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  nextIndex: number,
  depth: number
): Promise<HookOutput>;
```

- **Async.** Returns `HookOutput`.
- Not exported. Reachable only via the cascade-emitting dispatchers.

## 5. `dispatchCommand` — extended with cascade tail (FR-002, FR-008)

```typescript
/**
 * FR-019 (existing) + FR-002 (cascade) + FR-008 (failure halt).
 *
 * Success path:
 *   - exec succeeds → step.status = 'done' → if step.terminal: state.status='completed', return approve (no cascade).
 *   - else → return cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, depth).
 *
 * Failure path:
 *   - exec fails → step.status = 'failed' → wheelLog dispatch_cascade_halt reason=failed → return approve (no cascade).
 *
 * Signature unchanged from current code except for the new `depth` param threaded through.
 */
async function dispatchCommand(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
  depth: number
): Promise<HookOutput>;
```

- **Async.** Returns `HookOutput`.
- Module: `plugin-wheel/src/lib/dispatch.ts`.
- Signature line growth: 0 (only adds `depth` param). Body line growth: ≤ 30 lines for the cascade tail (SC-004 soft target).

## 6. `dispatchLoop` — extended with cascade tail (FR-003)

```typescript
/**
 * FR-025 (existing) + FR-003 (cascade).
 *
 * Cascade insertion points:
 *   - Loop exhausted, on_exhaustion === 'continue', step.status = 'done':
 *       return cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, depth).
 *   - Loop condition met early, step.status = 'done':
 *       return cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, depth).
 *   - Iteration in progress (substep type 'command' or 'agent'):
 *       NO cascade. Existing return semantics.
 */
async function dispatchLoop(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
  depth: number
): Promise<HookOutput>;
```

## 7. `dispatchBranch` — extended with cascade tail (FR-004)

```typescript
/**
 * FR-024 (existing) + FR-004 (cascade).
 *
 * After resolving target index + marking off-target 'skipped' + setting
 * cursor to target:
 *   - if target is END (stepIndex + 1 >= steps.length): cascadeNext to nextIndex.
 *   - else: return cascadeNext(hookType, hookInput, stateFile, targetIndex, depth).
 *
 * cascadeNext handles the auto-executable check + cursor-already-set semantics.
 */
async function dispatchBranch(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
  depth: number
): Promise<HookOutput>;
```

## 8. `handleActivation` — replaces kickstart with FR-005 cascade trigger

```typescript
/**
 * FR-005 — after stateInit + workflow_definition persistence:
 *   - if isAutoExecutable(steps[0]): dispatchStep(steps[0], 'post_tool_use', hookInput, stateFile, 0, 0).
 *   - else: do NOT cascade.
 *   - after dispatch returns: maybeArchiveAfterActivation(stateFile).
 *
 * The previous manual `while` loop kickstart (lines ~387–420) is REMOVED.
 *
 * Module: plugin-wheel/src/hooks/post-tool-use.ts. Signature unchanged.
 */
async function handleActivation(
  activateLine: string,
  hookInput: HookInput
): Promise<{ output: HookOutput; activated: boolean }>;
```

## 9. `maybeArchiveAfterActivation` — shared archive trigger (extracted from engine)

```typescript
/**
 * Mirrors maybeArchiveTerminalWorkflow from engine.ts but takes stateFile
 * as a parameter (not module-scoped). Used by handleActivation post-cascade
 * AND by engineHandleHook via a thin module-scoped wrapper.
 *
 * Idempotent: if the workflow is not terminal, no-op. If already archived,
 * no-op.
 *
 * Module: plugin-wheel/src/lib/engine.ts (NEW export) OR a new
 * plugin-wheel/src/lib/archive.ts. Choose at implementation time.
 */
export async function maybeArchiveAfterActivation(stateFile: string): Promise<void>;
```

- **Async.** Returns void.
- Engine's existing `maybeArchiveTerminalWorkflow` becomes a thin wrapper that reads `STATE_FILE` and delegates.

## 10. Logging phase types (FR-009)

`wheelLog` (in `plugin-wheel/src/lib/log.ts`) MUST accept these phase strings without runtime error. If `wheelLog` is strictly typed, extend its phase union:

```typescript
export type WheelLogPhase =
  | /* existing phases */
  | 'dispatch_cascade'
  | 'dispatch_cascade_halt'
  | 'cursor_advance';
```

Field schema (informal, all phases):
- `dispatch_cascade`: `from_step_id`, `to_step_id`, `from_step_type`, `to_step_type`, `hook_type`, `state_file`.
- `dispatch_cascade_halt`: `step_id`, `step_type`, `reason` (∈ `'blocking_step' | 'terminal' | 'failed' | 'end_of_workflow' | 'depth_cap'`), `state_file`.
- `cursor_advance`: `from_cursor`, `to_cursor`, `state_file`.

If `wheelLog` does not yet exist or doesn't support these phase types, the implementer adds a thin internal helper in `dispatch.ts` and emits to the existing log file. Either path satisfies FR-009.

## 11. Backwards-compat invariants

- `dispatchStep`'s caller signature (without `depth`) continues to work — `depth=0` default.
- `engineHandleHook` is unchanged.
- `dispatchAgent`, `dispatchTeamCreate`, `dispatchTeammate`, `dispatchTeamWait`, `dispatchTeamDelete`, `dispatchParallel`, `dispatchApproval`, `dispatchWorkflow` signatures are unchanged (cascade does not enter these — except `dispatchWorkflow` which manages its own child cascade per FR-001 Composite case).
- `WorkflowStep`, `HookType`, `HookInput`, `HookOutput` types are unchanged.
- `state_*.json` schema is unchanged.
- Workflow JSON schema is unchanged.
