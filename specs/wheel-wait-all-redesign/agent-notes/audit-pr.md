# audit-pr friction note (task #4)

_Author: audit-pr agent (claude sonnet) — 2026-04-30_
_Branch: build/wheel-wait-all-redesign-20260430_

## Substrate citation

**Used**: 89 unit/integration tests in `plugin-wheel/src/**/*.test.ts` (vitest 1.6.1, all pass) + structural code-reading.

**Skipped (deferred)**: live Phase 4 fixture run via `plugin-wheel/docs/isolated-workflow-testing.md` recipe.

## Why live Phase 4 was deferred

Two compounding reasons:

1. **B-3 will deterministically stall any Phase 4 fixture.** The audit-compliance agent (task #3) flagged that `archiveWorkflow` is exported from `state.ts:473` and exhaustively unit-tested (14 tests in `archive-workflow.test.ts`) but is **not called from any TS terminal-step dispatcher**. I confirmed this by code-reading:
   - `plugin-wheel/src/lib/dispatch.ts:178-182` — terminal=true sets `state.status = 'completed'` but does NOT call `archiveWorkflow(stateFile, bucket)`.
   - `plugin-wheel/src/lib/engine.ts engineHandleHook` — no archive call.
   - `plugin-wheel/hooks/stop.sh` is a pure shim: `exec node "$PLUGIN_ROOT/dist/hooks/stop.js"`. The shell `_archive_workflow` in `lib/dispatch.sh` is dead code.
   - `_runPollingBackstop` in `dispatch.ts:521` keys "child still running" on whether `alternate_agent_id` appears in any live `.wheel/state_*.json`. Without `archiveWorkflow` removing the file, the backstop sees the child as "still running" forever — slot never reconciles, parent step stalls in `working`.
   The team-static / team-dynamic / team-partial-failure fixtures all rely on this archive→parent-slot-update path, so all three would stall identically.

2. **Cache version mismatch — the recipe tests stale code.** The isolated-workflow-testing recipe (per `plugin-wheel/docs/isolated-workflow-testing.md`) invokes `~/.claude/plugins/cache/yoshisada-speckit/wheel/<version>/bin/activate.sh`. Latest installed cache is `000.001.009.842` (Apr 29). Our wait-all-redesign source compiles to `000.001.009.1340` and is uncommitted to the cache. So even if I ran the recipe, the subprocess would exec the OLD shell `_archive_workflow` path (which is removed in our TS rewrite) and the test would not exercise our changes. Setting up a fake cache version pointing at our local `plugin-wheel/dist` is non-trivial (requires understanding Claude Code's plugin-resolution logic at hook time) and risks polluting the parent session.

The combined verdict: a live run would either (a) test stale code, giving zero signal, or (b) cost ~$3 + 5 min × 3 fixtures to confirm a B-3 prediction that's already empirically grounded by 89 passing unit tests + an exported-but-uncalled function with no callers via grep.

## What the PR should communicate

- All 11 PRD FRs are implemented and unit-tested at the helper level.
- FR-009 wiring is **partial**: `archiveWorkflow` exists, is correct, and is unit-tested, but is not called from `dispatchCommand` / `dispatchAgent` terminal branches yet. This is a known follow-up.
- Phase 4 live fixture run (SC-001/003/004) is DEFERRED to the FR-009-wiring follow-up PR.
- Coverage gate met by manual branch-counting (B-4 — vitest/coverage-v8 pin mismatch is a separate ticket).

## Cleanup

- Removed `/tmp/wheel-phase4-3C9D8C80/` (created during setup before the deferral decision).
- No `~/.claude/teams/test-*-team` dirs were created (no teams ever spawned).
- No state files left in parent's `.wheel/`.

## PR body template workability

Workable. Made small adjustments:
- Replaced "Phase 4 smoke" PASS/FAIL grid with a DEFERRED block citing B-3.
- Added a "Follow-up issues" line so the B-3 wiring fix is explicitly tracked.

## Flags for team-lead

- **B-3 is the most important known issue.** Without it, the wait-all redesign is effectively untestable end-to-end. Recommend filing as a P0 follow-up before any further wait-all work lands.
- **B-4 (coverage tooling)** should be a separate small PR — pin `@vitest/coverage-v8` to `^1.6.1` to match vitest 1.6.x, OR bump vitest to ^3.x.
- The isolated-workflow-testing recipe doc should be amended to address the "testing uncommitted local changes" case (currently it assumes the desired version is already in the cache).
