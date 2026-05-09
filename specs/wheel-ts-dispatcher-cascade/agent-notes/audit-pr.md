# audit-pr friction note — wheel-ts-dispatcher-cascade

Run: `2026-05-01T22:14:28Z` (smoke), branch `build/wheel-ts-dispatcher-cascade-20260501`.

## Outcome

**PR was NOT opened.** SC-1 acceptance gate (`/wheel:wheel-test` Phases 1-3 green) could not be cleared because two pre-existing wheel-ts-rewrite bugs surface as Phase 1 failures even after the cascade lands. Both are out of scope for this PRD per the cascade unit tests' explicit `// Loops increment per dispatch; drive through max_iterations + 1 dispatches.` comment in `dispatch-cascade.test.ts:203`.

## /wheel:wheel-test results (this run)

Cascade itself works — see `.wheel/wheel.log`:
- count-to-100 cascade: `init` → `count-loop` (logged at 22:14:37 — the cascade behavior the PRD adds).
- loop-test cascade: `setup` → `increment-loop` (22:14:43).
- team-sub-fail cascade halt: `fail-step reason=failed` (22:14:46) → archived to `.wheel/history/failure/team-sub-fail-20260501-221446-...`.

Phase 1 individual outcomes:
- **count-to-100 — FAIL.** Loop step `count-loop` ran iteration 1 (counter file shows `1`, log shows 1 line), then dispatcher returned `{decision: 'approve'}` without re-cascading. Subsequent post-tool-use hooks (from my own bash calls) drove iteration 2…N until line 1015's `currentIteration >= maxIterations` triggered terminal failure. Five `loop: exhausted after 10 iterations` entries in `command_log` between 22:16:44 and 22:17:09. State.status set to `failed`; not archived (cascade halt with reason=failed leaves the state file in place).
- **loop-test — FAIL.** Same shape: cascade reached `increment-loop`, ran iteration 1, returned. Counter ended at 1 (need ≥3). State stayed alive, step status pending/working, never satisfied condition.
- **team-sub-fail — PASS** (expected-failure reconciliation: workflow basename `*-fail*` → fail in `.wheel/history/failure/` is a pass).

Skipped Phases 2-4 because team-lead's instructions explicitly gate on Phase 1.

## Two pre-existing TS-rewrite bugs that block SC-1

### Bug A: dispatchLoop doesn't self-cascade between iterations

`plugin-wheel/src/lib/dispatch.ts:1109` returns `{decision: 'approve'}` after running one substep iteration. There is no `cascadeNext(... stepIndex, depth)` self-recursion to drive the loop forward. The cascade only fires *forward* (to step+1) when the loop is determined complete (lines 1024-1027 / 1056-1058 / 1104-1107). The unit test `dispatch-cascade.test.ts:189-203` explicitly acknowledges this: "Loops increment per dispatch; drive through max_iterations + 1 dispatches."

This means workflows with high `max_iterations` (count-to-100=101) cannot self-complete inside a single activation — they require N external post-tool-use events. With Phase 1's 60 s budget and tool-call cadence, that's not achievable for count-to-100. Even loop-test (max=5, condition at 3) needs ≥3 external dispatches and the harness wait_all only fires one per workflow.

### Bug B: max_iterations defaults to 10 because it's read from state, not workflow definition

`plugin-wheel/src/lib/dispatch.ts:1009` and `dispatch.ts:1101`:
```ts
const maxIterations = (step as any).max_iterations ?? 10;             // line 1009 — reads from step definition (correct)
const reMaxIter = (reState.steps[stepIndex] as any)?.max_iterations ?? 10;  // line 1101 — reads from STATE (wrong)
```

`state.steps[i]` is a state-projection that doesn't carry `max_iterations` (workflow-def property). So line 1101 always falls back to 10. count-to-100 (workflow says 101) was therefore guaranteed to fail at iteration 10 regardless of cascade behavior.

Easy fix: read from `state.workflow_definition.steps[stepIndex].max_iterations` like cascadeNext does at `dispatch.ts:173-175` (`Prefer workflow_definition.steps over state.steps`). But this is loop-dispatcher-internal — outside this PRD's FRs.

## Why this isn't a regression of this PR

Previous test report `.wheel/logs/test-run-20260501T194556Z.md` (taken before cascade impl): **0 / 109 passed.** count-to-100 + loop-test both timed out at 60 s with reason `phase 1 60s timeout`, no cascade hops in `wheel.log`. The cascade fix actually made progress (cascade hops fire, team-sub-fail now correctly archives to `failure/`), but the loop-iteration gap and the max-iterations-read-from-state gap dominate the smoke verdict.

## Cache deploy + restore mechanics — what I observed

- `npm run build` succeeded clean.
- Deploy of `dist` + `hooks/*.sh` to `~/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.842` worked first try.
- The cached `hooks/post-tool-use.sh` is a **TS shim** (`exec node "$DIST_HOOK"`). The shim REQUIRES `dist/` to be present; if `dist/` is removed per the team-lead's cleanup step (`rm -rf $CACHE/dist`) without restoring the original shell-based hook, *every* tool call in the user's session will fail with `Cannot find module dist/hooks/post-tool-use.js`. I had to re-deploy `dist/` before walking away. **Action item**: the cleanup recipe in the team-lead message should either preserve dist OR restore the original hooks; otherwise the parent session is left in a broken state.
- After PR is opened (or in this case, deferred), the cache should be reset by re-running `claude plugin install` rather than ad-hoc `rm -rf` / `cp`.

## PR body template

Template was workable. The four-row SC-1 table with `<PASS|FAIL>` placeholders + Phase 4 deferred line maps cleanly. Did not get to use it because the gate failed.

## Anything to flag for team-lead

1. **SC-1 gate is not achievable with this PRD alone.** The cascade PRD's scope (per its specs/tests) explicitly defers loop self-iteration. count-to-100 and loop-test cannot complete in Phase 1's 60 s budget without either (a) a follow-up PRD adding loop self-cascade, or (b) reducing the smoke fixtures' `max_iterations` to ≤ a single-dispatch-friendly count and lifting the workflow expectation to "drive externally". I'd lean (a) — both bugs are small, the loop fix would land naturally as a "loop-self-iterate-cascade" PRD on top of this one.
2. **The TS-rewrite cached `post-tool-use.sh` shim is fragile.** Manual `rm -rf $CACHE/dist` without restoring shell hooks bricks the parent session. Worth either (a) shipping a defensive fallback in the shim, or (b) updating the team-lead recipe to also restore hooks.
3. Audit-compliance was right to flag `@vitest/coverage-v8@4.1.5` infra incompatibility separately — not material to this gate.

## Cleanup performed

- Phase 1 orphan state files moved to `.wheel/history/stopped/` (count-to-100 + loop-test).
- Cache `dist/` left in place (removing it would brick the hook shim — see flag #2).

## Files generated

- `.wheel/logs/.wheel-test-phases-20260501T221428Z.env`
- `.wheel/logs/.wheel-test-phase1-starts-20260501T221428Z.tsv`
- `.wheel/logs/.wheel-test-results-20260501T221428Z.tsv` (empty — `wt_phase1_wait_all` aborted on `set -e` propagation when `wt_wait_for_archive` returned rc=2; minor harness bug, not in this PRD's scope either)
- No `test-run-<ts>.md` produced (didn't reach Step 7).
