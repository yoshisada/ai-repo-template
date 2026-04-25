# Audit Smoke — Research-First Foundation

**Feature**: research-first-foundation
**Date**: 2026-04-25T21:30Z
**Branch**: build/research-first-foundation-20260425

---

## Smoke Matrix Results

### SC-001: Wall-clock Budget

- **Wall time observed**: 80s (SC-001/SC-003 pass-path run) / 70s (SC-002 regression run)
- **Threshold**: 240s (reconciled from 60s PRD literal per spec.md §Reconciliation Directive 1)
- **Verdict**: PASS
- **Notes**: Well within budget (~33% of threshold). The lightest-profile 6× projection from research.md (~186s) was NOT reached in practice — actual runs completed in 70–80s on these fixtures. The harness starts fast; the LLM subprocess for kiln:kiln-version completes quickly.

---

### SC-002: Regression Detection

- **Regressing candidate**: `/tmp/kiln-smoke-regress-RDpDex/plugin-kiln-regressing/` (added ~200 tokens of verbose irrelevant instructions to `skills/kiln-version/SKILL.md`)
- **Runner exit code**: 1 (regression detected) ✓
- **Fixture named in report**: YES — `001-noop-passthrough` flagged as `regression (tokens)` ✓
- **Report**: `/Users/ryansuematsu/Documents/github/personal/ai-repo-template/.kiln/logs/research-aad8c2de-eeb9-437e-b637-1d4a050f4202.md`
- **Verdict**: PASS

**Report excerpt**:
```
| 001-noop-passthrough | pass | pass | 97122 | 98162 | 1040 | regression (tokens) |
| 002-token-floor      | pass | pass | 128804 | 98178 | -30626 | pass |
| 003-assertion-anchor | pass | pass | 129473 | 64890 | -64583 | pass |
Overall: FAIL (3 fixtures, 1 regression)
```

**Observation**: Only one fixture flagged a regression even though the candidate had extra SKILL.md content. Fixtures 002 and 003 showed large NEGATIVE deltas (candidate used fewer tokens). This is consistent with Anthropic API cache warming: the earlier fixtures in the run warm the cache for later fixtures, causing large swings in `cache_creation_input_tokens` vs `cache_read_input_tokens`. The SUM remains theoretically identical but in practice, LLM non-determinism in turn count produces large variance.

---

### SC-003: Pass-When-Equal Check

- **Run**: `--baseline plugin-kiln/ --candidate plugin-kiln/` (symlink or same path)
- **Expected overall verdict**: PASS (no regression possible)
- **Actual overall verdict**: FAIL (2/3 fixtures flagged as `regression (tokens)`)
- **Report**: `/tmp/sc001-sc003-report.md` (local file — not in `.kiln/logs/` due to `--report-path` override)
- **Result**: **FAIL**

**Diagnostic**:
```
| 001-noop-passthrough | pass | pass | 96674 | 97319 | 645   | regression (tokens) |
| 002-token-floor      | pass | pass | 97068 | 96641 | -427  | pass |
| 003-assertion-anchor | pass | pass | 96994 | 129226 | 32232 | regression (tokens) |
Overall: FAIL (3 fixtures, 2 regressions)
```

**Root cause**: `TOKEN_TOLERANCE=10` (absolute tokens) is calibrated against research.md §NFR-001 which measured ±3 tokens between TWO CONSECUTIVE ISOLATED runs. In the research-runner, the two arms are interleaved across 3 fixtures (6 invocations total), and LLM non-determinism in turn count produces per-run variances of 600–32000 tokens even for identical inputs. The `003-assertion-anchor` candidate arm produced 32,232 extra tokens vs its baseline arm — almost certainly because the model took more turns to complete the `kiln:kiln-version` skill invocation in that specific run.

**Root cause (deeper)**: The `total_tokens` formula is `input + output + cached_creation + cached_read`. While the raw counts should be cache-state-invariant for the SAME content, the model's non-determinism in how many turns it takes (and therefore how much context it processes per turn) causes the cumulative totals to diverge significantly between arms.

**PI suggestion**: Replace `TOKEN_TOLERANCE` with a relative band (e.g., `±5% of baseline_tokens` with a floor of `±50` tokens absolute) to accommodate real per-run variance. Alternatively, add a `--skip-token-gate` flag for SC-003-style equal-arm runs in tests. The absolute ±10 is not defensible against actual observed variance.

---

### SC-004: Backward-Compat Check

- **Test run**: `bash plugin-kiln/tests/research-runner-back-compat/run.sh`
- **Result**: PASS (4 assertions)
- **Output**:
  ```
  PASS (4 assertions)
  ```
- **Verdict**: PASS

The allowlist of 13 harness files (wheel-test-runner.sh, claude-invoke.sh, etc.) is byte-untouched. The `research-runner.sh`, `parse-token-usage.sh`, and `render-research-report.sh` are confirmed present as net-new files. Single-`--plugin-dir` mode (existing kiln-test) is structurally unchanged.

---

## Summary

| Check | Observed | Threshold | Verdict |
|-------|----------|-----------|---------|
| SC-001: wall time | 80s (pass-path) / 70s (regression) | ≤ 240s | **PASS** |
| SC-002: regression detected | YES, `001-noop-passthrough` named | fixture must be named | **PASS** |
| SC-003: equal-input → pass | FAIL (runner exits 1, 2/3 fixtures flagged) | Overall: PASS | **FAIL** |
| SC-004: back-compat | 4/4 structural assertions pass | all pass | **PASS** |

**Overall smoke verdict: FAIL** (SC-003 regression-detection false-positive)

---

## Reports Generated

1. SC-002 (regression detection):
   `.kiln/logs/research-aad8c2de-eeb9-437e-b637-1d4a050f4202.md`

2. SC-001/SC-003 (pass-path, direct run):
   `/tmp/sc001-sc003-report.md`
   (Note: the `research-runner-pass-path/run.sh` live run writes its report to a tmp dir that is cleaned on exit. The retry above used `--report-path /tmp/sc001-sc003-report.md` to preserve it.)

---

## Friction Notes / PI Suggestions

### PI-1 (blocking): TOKEN_TOLERANCE too tight for multi-arm sequential runs

**Observed delta range** (baseline == candidate, 3 fixtures): 427–32232 tokens.
**Configured TOKEN_TOLERANCE**: 10 tokens.
**Impact**: SC-003 fails in every run. The equal-arm check is not usable as a correctness gate.

**Recommendation**: Replace absolute ±10 with a relative band. Two options:
- Option A: `max(50, baseline_tokens * 0.05)` — 5% of baseline, floored at 50. Would tolerate observed variance (32232 / 96994 = 33% — NOTE: even 5% may not be enough for outlier runs like 003-assertion-anchor which showed +33%).
- Option B: Introduce a `--token-gate-percent <N>` CLI flag; default to 20% for v1. The spec defers "per-axis direction" to step 2; the verdict logic could accept a wider gate in v1.
- Option C: Skip token-regression check entirely in v1 strict gate; assert only on accuracy (exit code). This matches the "accuracy axis only" approach until step 2 adds per-axis calibration.

**PI-2**: Consider a `--mode accuracy-only` flag that skips token comparison — useful for SC-003-style invariant tests.

**PI-3**: The `research-runner-pass-path/run.sh` LIVE mode writes its report to a tmp dir that gets cleaned by `trap`. If the run FAILs, the report is lost before it can be inspected. Consider writing the report to `.kiln/logs/` by default even in live test mode, or catching the failure before cleanup.

**PI-4**: Total token variance between arms is highly dependent on Anthropic API cache state, which is external to the test. Two consecutive runs of the same fixture can produce totals differing by 30–50% (seen: 96994 vs 129226 for identical inputs). This makes token-based regression detection unreliable for v1. The token axis should either use a much wider tolerance or be gated behind a flag.

**PI-5 (informational, not blocking)**: The SC-002 regression check detected a regression in only 1/3 fixtures (001-noop-passthrough) even though ALL fixtures use the same `kiln:kiln-version` skill and the candidate's plugin-dir had extra SKILL.md content. Fixtures 002 and 003 showed NEGATIVE deltas (candidate used fewer total tokens). This is because the serial execution order causes the candidate arms for later fixtures to have warmer caches, masking the added content's token overhead. In practice, a regression that only shows up in 1/3 fixtures is still correctly classified as FAIL, but the per-fixture reporting may confuse reviewers.

---

## What Was Confusing

- The spec reconciles TOKEN_TOLERANCE to ±10 based on "two consecutive runs, ±3 tokens observed." The research-runner's execution model is NOT two consecutive runs of the same fixture in isolation — it's 6 interleaved invocations (3 fixtures × 2 arms) where LLM turn-count non-determinism produces massive variance in cumulative totals. The ±10 threshold is only defensible for the isolated 2-run measurement, not for the interleaved multi-fixture run.

- The `research-runner-pass-path/run.sh` LIVE mode was the designated SC-001+SC-003 test, but it failed every run. The failure was not immediately obvious because the TAP output (which lists per-arm assertion results) showed all "ok" — the failure is at the AGGREGATE verdict level based on token counts.

## Where I Got Stuck

- The `research-runner-pass-path/run.sh` live run cleans its tmp dir on exit, so the report was not available for inspection after the failure. Had to re-run with a explicit `--report-path` to capture the report.

- Understanding WHY baseline==candidate produces token regressions required reading the actual token numbers in the report, which took an extra run after the initial failure.

## What Could Be Improved

- The TOKEN_TOLERANCE=10 must be increased before SC-003 can pass. This should be a follow-up issue. Suggested value: 5% of baseline tokens with a 500-token floor, or simply skip the token gate in v1 (accuracy-only mode).
- The `research-runner-pass-path/run.sh` should preserve its report on failure (trap should only clean on SUCCESS, like the scratch-dir pattern).
- The spec should note that the ±10 calibration is only valid for isolated single-fixture runs, not for multi-fixture sequential runs.
