# Research — Research-First Foundation

**Branch**: `build/research-first-foundation-20260425`
**PRD**: [docs/features/2026-04-25-research-first-foundation/PRD.md](../../docs/features/2026-04-25-research-first-foundation/PRD.md)

## §baseline (current-main measurements, captured 2026-04-25)

Baselines were captured against the existing `kiln-test` substrate
(`plugin-wheel/scripts/harness/wheel-test-runner.sh` →
`plugin-wheel/scripts/harness/claude-invoke.sh` →
`plugin-wheel/scripts/harness/substrate-plugin-skill.sh`), which already shells
out to `claude --print --verbose --input-format=stream-json
--output-format=stream-json --dangerously-skip-permissions --plugin-dir <dir>`
per-fixture. The research-first runner (FR-001) extends this same code path to
take **two** `--plugin-dir` arguments per fixture, so kiln-test's per-fixture
wall time and per-fixture token-noise are the right physics to project from.

**Substrate facts (used in projections below):**

- Subprocess shape: `claude --print --verbose --input-format=stream-json
  --output-format=stream-json --dangerously-skip-permissions --plugin-dir <dir>`.
- Per-fixture metrics already parseable from the stream-json `result` envelope:
  `usage.input_tokens`, `usage.output_tokens`,
  `usage.cache_read_input_tokens`, `usage.cache_creation_input_tokens`,
  `duration_ms`, `duration_api_ms`, `num_turns`, `total_cost_usd`,
  `is_error`, `subtype`. **No new parsing is required** for FR-003.
- Harness fixed-cost overhead per fixture (scratch-create + fixture-seeder +
  watcher startup + assertions + cleanup): **~20 s** — measured below by
  comparing wall time minus subprocess `duration_ms`.

### Sample of historical kiln-test runs (n=18 transcripts in `.kiln/logs/`)

Per-fixture subprocess wall time, harvested from
`.kiln/logs/kiln-test-*-transcript.ndjson` `result.duration_ms`:

| stat   | duration_ms (s) |
|--------|-----------------|
| min    | 28.8            |
| median | 63.2            |
| mean   | 98.8            |
| max    | 656.8 (outlier) |

(All 18 runs exited cleanly; the 656.8s outlier is a `kiln:kiln-distill` run
that did real multi-step distillation work — representative of the high end of
what a research fixture *could* look like, but not what a "seed example" would
look like.)

### SC-001 wall-time projection

**SC-001 quote** (from PRD §Success Criteria):
> "A maintainer can construct a 3-fixture corpus under
> `plugin-<name>/fixtures/<skill>/corpus/`, invoke the runner with
> `--baseline`+`--candidate`+`--corpus`, and receive a
> `.kiln/logs/research-<uuid>.md` report in **under 60s on the seed example**
> (token-only axis, no live judge)."

**Two anchor measurements (both captured 2026-04-25):**

1. **Lightest possible fixture** — `plugin-kiln/tests/structured-roadmap-shelf-mirror-paths/`
   tests `kiln:kiln-version` (a near-no-op skill that just prints the version).
   This is the *floor* for a stream-json subprocess invocation against a
   plugin-dir.
   - Subprocess `duration_ms`: **11.16 s** (run A) / **11.22 s** (run B)
   - `num_turns`: 5
   - End-to-end harness wall time (incl. scratch-create + watcher + assertions
     + cleanup): **31 s**
   - Implied harness fixed-cost overhead: ~20 s per fixture

2. **Median historical fixture** — typical multi-turn `kiln:*` skill probe
   (e.g. `kiln-hygiene-backfill-idempotent`).
   - Subprocess `duration_ms`: **63.2 s** (median across 18 runs)
   - End-to-end harness wall time: ~91 s (verdict-emitted-iso minus
     session-started-iso, which the watcher rounds to ~30 s buckets)

**6× projection (baseline×3 + candidate×3, serial)** — what SC-001 demands of
a 3-fixture corpus:

| Fixture profile        | Per-fixture subprocess | Per-fixture wall (subprocess + ~20 s harness) | 6× wall |
|------------------------|------------------------|------------------------------------------------|---------|
| Lightest (kiln-version probe) | 11.2 s          | ~31 s                                          | **~186 s (~3.1 min)** |
| Median (real skill probe)     | 63 s            | ~83 s                                          | **~498 s (~8.3 min)** |
| Min historical                | 28.8 s          | ~49 s                                          | **~294 s (~4.9 min)** |

**SC-001 budget**: 60 s.
**Verdict**: **UNREACHABLE for 3 fixtures × 2 plugin-dirs serial**, even with
the lightest possible fixture profile. The harness fixed-cost overhead
(~20 s/fixture) alone, multiplied by 6 invocations, eats 120 s — already 2× the
budget before any subprocess work. A 1-fixture × 2-plugin-dirs corpus
(~62 s wall) is right at the boundary.

**Recommendations** (pick one, ordered by least PRD churn):

- **(A) Reframe "seed example" as 1-fixture × 2-plugin-dirs** — change SC-001's
  "3-fixture corpus" to "1-fixture corpus" or to "the v1 seed-example corpus
  shipped at `plugin-kiln/fixtures/kiln-test/corpus/001-<slug>/`", and keep the
  60 s budget. This works because at the lightest profile, 1 fixture × 2 plugin-
  dirs ≈ 22 s subprocess + ~40 s harness = ~62 s. **(Tightest fit; depends on
  the v1 seed fixture being a near-no-op probe.)**
- **(B) Widen the budget to match observed reality** — change SC-001 to "under
  240 s on a 3-fixture seed corpus" (4 min). This matches the lightest-profile
  6× projection with comfortable headroom and admits real multi-turn fixtures
  without re-engineering the runner.
- **(C) Mandate plugin-dir parallelism in v1** — run baseline and candidate
  invocations of the same fixture concurrently. 3 fixtures × max(baseline,
  candidate) ≈ 3 × 31 s = ~93 s with the lightest profile. Still misses 60 s
  but is materially closer; combine with (A) for a fit. **Adds scope** —
  current `wheel-test-runner.sh` runs serial.

**Recommendation to specifier**: (B) widen to 240 s. (A) is too brittle (the
"seed example" definition becomes load-bearing on a single hand-tuned probe),
(C) adds non-trivial concurrency scope to v1 that the PRD's Risk 3 already
defers ("Single-fixture concurrency: v1 runs fixtures serially. ...
Parallelization is deferred"). 240 s preserves the spirit of "fast-enough to
re-run during a PR review" without locking the substrate to a particular
fixture shape.

### NFR-001 token-determinism

**NFR-001 quote** (from PRD §Non-Functional Requirements):
> "**NFR-001 — Determinism**: re-running the runner with identical baseline +
> candidate + corpus inputs MUST produce a per-fixture verdict that is
> identical except for token-count noise within **±2 tokens** (acknowledging
> stream-json non-determinism). The report's overall verdict (pass/fail) MUST
> be stable across reruns."

**Method**: invoked
`plugin-wheel/scripts/harness/wheel-test-runner.sh kiln structured-roadmap-shelf-mirror-paths`
twice consecutively (run A then run B), against the same plugin-dir
(`plugin-kiln`) on the same branch (`build/research-first-foundation-20260425`)
on the same commit (`947ccf4`), and parsed `usage` from each transcript's
`result` envelope.

**Run A transcript**: `.kiln/logs/kiln-test-e8fff0fe-e706-41dc-94f3-dfbab279e09b-transcript.ndjson`
**Run B transcript**: `.kiln/logs/kiln-test-dc82afa5-e78e-4e1a-a70a-63e6560059fb-transcript.ndjson`

| metric                       | A      | B      | Δ (B − A) | %       |
|------------------------------|--------|--------|-----------|---------|
| `input_tokens`               | 12     | 12     | **0**     | 0.00 %  |
| `output_tokens`              | 492    | 495    | **+3**    | +0.61 % |
| `cache_read_input_tokens`    | 113842 | 113842 | **0**     | 0.00 %  |
| `cache_creation_input_tokens`| 14278  | 14281  | **+3**    | +0.02 % |
| `num_turns`                  | 5      | 5      | 0         | 0.00 %  |
| `duration_ms`                | 11159  | 11218  | +59       | +0.53 % |
| `duration_api_ms`            | 10036  | 10259  | +223      | +2.22 % |
| `total_cost_usd`             | 0.1585 | 0.1586 | +0.0001   | —       |
| `is_error`                   | false  | false  | identical | —       |
| `stop_reason`                | end_turn | end_turn | identical | —    |

**NFR-001 budget**: ±2 tokens.

**Verdict**: **TIGHT — observed delta exceeds ±2** in both `output_tokens`
(+3) and `cache_creation_input_tokens` (+3) on the *lightest possible probe*
(`kiln:kiln-version`, 5 turns, ~500 output tokens). Multi-turn real-skill
fixtures are likely to produce *larger* per-run noise because output sampling
is multiplied across more turns. The ±2 tolerance from the PRD is a
**concept-stage estimate that the live numbers do not support**.

The pass/fail *verdict* itself was stable across both runs, and FR-005's strict
gate (regression iff candidate accuracy < baseline accuracy OR candidate total
tokens > baseline total tokens) would still produce stable verdicts when the
total-tokens delta is small relative to baseline-vs-candidate gap — but the
NFR-001 promise as written ("identical except for token-count noise within
±2 tokens") is empirically false.

**Recommendations** (pick one, ordered by least PRD churn):

- **(A) Widen absolute tolerance to ±10 tokens per `usage` field** — this
  comfortably covers the +3 observed on a near-no-op probe and gives headroom
  for richer fixtures. Easy to specify in tests; easy to enforce.
- **(B) Switch to a percent-based tolerance: ±2 % per `usage` field** — scales
  with fixture richness. The +3-on-495-output-tokens case is +0.6 %, well
  inside ±2 %. Better physics but harder to assert in unit tests when
  baselines are small (a 12-token input under ±2 % is still ±~0.24 tokens,
  i.e. 0).
- **(C) Compound tolerance: max(±5 tokens, ±1 %)** — clamps small-baseline
  noise to a sane absolute floor while letting larger fixtures flex
  proportionally. Slightly more complex to assert but most accurate to
  observed physics.

**Recommendation to specifier**: (A) widen to **±10 tokens**. The PRD scopes
v1 as "intentionally narrow" (Goals bullet 5), and the strict-gate verdict in
FR-005 is the load-bearing determinism — the per-field ±N is just a
sanity-check on transcript parsing. ±10 absolute is the cheapest spec
that survives the live-number reality without inviting NFR-001 follow-up
issues at first contact.

### Substrate-portability note (no PRD change required)

The kiln-test substrate already emits everything FR-003 asks for (input /
output / cached input tokens, plus pass/fail accuracy via the existing
assertions.sh path) inside the stream-json `result` envelope. This means
FR-003 is implementable as **JSON parsing of the existing transcript file**
written by `claude-invoke.sh` — no shape changes to claude-invoke.sh, no new
flags on the CLI subprocess, no new env vars. This corroborates NFR-002
("No fork of kiln-test") as already-satisfiable: the new `--baseline` /
`--candidate` / `--corpus` flags can live as a thin orchestration layer on
top of the existing per-fixture loop in `wheel-test-runner.sh`.

### Aggregation summary for the specifier

| Item                                  | Verdict      | Recommended change                                             |
|---------------------------------------|--------------|----------------------------------------------------------------|
| SC-001 60 s budget on 3-fixture corpus | UNREACHABLE  | Widen to **≤ 240 s** (Recommendation B above)                  |
| NFR-001 ±2 tokens per-field           | TIGHT (false) | Widen to **±10 tokens absolute** per `usage` field (Recommendation A above) |
| NFR-002 no-fork-of-kiln-test          | reachable    | No change — substrate already extensible per current shape    |
| NFR-003 backward compat (single `--plugin-dir`) | reachable | No change                                                  |
| FR-003 token capture from stream-json | reachable    | No change — `usage.{input,output,cache_read,cache_creation}_tokens` parses directly from `result` envelope |
