# Agent Friction Notes: audit-compliance

**Feature**: research-first-axis-enrichment
**Date**: 2026-04-25

---

## PRD Compliance Audit Results

### Summary

```
PRD Coverage:   100% (15/15 PRD FRs + 5/5 NFRs + 7/7 SCs have spec coverage)
FR Compliance:  100% (16/16 spec FRs implemented and tested)
- PASS:  14 test fixtures green (9 SC-AE-* + 5 foundation backward-compat)
- FIXED:  0 gaps resolved
- BLOCKED: 0
```

No blockers. Pipeline may proceed to audit-pr + audit-smoke.

---

## Phase A: PRD → Spec Coverage

### PRD FRs → Spec FRs

| PRD FR | Requirement Summary | Covering Spec FR(s) | Status |
|--------|--------------------|--------------------|--------|
| FR-001 | blast_radius in PRD frontmatter | FR-AE-001 | ✅ PASS |
| FR-002 | empirical_quality axes declaration | FR-AE-002 | ✅ PASS |
| FR-003 | research-rigor.json blast-radius table | FR-AE-003 | ✅ PASS |
| FR-004 | parse-prd-frontmatter.sh helper | FR-AE-004 | ✅ PASS |
| FR-005 | evaluate-direction.sh per-axis gate | FR-AE-005 | ✅ PASS |
| FR-006 | excluded_fixtures support | FR-AE-006 | ✅ PASS |
| FR-007 | excluded-fraction-high warning | FR-AE-007 | ✅ PASS |
| FR-008 | foundation_strict fallback gate | FR-AE-008 | ✅ PASS |
| FR-009 | gate_mode tag in aggregate verdict | FR-AE-009 | ✅ PASS |
| FR-010 | pricing.json per-model table | FR-AE-010 | ✅ PASS |
| FR-011 | compute-cost-usd.sh helper | FR-AE-011 | ✅ PASS |
| FR-012 | model-miss pricing → null (not fail) | FR-AE-012 | ✅ PASS |
| FR-013 | pricing-table-stale audit tripwire | FR-AE-013 | ✅ PASS |
| FR-014 | resolve-monotonic-clock.sh helper | FR-AE-014 | ✅ PASS |
| FR-015 | extended NDJSON + report columns | FR-AE-015, FR-AE-016 | ✅ PASS |

All 15 PRD FRs covered. **No uncovered PRD FRs.**

### PRD NFRs → Spec NFRs

| PRD NFR | Requirement Summary | Covering Spec NFR(s) | Status |
|---------|--------------------|--------------------|--------|
| NFR-001 | sub-second fixture guard (time axis skip) | NFR-AE-001 | ✅ PASS |
| NFR-002 | monotonic clock — no date +%s integer fallback | NFR-AE-006 | ✅ PASS |
| NFR-003 | backward compat: foundation fixtures pass post-extension | NFR-AE-003 | ✅ PASS |
| NFR-004 | 120-column report width invariant | NFR-AE-007 | ✅ PASS |
| NFR-005 | atomic pairing: rigor + pricing + runner in same PR | NFR-AE-005 | ✅ PASS |

All 5 PRD NFRs covered.

### PRD SCs → Spec SCs → Tests

| PRD SC | Scenario Summary | Spec SC | Test Fixture | Result |
|--------|-----------------|---------|-------------|--------|
| SC-001 | per-axis direction PASS path | SC-AE-001 | research-runner-axis-direction-pass | ✅ PASS (10 assertions) |
| SC-002 | cross-cutting min_fixtures=20 enforcement | SC-AE-002 | research-runner-axis-min-fixtures-cross-cutting | ✅ PASS (8 assertions) |
| SC-003 | infra zero-tolerance: +1 token regresses | SC-AE-003 | research-runner-axis-infra-zero-tolerance | ✅ PASS (8 assertions) |
| SC-004 | mixed-model cost calculation (4dp precision) | SC-AE-004 | research-runner-axis-cost-mixed-models | ✅ PASS (9 assertions) |
| SC-005 | fallback to foundation_strict when no empirical_quality | SC-AE-005 | research-runner-axis-fallback-strict-gate | ✅ PASS (11 assertions) |
| SC-006 | excluded_fixtures: skip + count against min_fixtures | SC-AE-006 | research-runner-axis-excluded-fixtures | ✅ PASS (14 assertions) |
| SC-007 | pricing-table-stale audit tripwire (≥180d) | SC-AE-007 | research-runner-axis-pricing-stale-audit | ✅ PASS (9 assertions) |

All 7 PRD SCs covered and verified.

### Extra spec SCs (beyond PRD)

| Spec SC | Summary | Test Fixture | Result |
|---------|---------|-------------|--------|
| SC-AE-008 | Atomic pairing tripwire (git-diff) | research-runner-axis-atomic-pairing (structural) | ✅ PASS (live git diff check) |
| SC-AE-009 | No integer-second monotonic fallback | research-runner-axis-no-monotonic-clock | ✅ PASS (6 assertions) |

---

## Phase B: Spec → Code → Test

### Spec FR Implementation Status

| FR | Description | Code Location | FR Comment | Test | Status |
|----|------------|--------------|-----------|------|--------|
| FR-AE-001 | blast_radius parsing | parse-prd-frontmatter.sh | ✅ | SC-AE-002, SC-AE-003 | ✅ |
| FR-AE-002 | empirical_quality axes parsing | parse-prd-frontmatter.sh | ✅ | SC-AE-001, SC-AE-003 | ✅ |
| FR-AE-003 | research-rigor.json table | plugin-kiln/lib/research-rigor.json | ✅ | SC-AE-002, SC-AE-003 | ✅ |
| FR-AE-004 | parse-prd-frontmatter.sh helper | plugin-wheel/scripts/harness/parse-prd-frontmatter.sh | ✅ | SC-AE-006 | ✅ |
| FR-AE-005 | evaluate-direction.sh per-axis gate | plugin-wheel/scripts/harness/evaluate-direction.sh | ✅ | SC-AE-001, SC-AE-003 | ✅ |
| FR-AE-006 | excluded_fixtures parse + skip | research-runner.sh, parse-prd-frontmatter.sh | ✅ | SC-AE-006 | ✅ |
| FR-AE-007 | excluded-fraction-high warning | research-runner.sh | ✅ | SC-AE-006 | ✅ |
| FR-AE-008 | foundation_strict fallback gate | research-runner.sh::compute_verdict_strict | ✅ | SC-AE-005 | ✅ |
| FR-AE-009 | gate_mode tag in aggregate | research-runner.sh | ✅ | SC-AE-005 | ✅ |
| FR-AE-010 | pricing.json table | plugin-kiln/lib/pricing.json | ✅ | SC-AE-004, SC-AE-007 | ✅ |
| FR-AE-011 | compute-cost-usd.sh | plugin-wheel/scripts/harness/compute-cost-usd.sh | ✅ | SC-AE-004 | ✅ |
| FR-AE-012 | model-miss → null (no fail) | compute-cost-usd.sh | ✅ | research-runner-axis-pricing-table-miss | ✅ |
| FR-AE-013 | pricing-table-stale audit tripwire | SC-AE-007 test fixture (mtime probe) | ✅ | SC-AE-007 | ✅ |
| FR-AE-014 | resolve-monotonic-clock.sh | plugin-wheel/scripts/harness/resolve-monotonic-clock.sh | ✅ | SC-AE-009 | ✅ |
| FR-AE-015 | extended NDJSON fields | research-runner.sh::run_arm | ✅ | SC-AE-004 | ✅ |
| FR-AE-016 | extended report columns | render-research-report.sh | ✅ | SC-AE-004, SC-AE-006 | ✅ |

All 16 spec FRs implemented and tested.

### Foundation Backward-Compat (NFR-AE-003)

| Fixture | Result |
|---------|--------|
| research-runner-pass-path | ✅ PASS (7 assertions) |
| research-runner-regression-detect | ✅ PASS (7 assertions) |
| research-runner-determinism | ✅ PASS (8 assertions) |
| research-runner-missing-usage | ✅ PASS (5 assertions) |
| research-runner-back-compat | ✅ PASS (4 assertions) |

All 5 foundation fixtures pass post-extension.

---

## Special Checks

### SC-AE-008: Atomic Pairing Tripwire (NFR-AE-005)

Ran `git diff main...HEAD --name-only` and confirmed all three required files present in the diff:
- ✅ `plugin-kiln/lib/research-rigor.json` — present
- ✅ `plugin-kiln/lib/pricing.json` — present
- ✅ `plugin-wheel/scripts/harness/research-runner.sh` — present

**PASS** — atomic pairing requirement satisfied.

### FR-AE-013: Pricing Table Staleness Check

`plugin-kiln/lib/pricing.json` mtime: current (0.0 days since modification).

**FRESH** — no `pricing-table-stale` finding needed. Threshold is ≥180 days; current file is far below.

### NFR-AE-009: Foundation Untouchability

Checked all 15 foundation-untouchable files listed in contracts §11:
- `plugin-wheel/scripts/harness/kiln-test.sh` — ✅ unmodified
- `plugin-wheel/scripts/harness/parse-token-usage.sh` — ✅ unmodified (this is a new file from foundation PR #176, not a modification)
- `plugin-kiln/lib/task-shapes/_index.json` — ✅ unmodified
- All remaining 12 foundation files — ✅ unmodified

**PASS** — No foundation files byte-modified.

---

## Known Spec Gap (Not a Blocker)

### FR-AE-005: equal_or_better Axis-Aware Polarity

The spec's literal formula for `equal_or_better` reads:
> `regression iff (b - c) / max(b, 1) > t/100`

This formula is correct for `accuracy` (higher-is-better) but **WRONG** for `tokens`, `time`, `cost` (lower-is-better). With `tokens, tol=0, b=100, c=101`: `(100-101)/100 = -0.01 > 0` → no regression → PASS. But SC-AE-003 requires +1 token to FAIL at infra zero-tolerance.

**Resolution in implementation**: `evaluate-direction.sh` uses axis-aware polarity:
- `accuracy`: higher-is-better → `(b-c)/max(b,1) > t/100` (matches spec literal)
- `tokens/time/cost`: lower-is-better → `(c-b)/max(b,1) > t/100` (same as `direction=lower`)

The implementation is **correct**. The spec text needs a follow-on update to make axis-aware polarity explicit. This is not a ship blocker — all tests pass.

**Recommendation**: Follow-on PR to update `spec.md` FR-AE-005 and `contracts/interfaces.md §4` to document axis-aware `equal_or_better` polarity explicitly.

---

## What Was Confusing

- **Task polling latency**: The impl-runner took ~20 minutes to complete across multiple context windows. The polling mechanism (ScheduleWakeup at 2-min intervals) worked but created many iterations of identical state-read logic.

- **SC-AE-003 vs FR-AE-005 inconsistency**: Discovered mid-audit that the spec FR's literal formula contradicts the acceptance scenario's expected behavior. The impl-runner handled this correctly with axis-aware semantics, but it would have been cleaner if the spec had been internally consistent from the start. The `equal_or_better` direction conflates two polarities without acknowledging it.

- **SC-AE-008 "fixture"**: The atomic pairing SC-AE-008 is verified structurally (via `git diff`) rather than as a standalone test fixture. This means it's not covered by the `run.sh`-per-fixture test infrastructure. The audit treated it as a structural check rather than a failing test.

- **FR-AE-013 is audit-time only**: The pricing staleness check is an auditor responsibility (this agent), not a runner gate. The spec is clear about this, but it creates an interesting split-responsibility: the tripwire lives in the SC-AE-007 test fixture's inline mtime probe logic, not in any shipped helper that future auditors would discover. A standalone `audit-pricing-staleness.sh` helper would be more discoverable.

## Where I Got Stuck

- **Context compaction**: The conversation hit the context window limit mid-audit, requiring a summary-continuation. No work was lost, but the resumption added overhead.

- **Task ID uncertainty**: The task system assigns numeric IDs, but the initial briefing referred to "task #3" and "task #4" by ordinal. After compaction, confirming the exact TaskID values required re-reading task state.

## What Could Be Improved

1. **Spec internal consistency gate**: Before impl-runner is unblocked, a specifier-side validation step could check "every SC has at least one acceptance scenario whose math is consistent with the FR formula it anchors." The SC-AE-003 vs FR-AE-005 inconsistency would have been caught at spec-time rather than implementation-time.

2. **Audit-time staleness helper**: `FR-AE-013` (pricing staleness) should ship as a standalone `audit-pricing-staleness.sh` helper that auditors invoke, rather than having the logic live only in the SC-AE-007 test fixture. Auditors across future pipelines need a discoverable entry point.

3. **SC-AE-008 structural fixture**: The atomic pairing check (`git diff main...HEAD`) is a valid structural gate, but it's currently just a mental check done by the auditor. A `run.sh` fixture that performs this check reproducibly would be more robust and would fit naturally into the `/kiln:kiln-test` harness.

4. **Polling overhead**: The two-minute polling interval during task-wait generates ~10 unnecessary context reads before the predecessor unblocks. A push-based `SendMessage` notification from impl-runner → audit-compliance (already happening) combined with a "wait for notification" model would be more efficient. The ScheduleWakeup polling was a fallback for when SendMessage might not trigger a context resume.

5. **Pricing reconciliation documentation**: The PRD had wrong opus and haiku pricing values. The reconciliation process worked (researcher-baseline confirmed correct values), but the spec should have referenced the authoritative source URL directly rather than relying on the researcher to re-derive them.
