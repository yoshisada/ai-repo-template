# Blockers: Research-First Foundation

**Feature**: research-first-foundation
**Audited**: 2026-04-25
**Auditors**: audit-compliance + audit-smoke

## Status: 1 KNOWN ISSUE (SC-003 calibration gap; non-blocking for merge)

PRD coverage: 100% (17/17 requirements have spec FRs + implementations + tests). Smoke matrix is 3/4 PASS with one calibration gap surfaced live (SC-003).

### Known Issue: SC-003 — TOKEN_TOLERANCE too tight for multi-arm runs (audit-smoke PI-1)

**Verdict**: FAIL on live run with `--baseline plugin-kiln/ --candidate plugin-kiln/` (equal arms).
**Observed token deltas (identical inputs)**: 427–32232 tokens across 3 fixtures.
**Configured `TOKEN_TOLERANCE`**: 10 (absolute).
**Root cause**: `±10` was calibrated against research.md §NFR-001 measuring TWO CONSECUTIVE ISOLATED runs (±3 tokens). The runner's actual execution model is 6 interleaved invocations (3 fixtures × 2 arms) where LLM turn-count non-determinism + Anthropic API cache warming produces 600–32000 token swings even for identical inputs. The tolerance is only defensible for the isolated 2-run measurement.

**Why non-blocking for merge**:
- Substrate, structural tests, and regression-detection (SC-002) all PASS.
- The fix is a tuning constant, not an architectural change (replace absolute `±10` with relative `±5–20%` band, or add `--mode accuracy-only` flag).
- v1 strict gate semantics (any-fixture regression → FAIL) work correctly when calibration is right; SC-002 verifies this.

**Required follow-up before declaring SC-003 GREEN**: file a tactical issue against `plugin-wheel/scripts/harness/research-runner.sh` to widen `TOKEN_TOLERANCE` to a relative band. Suggested values from audit-smoke: `max(500, baseline_tokens * 0.05)` floor, OR ship `--mode accuracy-only` for invariant-arm tests. See `specs/research-first-foundation/agent-notes/audit-smoke.md` PI-1..PI-4 for detail.

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
