# Research — Wheel TS Dispatcher Cascade

## Baseline

Captured 2026-05-01 on branch `build/wheel-ts-dispatcher-cascade-20260501` (HEAD = wait-all-redesign tip).

| Metric | Command | Value | Notes |
|---|---|---|---|
| `dispatchCommand` source size | `awk '/^async function dispatchCommand/,/^}/' plugin-wheel/src/lib/dispatch.ts \| wc -l` | **46 lines** | SC-004 baseline. Cap target: ≤ 76 lines (46 + 30). Soft. |
| `count-to-100` wall-clock | `/wheel:wheel-test` Phase 1 row | **60 s timeout — test never completes** | SC-002 baseline. There is no recorded "current wall-clock" because the workflow does not progress past `cursor=0` after activation; the test runner's per-phase budget expires. Target: <5 s. |
| `/wheel:wheel-test` Phase 1–3 pass rate | `.wheel/logs/test-run-20260501T194556Z.md` | **0/13** non-Phase-4 fixtures pass | SC-001 baseline. All time out at the 60 s phase budget. Orphan state files cascade across fixtures, contaminating downstream test counts (109 expected results, 0 passed). |
| Orphan state files after a `/wheel:wheel-test` run | `ls .wheel/state_*.json \| wc -l` | **14+** | SC-003 baseline. Direct evidence in the test-run report under "Orphan state". |

## Source-of-truth references

- Shell cascade canonical impl: `~/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.842/lib/dispatch.sh` — function `dispatch_step`. Read for shape; replicate per-step boundaries in TS.
- Existing TS dispatchers: `plugin-wheel/src/lib/dispatch.ts` (979 lines).
- Existing engine: `plugin-wheel/src/lib/engine.ts` — `engineHandleHook` already advances cursor +1 after each dispatch and calls `maybeArchiveTerminalWorkflow` (wait-all redesign FR-009). The cascade lives INSIDE dispatchers, BEFORE `engineHandleHook`'s post-dispatch advance.
- Existing activation kickstart (to be replaced by FR-005): `plugin-wheel/src/hooks/post-tool-use.ts` `handleActivation` lines ≈387–420 — manual `while` loop iterating auto-executable step types. This duplicates step-type classification (`step.type !== 'command' && step.type !== 'loop' && step.type !== 'branch'`) that FR-001's `isAutoExecutable` helper consolidates.
- Existing helpers reused by cascade: `resolveNextIndex`, `advancePastSkipped`, `workflowGetBranchTarget` (per PRD assumption — confirm at plan time; if missing, plan adds them or matches the shell-equivalent inline logic).

## Reconciliation notes

- SC-2 reconciliation: trivial. Baseline = "60s timeout (workflow never completes)". Target = "<5s wall-clock". Both numbers are in the test-run report.
- SC-4 reconciliation: dispatchCommand current size is 46 lines (verified via the `awk` recipe in the team-lead's brief). Soft cap ≤ 76 lines. If the cascade tail needs more lines, the PRD explicitly accepts a documented overrun.

## Risks worth flagging early

- **R-3** (post-agent cascade owner): resolved in spec §7 — dispatchAgent stays unchanged; engineHandleHook routes the next hook fire to dispatchStep on the new cursor, which cascades. Verified by FR-010 fixture #2.
- **R-4** (composition child archive → parent cascade resume): contract owned by wait-all redesign FR-009. Not extended here. Verified by FR-010 fixture #7.
- **R-5** (failed cascade leaves inconsistent state): mitigated by FR-002 step ordering — cursor advances FIRST, dispatch runs SECOND. Mid-dispatch crash is idempotent: next hook fire retries the same step.
