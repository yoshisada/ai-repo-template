# Friction note — researcher-baseline

**Agent**: researcher-baseline
**Task**: #2 (Capture baseline measurements for SC-001 wall-time + NFR-001 token-determinism)
**Branch**: `build/research-first-foundation-20260425`
**Captured**: 2026-04-25

## What worked

- **Existing `.kiln/logs/kiln-test-*-transcript.ndjson` archive was a goldmine** —
  18 historical transcripts let me compute a wall-time distribution (min /
  median / mean / max) without needing to spin up new runs. The
  `result` envelope shape is stable: `duration_ms`, `duration_api_ms`,
  `num_turns`, and the full `usage` block (input / output /
  cache_read_input / cache_creation_input tokens) are all there. **This
  also corroborates that FR-003 needs zero new substrate work** — the
  research-first runner just has to parse what kiln-test already writes.
- **Fixture-size scan via `wc -c < inputs/initial-message.txt` + `timeout-override` in `test.yaml`**
  gave a clean ranking that surfaced
  `plugin-kiln/tests/structured-roadmap-shelf-mirror-paths/` as the cheapest
  probe (`kiln:kiln-version`, 60 s timeout-override, ~5 turns). That fixture
  ran twice in under a minute total, which fit my 15-minute budget.
- **`wheel-test-runner.sh kiln <test-name>`** is genuinely fast for unit-style
  fixtures — 31 s wall, 11 s subprocess. The 20 s harness fixed-cost is the
  load-bearing chunk, and it's the same constant per fixture, so the 6×
  projection math is clean: `6 × (subprocess + ~20 s)`.

## What was confusing

- **`verdict_emitted_iso` is 30 s-bucketed by the watcher**, not a true
  wall-time. The watcher polls every 30 s and stamps the timestamp on the
  poll-iteration that observed the result envelope. This means
  `verdict_emitted_iso − session_started_iso` rounds *up* to the nearest 30 s
  multiple — and historical timestamps cluster at 60 / 90 / 120 s with no
  values in between. The actual wall time lives in the transcript's
  `result.duration_ms`, not in the verdict timestamps. Took me one detour
  through the verdict files to figure that out. **PI-N suggestion**: have
  the watcher emit a `wall_clock_duration_ms` field in `verdict.json` derived
  from `result.duration_ms` so future researcher agents don't repeat the
  detour.
- **Verdict files don't preserve which test fixture ran**. The `.md` /
  `.json` verdict pair only carries the `scratch_uuid`, not the `test_name`
  or `test_dir`. Pairing two runs of the same fixture for a token-noise
  measurement requires fishing through the user-visible TAP output or rerunning
  the fixture under a known scratch UUID. **PI-N suggestion**: include
  `test_name` and `test_dir` (relative to repo root) in
  `kiln-test-<uuid>-verdict.json` for future cross-run reproducibility
  audits.
- **The `claude-invoke.sh` cache-warming pattern means run-A is "cold" and
  run-B is "warm".** Both my measured runs hit nearly-identical
  `cache_read_input_tokens` (113,842 → 113,842), which suggests the
  per-session cache *is* hitting consistently — but a true determinism test
  would also want to compare a run-N (fully warm) against run-1 (cold start).
  My ±3 token deltas are thus a *floor* on noise, not a representative mean.
  Specifier should weight the NFR-001 recommendation toward the looser end
  for that reason.
- **`harness-type: plugin-skill` is the only substrate available in
  v1 of kiln-test.** The PRD's seed-example physics implicitly assume this
  same substrate. If a research-first fixture wants to probe a non-skill
  axis (e.g. an agent or a workflow), the substrate-mode plumbing in
  `dispatch-substrate.sh` would also need extension. PRD §Goals scopes to
  "the existing kiln-test substrate" so this is fine for v1, but a
  follow-on PRD touching agent-mode comparisons will need to revisit.

## PI-N suggestions (for retrospective)

1. **`kiln-test-<uuid>-verdict.json` should preserve `test_name` /
   `test_dir`** so historical runs are pair-able for noise / regression /
   determinism audits without rerunning. Cheapest possible change in
   `wheel-test-runner.sh` step 6 (set up per-test env + log paths).
2. **Watcher should write a `wall_clock_duration_ms` derived from
   `result.duration_ms`** to `verdict.json`, so duration-based measurements
   don't require parsing the transcript NDJSON. Bonus: makes the verdict
   self-contained for downstream tooling (e.g. the research-first runner
   itself, which is going to want the same number).
3. **Consider exposing a "lightest-probe fixture" as a public reusable**
   under `plugin-kiln/fixtures/_probe/` (or similar). The
   `structured-roadmap-shelf-mirror-paths` fixture is structured as a unit
   test of a specific helper, but it incidentally serves as the cheapest
   stream-json probe in the repo. If the research-first phase wants a stable
   "minimal probe" baseline for future steps' physics measurements, the
   fixture should be *named* for that role, not just borrowed from another
   spec. (Defer to a step-2 / step-3 PRD; flagged here for visibility.)
4. **The 60 s SC-001 budget appears to be a concept-stage placeholder**,
   not a measurement-anchored target. Future PRDs touching wall-time
   constraints should pull a draft baseline from kiln-test logs *before*
   committing to a number — the existing `.kiln/logs/` archive is a
   first-class measurement source and should be the default reference for
   any "should run in N seconds" assertion.

## Time spent

- Reading PRD + spec dir layout: ~2 min
- Reading kiln-test substrate (claude-invoke.sh, wheel-test-runner.sh): ~3 min
- Harvesting historical transcripts (Python parse → wall-time + usage tables): ~3 min
- Running two consecutive lightest-probe runs: ~2 min wall (background)
- Writing research.md + this note: ~3 min
- **Total**: ~13 min. Within 15-min budget.
