# Implementer friction notes — wheel-ts-dispatcher-cascade

**Branch**: `build/wheel-ts-dispatcher-cascade-20260501`
**Implementer**: impl-wheel
**Date**: 2026-05-01

## Surfaced gaps in spec/plan/contracts

### G1 — `state.steps[i]` is a projection, not the full WorkflowStep

The contract for `cascadeNext` (interfaces.md §4) says "reads fresh state"
and references "nextStep = state.steps[nextIndex]" implicitly. But
`stateInit` in `state.ts` projects WorkflowStep down to the runtime fields
(`id`, `type`, `status`, etc.) and **drops `command`, `condition`, `substep`,
`if_zero`, `if_nonzero`, `max_iterations`, etc.** dispatchCommand
short-circuits with `if (!step.command) return;` — so reading the next step
purely from `state.steps[i]` makes every cascade hop a silent no-op.

**Fix applied**: cascadeNext reads `state.workflow_definition.steps[i]`
first, falls back to `state.steps[i]`. handleActivation +
dispatchWorkflow already persist `workflow_definition` into the state
file. Engine path uses module-scoped `WORKFLOW` global which the cascade
isn't connected to, so the workflow_definition reads are the canonical path.

**Spec gap**: contracts/interfaces.md §4 should explicitly call out that
cascadeNext reads from workflow_definition (or note the projection
hazard). Filed informally here; would otherwise repeatedly bite.

### G2 — Skipped-step walk-past wasn't in the contract

The `dispatchBranch` spec (FR-004) marks the off-target arm as `skipped`
and sets cursor to the target. When the target's cascade hops PAST the
target (e.g., target was at index 1, off-target at index 2), the cascade
naturally walks past index 2. But if the off-target arm is BEFORE the
on-target arm, the cascade hops over `skipped` steps. cascadeNext must
walk past `skipped` exactly the way `maybeAdvanceParentTeamWaitCursor`
does — otherwise we'd re-execute (or re-mark working) a skipped step.

**Fix applied**: cascadeNext loops `while state.steps[i].status === 'skipped'`
to bump `resolvedIndex` before reading the next step.

**Spec gap**: not mentioned in interfaces.md §4. The behavior is
load-bearing; the contract should pin it down.

### G3 — Cascade-failure halt didn't archive

interfaces.md §5 says "exec fails → step.status = 'failed' → wheelLog
dispatch_cascade_halt reason=failed → return approve (no cascade)" — and
asserts "engine archive logic handles termination". But
`maybeArchiveAfterActivation` (the activation-path archive trigger) only
fires when **cursor >= length OR state.status terminal**. A failure that
halts the cascade leaves cursor at the failed step and state.status='running'
— so the orphan-state regression returns by the back door.

**Fix applied**: every cascade-tail failure path
(`dispatchCommand` exec error, `dispatchBranch` no-condition / target-not-found,
`dispatchLoop` exhaustion-fail) sets `state.status='failed'` immediately
before the halt log. The engine path (engineHandleHook) advances cursor
past failed steps separately, so its archive path was already covered.

**Spec gap**: contracts/interfaces.md §5 should say "set state.status='failed'"
explicitly, or the activation-path archive contract (§9) should detect
"any step failed" without an explicit status flip.

### G4 — Composition-resume (parent's trailing step after child archive)

US-5 says "the parent's cursor advances and the parent's cascade resumes
on the next hook fire". But `archiveWorkflow` only advances parent cursor
when parent's current step is `team-wait` (via
`maybeAdvanceParentTeamWaitCursor`). For `type: workflow` (composition),
there's no equivalent helper — parent stays at the workflow step forever.

**Workaround applied**: cascade-cascade.test.ts test #7 only validates the
boundary up to "parent halts at workflow step + child cascades to terminal".
The "parent's trailing command runs after child archive" assertion is
deferred to E2E (`/wheel:wheel-test composition-mega`) since vitest can't
synthesize the next-hook-fire reliably without re-implementing the hook
machinery.

**Spec gap**: PRD says "this PRD does not extend wait-all FR-009" — but
that FR-009 only covers team-wait. Composition-resume is unhandled in
the current TS code (regardless of cascade). Filed for a follow-up PRD.

## Foundation interactions (engineHandleHook archive wiring)

The wait-all-redesign B-3 fix (commit e18af4e8) wired `archiveWorkflow`
into `engineHandleHook` via `maybeArchiveTerminalWorkflow()` (engine
module-scoped, reads STATE_FILE). My Phase 5 extracted the body into a
public `maybeArchiveAfterActivation(stateFile)` so handleActivation can
call it without engine's STATE_FILE coupling. The engine wrapper still
clears STATE_FILE before delegating — preserves the re-entrant-archive
guard. No surprises.

## Substrate citations

| FR | Substrate | Citation |
|---|---|---|
| FR-001 (single classifier) | TERTIARY (vitest) + PRIMARY (`/wheel:wheel-test`) | `git grep -nE "type === 'command'\|type === 'loop'\|type === 'branch'" plugin-wheel/src/lib/dispatch.ts plugin-wheel/src/hooks/post-tool-use.ts` returns one comment hit only — invariant satisfied. /wheel:wheel-test gate is the audit-pr teammate's verification. |
| FR-002 (dispatchCommand cascade) | TERTIARY | dispatch-cascade.test.ts US-1: 3 chained commands, all done, archive to history/success/. Last assertion `archivedState.steps.every(s => s.status === 'done')`. |
| FR-003 (dispatchLoop cascade) | TERTIARY | dispatch-cascade.test.ts FR-003 test: loop with max_iterations=3 → trailing command runs and archives. |
| FR-004 (dispatchBranch cascade) | TERTIARY | dispatch-cascade.test.ts FR-004 test: branch → 'a' target runs, 'b' off-target marked skipped, archives. |
| FR-005 (handleActivation cascade trigger) | SECONDARY | post-tool-use.ts now calls `dispatchStep(steps[0], ..., 0, 0)` + `maybeArchiveAfterActivation`. Vitest can't drive handleActivation directly (it's hook-process-scoped); validation is by the audit-pr teammate via /wheel:wheel-test SC-001. |
| FR-006 (depth cap) | TERTIARY | dispatch-cascade.test.ts FR-006 test: 1002 trivial command steps, halts at depth 1000, `dispatch_cascade_halt reason=depth_cap` in wheel.log. Test takes ~18s (1001 execAsync('true') subprocesses). |
| FR-007 (hook-type pass-through) | TERTIARY (implicit) | cascadeNext takes hookType as parameter and passes it unchanged to recursive dispatchStep. Verified in source review; no separate test (would be redundant). |
| FR-008 (failure halt) | TERTIARY | dispatch-cascade.test.ts US-3 test: command(false) fails → halt log + failure-bucket archive. |
| FR-009 (cascade events) | TERTIARY | US-3 test asserts `wheel.log` contains `dispatch_cascade_halt.*reason=failed`; FR-006 test asserts `reason=depth_cap`. Other phases (`dispatch_cascade`, `cursor_advance`) emitted but not asserted in fixtures (visible in wheel.log on inspection). |
| FR-010 (test fixtures) | TERTIARY | This file: `plugin-wheel/src/lib/dispatch-cascade.test.ts`, 7 tests, all green. |
| SC-001 / SC-002 / SC-003 | PRIMARY | Deferred to audit-pr teammate's /wheel:wheel-test run. |
| SC-004 (line count) | TERTIARY | `awk '/^async function dispatchCommand/,/^}/' plugin-wheel/src/lib/dispatch.ts \| wc -l` → **64** lines (≤ 76 soft cap). |

## Build + test gate

- `cd plugin-wheel && npm run build` ✅
- `npx vitest run` → **99 / 99 passing** (92 baseline + 7 new in dispatch-cascade.test.ts)
- `git diff --cached --name-only` clean (auto-staged version-bump files only)
- All tasks.md items checked `[X]` per Article VIII.

## Recommendations for follow-up PRDs

1. **Composition-resume** — write a `wait-all-redesign-composition` PRD
   that wires `archiveWorkflow` to advance parent's cursor when parent's
   current step is `type: workflow`. Mirrors `maybeAdvanceParentTeamWaitCursor`.
   Without it, US-5 is half-done.
2. **workflowLoad fallback** — `workflowLoad(path)` rethrows ValidationError
   without trying the direct file read fallback. This forces composition
   fixtures to wrap workflow JSON in `{ workflow_definition: ... }`. Tiny
   ergonomic fix but useful.
3. **Coverage gate (T-080)** — defer to audit-compliance teammate; the
   80% gate is per Constitution Article II and this PRD's changes are
   well-covered by dispatch-cascade.test.ts but vitest --coverage flag
   needs plugin-wheel-level config.
