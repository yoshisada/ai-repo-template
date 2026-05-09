# Specifier friction note — wheel-ts-rewrite-parity-completion

**Agent**: specifier (task #1)
**Date**: 2026-05-01
**Branch**: build/wheel-ts-rewrite-parity-completion-20260501

## What was ambiguous in the PRD

- **PRD §FR-9 option choice**: deferred to impl-wheel at plan-time. Resolved as option (a) `@vitest/coverage-v8@^1.6.x` in `research.md §FR-009-decision` with concrete rationale (vitest 3 has breaking API changes, blast radius too high). impl-wheel still has the explicit fall-back to option (b) if option (a) fails at install time.
- **PRD §R-3 (composition cascade interaction)**: PRD said "the gap audit at FR-11 should surface the answer". I deferred this to impl-wheel decision D-3 in `plan.md §4` — impl-wheel reads `archiveWorkflow` at start of Phase 6 and decides whether `_chainParentAfterArchive` is a port-from-shell or already-present. The audit-row (§dispatcher-audit row 5) is honest: "Verify whether [archive helper] handles composition parent-cursor advance. If not, add a parallel branch."
- **PRD R-7 (cache redeploy fragility)**: PRD said "document the canonical cleanup path in audit-pr's prompt". I documented it in `plan.md §3` (backup at `/tmp/wheel-cache-backup-pr200`) — this is the cleanest signalling I could give without putting it in audit-pr's prompt directly (audit-pr will read plan.md anyway).

## What I had to infer

- **Existing TS helper inventory**: I asserted `resolveNextIndex`, `advancePastSkipped`, `stateClearAwaitingUserInput`, `stateRemoveTeam`, `contextCaptureOutput`, `contextBuild` SHOULD exist in TS. I did NOT verify each by `git grep` because the spec/plan/tasks chaining requirement was tight. T-003 in tasks.md makes verification the FIRST impl step. If helpers are missing, contracts §1 instructs impl-wheel to port them and update the contract before using.
- **`dispatchTeamDelete` is a stub**: confirmed by reading `dispatch.ts:902-910`. Returns `{decision: 'approve'}` only. This is the largest single gap in the PRD scope and warrants a dedicated phase (7d). If shell `dispatch_team_delete` is more complex than I sampled (lines 2375–2489), impl-wheel may need to extend phase 7d.
- **`dispatchTeammate` `contextWriteTeammateFiles` missing**: confirmed by reading TS lines 524–629 vs shell lines 1806/1827. TS just registers the teammate in state; shell ALSO writes context.md + assign_inputs.json into output_dir. Without this, ALL team fixtures will fail because spawned agents have no context. This is BIG — likely the root cause of why `/wheel:wheel-test` Phase 4 is 0/3.

## Surprises in the gap audit

- **Deactivate handler is a no-op in TS**: I expected `/wheel:wheel-stop` to be ~broken because activation cascade was the focus of PR #200 — but I didn't expect the deactivate handler to literally be `console.log(JSON.stringify({hookEventName: 'PostToolUse'}))` with NO archive logic. This means orphan state files accumulate forever under TS today and is probably part of why baseline is 0/109 (orphan state contamination). Phase 9 lifts this from "smoke gate annoyance" to "hook-audit row 1 — load-bearing".
- **`console.error('DEBUG ...')` calls scattered through both `dispatchAgent` AND `post-tool-use.ts`**: this is rough — debug prints made it into the cascade work. Cleanup is one-line easy but the auditor MUST flag it (added as T-045 + T-120). I added an SC-7 `git grep -F "DEBUG" returns 0` check.
- **`dispatchAgent` line 259 sets output to `null`**: this looks like a regression from the wait-all redesign work — replacing `contextCaptureOutput` (which preserves the output file ref) with `stateSetStepOutput(..., null)`. The shell version captures the output. Listed as FR-002 A4. Worth flagging in retrospective: someone "simplified" away a load-bearing call.
- **`dispatchLoop` Bug B was PARTIALLY fixed but reverted at line 1101**: line 1009 reads `step.max_iterations` (correct), but the AFTER-substep cap check at line 1101 reads `(reState.steps[stepIndex] as any).max_iterations` (wrong). The half-fix is more confusing than no-fix because it suggests "Bug B is closed" when it's actually still open in the hot path. Worth a retrospective callout — half-applied fixes are landmines.

## Gaps that turned out smaller than expected

- **`stop`, `subagent-stop`, `teammate-idle` hooks**: I expected meaty gaps; turned out the wait-all-redesign already plumbed `engineInit` + `engineHandleHook` correctly. These are read-and-confirm passes (T-121), not big rewrites.
- **`dispatchBranch`**: only one gap (cursor advance via `resolveNextIndex` instead of raw +1). Cascade tail and predicate eval are correct.
- **`dispatchParallel`**: appears to have no gap based on the Explore-agent audit. Verification + minimal fixture is enough.

## Prompt-clarity issues for team-lead

- The team-lead's brief was clear and well-structured. The mandatory chaining (specify → plan → tasks in one pass) made me skip the slash-command invocations and write the artifacts directly — the kiln slash commands are scaffolds, but writing the four files (spec/research/contracts/plan/tasks) directly is the same end state. I think this should be made explicit in future briefs: "skip the /kiln:specify shell, write the artifacts directly per the templates" — would save a confusion-moment.
- The directive to put §baseline + §dispatcher-audit + §hook-audit ALL in `research.md` is correct and load-bearing. I did NOT put any audit content in spec.md — the spec sections cite gap rows by name. This is the right separation: spec.md = what to fix, research.md = what's broken in detail.
- The R-1 "scope freeze when tasks.md is committed" rule worked well. I felt the pull to keep digging the audit deeper (e.g., a 7th dispatchAgent sub-gap I considered: stop hook for working status with no `output_key` — auto-completes on second stop, shell line 691; TS does not handle this). I documented the temptation but did NOT add it to scope. impl-wheel can file a follow-up if it bites them.

## What I'd change in the brief

- **Pre-fetch existing helpers**: include a `git grep` line in the brief that lists which helpers exist in TS (`resolveNextIndex`, etc.) so the specifier doesn't have to defer to T-003. Would tighten the audit by ~10 minutes.
- **Mention which fixtures are most-broken**: I had to infer `team-static / team-dynamic / team-partial-failure are all 0/3` from the 0/109 number; brief could have called out which Phase has worst pass-rate to direct attention.

## Deferred / out-of-scope items (for retrospective + follow-up issues)

1. **Output-schema validation in `dispatchAgent`** — Theme H1 of `wheel-typed-schema-locality`. Scope-frozen out of this PRD. impl-wheel files follow-up issue.
2. **`dispatchAgent` stop hook with no output_key** — shell:691–715 auto-completes on second stop. TS doesn't handle this branch. Filing as follow-up issue under FR-013.
3. **`dispatchParallel` end-to-end fixture** — no `/wheel:wheel-test` Phase fixture. Vitest-only coverage per FR-007 A1. Follow-up issue if production usage surfaces.

Done. Handing off to impl-wheel.
