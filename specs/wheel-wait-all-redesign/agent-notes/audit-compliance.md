# Agent Friction Notes: audit-compliance

**Feature**: wheel-wait-all-redesign
**Date**: 2026-04-30

---

## What Was Confusing

1. **Working directory drift from prior Bash commands.** An early
   `cd plugin-wheel && npx vitest run` moved the shell into
   `plugin-wheel/`, causing subsequent path lookups to fail silently
   (empty output instead of an error). This wasted cycles before I
   caught the drift with `pwd`. The prompt says "maintain current
   working directory throughout the session" — the problem is that a
   prior chained command buried the `cd` and state persists across
   tool calls. Not a workflow ambiguity per se, but a hazard for
   auditors who grep after running test suites.

2. **B-3 (archiveWorkflow wiring) ambiguity in FR-009.** FR-009 says
   "every workflow that archives goes through [archiveWorkflow]". The
   spec Foundation Note says to "extend, not replace" in-progress
   code. These two statements are in tension: if the TS dispatcher
   doesn't call `archiveWorkflow`, FR-009's "single deterministic call
   path" claim is false at the live-e2e level even though the helper
   itself is correctly implemented. The spec should have stated
   explicitly whether FR-009 means (a) the helper exists in state.ts
   or (b) all dispatch paths call it. The ambiguity caused me to spend
   extra cycles verifying which dispatch path is actually live.

3. **Live substrate determination for Phase 4.** The team-lead
   instructions say "live-substrate-first rule" with three tiers.
   Tier 1 (`/kiln:kiln-test`) — unclear whether it exists for wheel
   Phase 4 fixtures in this consumer project without checking. Tier 2
   (isolated recipe) — cannot run from sub-agent context. The
   delegation to audit-pr was clear in the end, but I had to work
   through the logic chain explicitly before concluding. A shorter
   phrase in the prompt like "Phase 4 live validation: delegate to
   audit-pr, document delegation" would have been faster.

---

## Where I Got Stuck

1. **B-3 depth-of-impact analysis.** The blocker.md B-3 note said
   "Phase 4 fixtures might still pass" without conclusively resolving
   whether the shell archive path is still live. I traced through
   `hooks/stop.sh` → `dist/hooks/stop.js` → `engineHandleHook` →
   `dispatchTeamWait` and confirmed the TS path owns hook delivery.
   Then I checked global settings.json for hook registrations (not
   finding a registered `stop.sh` shim from the dev `plugin-wheel`)
   before concluding the shell path is likely dead. This took ~4 tool
   calls. The impl-wheel note said "the audit run will confirm" —
   which is accurate but pushed the burden onto me.

2. **Waiting loop — 6 wakeup cycles.** Task #2 took ~30 minutes to
   complete after task #1 finished. I polled every ~3 minutes (10
   wakeup firings total, 6 poll cycles while #2 was in_progress). The
   3-minute interval was reasonable, but there's no "ping me when #2
   completes" mechanism. If SendMessage from impl-wheel arrived while I
   was in a sleep, that message would have woken me — and it did, on
   the final cycle. The overall wait was fine; just noting the
   inefficiency of polling vs. event-driven wakeup.

---

## What Could Be Improved

1. **FR-009 scope should be two sub-requirements:** "FR-009a: helper
   exists and is the single place that does rename + parent-update"
   and "FR-009b: all terminal-step dispatch paths call FR-009a."
   Currently only 009a is done. The spec conflates them, making it
   unclear when FR-009 is "done enough" to ship the PRD.

2. **Blocker documentation should include a "still live?" field** for
   blockers involving code paths. B-3 says "this needs wiring" but
   doesn't answer "does this break Phase 4?" definitively. A
   `live_impact: "likely breaks Phase 4 e2e"` line would make the
   risk surface immediately rather than requiring the auditor to trace
   dispatch paths.

3. **Spec SC-001 / SC-003 / SC-004 are over-specified** for a unit-test
   audit. The phase-4-fixtures-pass gate is a smoke-test concern, not
   an audit concern. Putting them in both spec.md and tasks.md (T-021,
   T-022) with "deferred to auditor" in the task notes creates
   confusion about whether the audit task is supposed to run the
   fixtures or just document the deferral. A cleaner split: SC-001/003
   belong exclusively in the smoke-tester's checklist.

4. **`engine.ts:113` stale-state read** is a subtle existing bug that
   isn't covered by a spec FR. `engineHandleHook` reads state before
   `dispatchStep` and uses that old object to decide cursor advance.
   After `dispatchTeamWait` calls `stateSetStepStatus('done')`, the
   old state still shows `pending` — so the engine's cursor advance
   never fires. The cursor advance for `team-wait` is supposed to
   happen via FR-002 (`maybeAdvanceParentTeamWaitCursor`) during the
   archive, not here. This is correct by design — but it's not
   documented in the spec or in a comment in engine.ts. Adding a
   comment noting "cursor advance for team-wait happens in FR-002,
   not here" would prevent future regressions.

---

## Verification Substrates Used

| FR / SC | Substrate used | Evidence quality |
|---|---|---|
| FR-001 | Unit test (archive-workflow.test.ts) | High — 3 direct tests |
| FR-002 | Unit test (archive-workflow.test.ts) | High — 4 direct tests |
| FR-003 | Unit test (dispatch-team-wait.test.ts) + structural (wc -l=45) | High |
| FR-004 | Unit test (dispatch-team-wait.test.ts) | High — orphan/history/live paths |
| FR-005 | Unit test (engine.test.ts) | High — teammate_idle + subagent_stop |
| FR-006 | Unit test (archive-workflow.test.ts) | High — failure bucket test |
| FR-007 | Structural grep + unit test (concurrent archive) | High — comment block confirmed |
| FR-008 | Structural grep (8 + 5 hits) + unit test (log assertions) | High |
| FR-009 | Unit test (archiveWorkflow integration) | Medium — helper tested, wiring not wired (B-3) |
| FR-010 | Structural (type inspection + test assertions) | Medium |
| FR-011 | Unit test (75 existing tests still pass) | High |
| SC-001 | DELEGATED to audit-pr | Not verified here |
| SC-002 | Structural (awk wc-l = 45 ≤ 132) | High |
| SC-003 | DELEGATED to audit-pr | Unit surrogate only |
| SC-004 | DELEGATED to audit-pr | Not verified here |
| SC-005 | Structural grep (archive_parent_update=8, wait_all_polling=5) | High |
| SC-006 | Structural grep (// FR-007 block in state.ts:4-24) | High |

---

## Whether impl Matched Spec

- **FR-001..008**: Implementation matches spec. FR comments present in
  every relevant function. Test references match acceptance scenarios.
- **FR-009**: Helper matches spec; upstream wiring deferred (B-3).
  Documented gap.
- **FR-010**: Schema is unchanged except for additive
  `failure_reason?: string` on TeammateEntry — consistent with FR-010
  "unchanged" intent (optional additive field is non-breaking).
- **FR-011**: All 75 pre-existing tests still pass. ✓
- **SC-002**: 45 lines vs ≤132 threshold. ✓ (76% under threshold)
- **Deviation noted**: `engine.ts:113` reads stale pre-dispatch state
  for cursor advance. This is correct by design (FR-002 owns team-wait
  cursor advance), but undocumented. Not a spec violation.
