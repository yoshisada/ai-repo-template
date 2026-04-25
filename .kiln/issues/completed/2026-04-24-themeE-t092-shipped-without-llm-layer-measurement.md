# Theme E T092 switchover shipped without LLM-layer measurement

**Date**: 2026-04-24
**Source**: build/wheel-as-runtime-20260424 pipeline post-mortem
**Priority**: high
**Suggested command**: `/kiln:kiln-fix`
**Tags**: [auto:continuance, wheel-as-runtime, theme-E, perf]

## Description

The `/kiln:kiln-build-prd wheel-as-runtime` pipeline landed commit `a36fba1` (T092 + T097) which patches `plugin-kiln/workflows/kiln-report-issue.json` to route the background sub-agent through the consolidated `plugin-shelf/scripts/step-dispatch-background-sync.sh` wrapper instead of the original 3-call chain. This became the live runtime path for `/kiln:kiln-report-issue` on merge of PR #161.

The measurement that justified the FR-E perf claim was taken at the **bash-orchestration layer** (`time bash <chain>`), not at the layer the PRD's SC-004 cares about (LLM-tool-call round-trip latency in a real agent session). At the measured layer, the wrapper is **~9 ms slower** than the separate chain (`~126 ms` vs `~117 ms`, within noise). The hoped-for positive signal — reduced LLM-RTT — was never measured.

The right substrate for this measurement is `/kiln:kiln-test`, which invokes real `claude --print --plugin-dir …` subprocesses against `/tmp/kiln-test-<uuid>/` fixtures and observes real agent-session wall-clock. That fixture was never authored for T092.

## What should happen

1. Author `plugin-kiln/tests/kiln-report-issue-batching-perf/` with a before/after fixture:
   - Phase A: checkout `plugin-kiln/workflows/kiln-report-issue.json` at `953dec6` (pre-T092), run `/kiln:kiln-report-issue` N≥3 times, record (a) foreground wall-clock, (b) bg-dispatch → bg-log-line-appears wall-clock, (c) token usage split fg/bg.
   - Phase B: checkout HEAD, repeat with identical scratch-dir seed.
   - Commit raw numbers to `.kiln/research/wheel-step-batching-audit-2026-04-24.md` replacing the bash-layer table.
2. If bg wall-clock delta exceeds the noise floor in the positive direction → T092 is validated, SC-004 satisfied. Done.
3. If delta is flat or negative → revert T092 only (keep audit + wrapper + convention + unit + integration tests, drop the live switchover). Ship Theme E as "audit + convention" with the fixture committed as reproducible evidence.

## Why this matters

- The switchover changed a **live user-facing workflow** runtime path without evidence at the layer where FR-E's claim operates.
- Silent-failure exposure: if the wrapper hits a consumer-install environment quirk that only surfaces under real LLM dispatch, users see `/kiln:kiln-report-issue` silently no-op — exactly the failure shape this PRD was supposed to stamp out elsewhere.
- SC-004 currently reads "a measurable wall-clock speedup from FR-018's step-batching prototype, with raw before/after numbers committed in the audit doc." Today's audit doc has raw numbers but they don't show a speedup; SC-004 is technically unsatisfied.
