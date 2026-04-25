# Audit Smoke — Research-First Foundation

**Feature**: research-first-foundation
**Date**: 2026-04-25T21:30Z (initial) / 2026-04-25T21:40Z (updated — post-fix re-run)
**Branch**: build/research-first-foundation-20260425

---

## Smoke Matrix Results (FINAL — after commit a0d058f fix-up)

### SC-001: Wall-clock Budget

- **Wall time observed**: 92s (SC-003 re-run) / 80s (earlier pass-path) / 82s (SC-002 strong regression)
- **Threshold**: 240s (reconciled from 60s PRD literal per spec.md §Reconciliation Directive 1)
- **Verdict**: **PASS**
- **Notes**: Well within budget (~38% of threshold). The lightest-profile 6× projection from research.md (~186s) was not reached in practice — all runs completed in 70–92s. The harness starts fast; `kiln:kiln-version` is an efficient near-no-op fixture.

---

### SC-002: Regression Detection (strong regression, post-fix)

- **Regressing candidate**: `/tmp/kiln-smoke-strong-regress-tmlOaB/plugin-kiln-strong-regressing/`
  (Added ~327KB / ~80k tokens of filler content to `skills/kiln-version/SKILL.md`)
- **Runner exit code**: 1 (regression detected) ✓
- **Fixtures named in report**: YES — all 3 fixtures flagged as `regression (tokens)` ✓
- **Report**: `/tmp/sc002-strong-report.md`
- **Verdict**: **PASS**

**Report excerpt**:
```
| 001-noop-passthrough | pass | pass | 129420 | 300753 | 171333 | regression (tokens) |
| 002-token-floor      | pass | pass | 129376 | 300398 | 171022 | regression (tokens) |
| 003-assertion-anchor | pass | pass |  96864 | 300511 | 203647 | regression (tokens) |
Overall: FAIL (3 fixtures, 3 regressions)
```

Candidate produced ~300k tokens vs baseline ~97–129k (2.3–3.1× baseline), well above the 1.5× gate.

**Note on regression sensitivity**: The v1 1.5× gate requires a large content addition (>50% token increase) to trip. A small ~200-token addition (the initial SC-002 attempt) was masked by cache-warming variance and only flagged 1/3 fixtures. The strong candidate (~80k-token addition) reliably flags all 3. impl-runner documented this sensitivity gap in research.md §post-implementation-observation as a known Step-2 concern.

---

### SC-003: Pass-When-Equal Check (re-run with 1.5× tolerance)

- **Run**: `--baseline plugin-kiln/ --candidate plugin-kiln/` (same path)
- **Expected overall verdict**: PASS
- **Actual overall verdict**: PASS ✓
- **Runner exit**: 0 ✓
- **Report**: `/tmp/sc003-rerun-report.md`
- **Verdict**: **PASS**

**Report excerpt**:
```
| 001-noop-passthrough | pass | pass | 129378 | 130217 |    839 | pass |
| 002-token-floor      | pass | pass | 162032 |  97118 | -64914 | pass |
| 003-assertion-anchor | pass | pass | 129372 | 129276 |    -96 | pass |
Overall: PASS (3 fixtures, 0 regressions)
```

Max positive delta observed: 839 tokens (0.65% of baseline 129378). 1.5× threshold would require >64,689 tokens of excess — the observed inter-run variance is comfortably below the gate.

---

### SC-004: Backward-Compat Check

- **Test run**: `bash plugin-kiln/tests/research-runner-back-compat/run.sh`
- **Result**: PASS (4 assertions)
- **Verdict**: **PASS**

The allowlist of 13 harness files (wheel-test-runner.sh, claude-invoke.sh, etc.) is byte-untouched by this PR. `research-runner.sh`, `parse-token-usage.sh`, and `render-research-report.sh` are confirmed present as net-new files. Single-`--plugin-dir` mode (existing kiln-test) is structurally unchanged.

---

## Summary (FINAL)

| Check | Observed | Threshold | Verdict |
|-------|----------|-----------|---------|
| SC-001: wall time | 92s (max across all runs) | ≤ 240s | ✅ **PASS** |
| SC-002: regression detected | YES — 3/3 fixtures flagged, exit 1 | fixture must be named | ✅ **PASS** |
| SC-003: equal-input → pass | PASS — 0 regressions, exit 0 | Overall: PASS | ✅ **PASS** |
| SC-004: back-compat | 4/4 structural assertions | all pass | ✅ **PASS** |

**Overall smoke verdict: PASS** (after commit a0d058f — 1.5× multiplicative gate)

---

## Reports Generated

1. **SC-002 (v1 small regression, pre-fix)**:
   `.kiln/logs/research-aad8c2de-eeb9-437e-b637-1d4a050f4202.md`

2. **SC-003 first attempt (pre-fix, FAIL)**:
   `/tmp/sc001-sc003-report.md`

3. **SC-002 strong regression (post-fix)**:
   `/tmp/sc002-strong-report.md`
   - Run UUID: `01f166f4-2316-4e92-b89f-1831e93316c9`

4. **SC-003 re-run (post-fix, PASS)**:
   `/tmp/sc003-rerun-report.md`
   - Run UUID: `7697cc19-cb0d-41e7-884d-6fb5d1bfe8c4`

---

## Friction Notes / PI Suggestions

### PI-1 (resolved via a0d058f): TOKEN_TOLERANCE absolute ±10 replaced with 1.5× multiplicative gate

The original ±10 absolute threshold (from spec.md NFR-S-001 reconciliation) caused SC-003 to fail on every live run. Root cause: the research-runner runs 6 interleaved invocations where LLM turn-count non-determinism produces per-run variances of 600–32,000 tokens — far exceeding ±10. The 1.5× gate (commit a0d058f) resolves SC-003.

**Residual concern (Step 2)**: The 1.5× gate is intentionally coarse. Realistic token-reduction improvements of 5–30% will NOT be detected by v1. The gate is useful only for catching large regressions (content additions that more than double plugin size). Per spec.md FR-S-005 updated language: token regression iff `candidate_total > baseline_total * 1.5`.

### PI-2: Regression sensitivity gap between v1 gate and real-world improvements

The v1 1.5× gate cannot detect a 1% improvement or a 30% regression. Step 2 (`09-research-first` phase item 2) should introduce per-axis direction enforcement with per-fixture calibrated tolerances. Until then, the token axis is only a gross sanity check (catches content-bloat, not subtle regressions).

### PI-3: `research-runner-pass-path/run.sh` cleans tmp dir on exit, losing failure report

The test uses `trap 'rm -rf "$tmp"' EXIT`. On live-mode failure, the report at `$tmp/research-test.md` is removed before it can be inspected. **Suggestion**: either write the report to `.kiln/logs/` unconditionally (not to tmp), or use a separate `trap` that only cleans on success (analogous to scratch-dir retention on fail).

### PI-4: run-to-run total token variance is large and cache-state-dependent

Observed range: 96k–162k tokens for identical `kiln:kiln-version` inputs across 6 sequential invocations. The Anthropic API cache state (server-side) determines how much of the plugin-dir content counts as `cache_creation` vs `cache_read` on each run, and this is not reproducible. The 1.5× gate accommodates this variance but the underlying unpredictability is an inherent limitation of v1's serial single-machine design.

### PI-5 (informational): Small candidate regressions masked by cache-warming order

With the original ~200-token candidate: only 1/3 fixtures detected (001-noop-passthrough). Fixtures 002 and 003 showed large NEGATIVE deltas because their candidate arms ran after the baseline had warmed the cache, masking the candidate's extra content. This "order-dependent masking" is expected under serial execution; a parallel-per-arm design (Step 3 of the research-first phase) would eliminate it.

---

## What Was Confusing

- The spec reconciled TOKEN_TOLERANCE to ±10 based on two consecutive isolated runs observing ±3 tokens. The research-runner's interleaved multi-fixture execution model was not the same measurement context — 6 sequential invocations exhibit 30–50% total-token variance driven by LLM non-determinism in turn count. The ±10 literal was unreachable without the 1.5× fix.

- The TAP output for `research-runner-pass-path/run.sh` shows all "ok" (per-arm assertion = exit code check), but the AGGREGATE verdict can still FAIL (token regression). This is confusing: 6 greens + aggregate FAIL looks like a harness bug, not a token-gate trip.

## Where I Got Stuck

- `research-runner-pass-path/run.sh` LIVE mode cleans its tmp dir on exit, so the failure report was gone. Required an extra run with explicit `--report-path` to diagnose.

- The initial SC-002 regression test used only ~200 tokens of extra content, which didn't reliably exceed even the old ±10 gate on all fixtures. Required a 327KB (~80k token) filler addition to reliably trigger the 1.5× gate.

## What Could Be Improved

- `research-runner-pass-path/run.sh` should write its report to `.kiln/logs/` even in live mode — not to a tmp dir that gets cleaned.
- The spec should note that the token gate is calibrated for content-bloat detection only (>1.5×), not subtle regressions. This should be explicit in FR-S-005.
- The SC-002 test fixture in the test suite should document what size of regression is required to trip the gate (to avoid future confusion about "my 5% regression wasn't detected").
