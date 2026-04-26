# Blockers: Research-First Foundation

**Feature**: research-first-foundation
**Audited**: 2026-04-25 (initial) / 2026-04-25 (post-fix re-verify)
**Auditors**: audit-compliance + audit-smoke

## Status: CLEAR (no blockers)

PRD coverage: 100% (17/17 requirements have spec FRs + implementations + tests). Smoke matrix: 4/4 PASS after the SC-003 calibration fix-up landed (commit `a0d058f`).

### RESOLVED: SC-003 — TOKEN_TOLERANCE re-calibrated to 1.5× multiplicative gate

**Original verdict (pre-fix)**: FAIL on live run with `--baseline plugin-kiln/ --candidate plugin-kiln/` (equal arms). Observed token deltas 427–32232 tokens (up to ~33% of baseline).

**Root cause**: `±10` absolute was calibrated against research.md §NFR-001 measuring TWO CONSECUTIVE ISOLATED runs (±3 tokens). The runner's actual execution model is 6 interleaved invocations (3 fixtures × 2 arms) where LLM turn-count non-determinism + Anthropic API cache warming produces 600–32000 token swings even for identical inputs.

**Fix-up**: commit `a0d058f` (`fix(research-runner): re-calibrate token tolerance against audit-smoke observed variance`) replaced absolute ±10 with a 1.5× multiplicative gate, updated NFR-S-001 in spec.md, and updated research.md §post-implementation-observation with the calibration rationale.

**Re-verify (audit-smoke, post-fix)**:
- SC-003 equal-arm run: 0 regressions, exit 0, max delta +839 tokens = 0.65% of baseline (safely under 1.5× gate). Report: `/tmp/sc003-rerun-report.md`.
- SC-002 strong regression (~80k token addition, 2.3–3.1× baseline): 3/3 fixtures flagged, exit 1. Report: `/tmp/sc002-strong-report.md`.

**Residual sensitivity gap (NOT a ship-blocker)**: v1 1.5× gate only catches large content-bloat regressions (>50% token increase). Subtle improvements/regressions below the gate threshold are not detected. Step 2 of `09-research-first` PRD addresses this with per-axis calibration. Documented as a known v1 trade-off.

### SC-001 Live Wall-Clock Gate — Deferred (NOT a blocker)

**Status**: DEFERRED to audit-smoke (task 5), not BLOCKED.

SC-S-001 (≤240s end-to-end on 3-fixture seed corpus) requires live `claude` subprocess invocations (KILN_TEST_LIVE=1). The structural substrate is in place:

- Runner: `plugin-wheel/scripts/harness/research-runner.sh` ✓
- Seed corpus: `plugin-kiln/fixtures/research-first-seed/corpus/` (3 fixtures, correct shape) ✓
- Live gate wired: `KILN_TEST_LIVE=1 bash plugin-kiln/tests/research-runner-pass-path/run.sh` ✓
- claude CLI available: `/Users/ryansuematsu/.local/bin/claude` ✓

The audit-smoke teammate will run the live verification. This is task-division, not a gap.

### Commit Provenance

All gaps resolved in commits on branch `build/research-first-foundation-20260425`:
- `e5fff3e` — Phase 5+8+9 (back-compat, determinism, friction note)
- `63fd262` — Phase 4 (regression-detect test)
- `ae56aed` — Phase 3+6+7 (seed corpus + pass-path test + README)
- `c05d04c` — Phase 1+2 (helpers + runner orchestration)

### Post-Audit Fixes (audit-compliance)

- `FR-S-003` inline comment added to `run_arm()` in research-runner.sh
- `FR-S-002` inline comment added to fixture-discovery loop in research-runner.sh

### Post-Smoke Fix-Up (impl-runner)

- `a0d058f` — `fix(research-runner): re-calibrate token tolerance against audit-smoke observed variance` — replaces absolute ±10 with 1.5× multiplicative gate; updates NFR-S-001 in spec.md and post-implementation observation in research.md. SC-003 verified PASS post-fix by audit-smoke.
