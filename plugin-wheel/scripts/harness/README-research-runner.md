# research-runner.sh — Baseline-vs-Candidate Research Substrate

> One-page how-to. ≤ 200 lines (NFR-S-009).

The research runner is a sibling to `wheel-test-runner.sh` that drives the SAME stream-json substrate twice per fixture (once against a baseline plugin-dir, once against a candidate) and emits a comparative markdown report.

It exists so a PR claiming "this reduces tokens" or "this is faster" has a substrate that can run the same input against two plugin-dirs and report comparative metrics — instead of trusting the diff or running a one-off shell loop.

v1 ships TWO axes: **accuracy** (assertion pass/fail) and **tokens** (input + output + cached, parsed from the stream-json `usage` envelope). The strict gate is hardcoded: ANY regression on accuracy OR tokens fails the run.

## Quick Start

### 1. Build a corpus

```text
plugin-<name>/fixtures/<skill>/corpus/
├── 001-<slug>/
│   ├── input.json        # stream-json user envelope (verbatim — see schema below)
│   ├── expected.json     # assertion config (exit code or scratch-dir state)
│   └── metadata.yaml     # OPTIONAL — axes covered + why-this-fixture-exists prose
├── 002-<slug>/
└── 003-<slug>/
```

`<NNN-slug>`: 3-digit zero-padded sort prefix (lex order = exec order) + kebab-case slug. Regex: `^[0-9]{3}-[a-z0-9-]+$`.

### 2. Author `input.json`

A single stream-json `user` envelope. The `.message.content` is what gets sent to `claude --print`.

```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": "/kiln:kiln-version"
  }
}
```

### 3. Author `expected.json`

```json
{
  "assertion_kind": "exit-code",
  "expected_exit_code": 0
}
```

v1 supports `exit-code`, `scratch-dir-state`, and `transcript-final-envelope` assertion kinds. The runner reads `expected_exit_code` for the simple case.

### 4. (Optional) Author `metadata.yaml` — for human reviewers

```yaml
axes:
  - accuracy
  - tokens
why_this_fixture: "1-2 lines describing what about the runner this fixture exercises."
```

The runner ignores this file. Reviewers read it.

### 5. Invoke the runner

```bash
bash plugin-wheel/scripts/harness/research-runner.sh \
  --baseline /abs/path/to/baseline-plugin-dir \
  --candidate /abs/path/to/candidate-plugin-dir \
  --corpus /abs/path/to/plugin-<name>/fixtures/<skill>/corpus
```

Or via the SKILL wrapper:

```bash
/kiln:kiln-research --baseline … --candidate … --corpus …
```

### 6. Read the report

The runner emits TAP v14 on stdout + writes a markdown report to `.kiln/logs/research-<uuid>.md` (gitignored per NFR-S-004). Sample:

```markdown
# Research Run Report

**Run UUID**: 1a2b3c4d-…
**Baseline plugin-dir**: /abs/baseline
**Candidate plugin-dir**: /abs/candidate
…

## Per-Fixture Results

| Fixture | Baseline Acc | Candidate Acc | Baseline Tokens | Candidate Tokens | Δ Tokens | Verdict |
|---|---|---|---|---|---|---|
| 001-noop-passthrough | pass | pass | 19 | 19 | 0 | pass |
| 002-token-floor | pass | pass | 24 | 24 | 0 | pass |
| 003-assertion-anchor | pass | pass | 31 | 31 | 0 | pass |

## Aggregate

- **Total fixtures**: 3
- **Regressions**: 0
- **Overall**: PASS
- **Report UUID**: 1a2b3c4d-…
- **Runtime**: 142s
```

## Worked Example — Seed Corpus

A 3-fixture seed corpus ships at `plugin-kiln/fixtures/research-first-seed/corpus/`. To smoke the runner against itself:

```bash
bash plugin-wheel/scripts/harness/research-runner.sh \
  --baseline "$PWD/plugin-kiln" \
  --candidate "$PWD/plugin-kiln" \
  --corpus "$PWD/plugin-kiln/fixtures/research-first-seed/corpus"
```

Same baseline + candidate → all fixtures pass with delta ≈ 0 tokens (within the NFR-S-001 ±10/field band). Wall-clock ≈ 100–240s on the lightest profile (per spec.md §SC-S-001 reconciled budget).

## Exit Codes

- **0** — all fixtures pass (`Overall: PASS`).
- **1** — at least one fixture regression (`Overall: FAIL`).
- **2** — at least one fixture inconclusive (missing files, stalled, parse error, empty corpus, malformed args). See `Bail out!` line on stdout.

## Per-Fixture Verdict Enum

- `pass` — both arms pass assertions; token delta within tolerance.
- `regression (accuracy)` — baseline assertion passes, candidate assertion fails.
- `regression (tokens)` — candidate total tokens > baseline + 10 (NFR-S-001 reconciled tolerance).
- `regression (accuracy + tokens)` — both axes regress.
- `inconclusive (<reason>)` — missing files, stalled, parse error.

## Forward-compat: `fixture_corpus:` PRD frontmatter

A PRD that opts into research-first MAY declare:

```yaml
---
fixture_corpus: plugin-<name>/fixtures/<skill>/corpus/
---
```

The v1 runner does NOT read PRD frontmatter — that wiring lands in step 6 of the `09-research-first` phase (`research-first-build-prd-wiring`). Documenting the convention here lets step 6 ship without a contract change. Once shipped, `/kiln:kiln-build-prd` will read this field to locate the corpus automatically.

## Interaction With `/kiln:kiln-test`

The research runner is **byte-untouched-existing-files** discipline (NFR-S-002). `/kiln:kiln-test` consumers see no behavior change. The runner sources existing harness helpers (`scratch-create.sh`, `claude-invoke.sh`, etc.) as subprocesses — never modifies them.

## Concurrency

Two parallel `research-runner.sh` invocations against the same corpus do NOT collide — each gets its own UUID-namespaced report path + per-arm scratch dirs (NFR-S-007). No file-locking required.

## Determinism (NFR-S-001)

Re-running with identical baseline + candidate + corpus produces a stable run-level verdict (PASS/FAIL). Per-field token observations stay within ±10 tokens absolute per `usage` field across reruns (the empirically-grounded tolerance — see `specs/research-first-foundation/research.md §NFR-001`).

## Authoring `empirical_quality:` in PRD frontmatter

PRDs that opt into the per-axis direction gate (FR-AE-001) declare which axes
are gate-enforced via `empirical_quality:` in their YAML frontmatter:

```yaml
---
blast_radius: feature
empirical_quality: [{metric: tokens, direction: equal_or_better, priority: primary}, {metric: time, direction: lower, priority: secondary}]
---
```

- **`metric`** — one of `accuracy`, `tokens`, `time`, `cost`, `output_quality`. (`output_quality` is reserved for step 5 — declaring it in this PRD emits a warning + ignores it.)
- **`direction`** — one of `lower`, `higher`, `equal_or_better`. For lower-is-better axes (`tokens`, `time`, `cost`), `equal_or_better` is shorthand for "no degradation" (axis-aware polarity). For `accuracy`, `equal_or_better` means candidate must not drop below baseline.
- **`priority`** — `primary` or `secondary` (both gate-enforced; primary surfaces in the report header).

Pass `--prd <path>` to opt into per-axis gating. Without `--prd` (or with a PRD that has no `empirical_quality:`), the runner takes the foundation strict-gate fall-through codepath (NFR-AE-003 — backward compat).

## Configuring blast-radius rigor

`plugin-kiln/lib/research-rigor.json` maps `blast_radius:` to `min_fixtures` (corpus floor) + `tolerance_pct` (per-axis wobble budget). Default values:

| blast_radius | min_fixtures | tolerance_pct |
|---|---|---|
| `isolated` | 3 | 5 |
| `feature` | 10 | 2 |
| `cross-cutting` | 20 | 1 |
| `infra` | 20 | 0 |

The runner reads the PRD's `blast_radius:` and looks up the rigor row at startup. Corpus-floor enforcement (`min_fixtures`) is fail-fast PRE-subprocess: a 5-fixture corpus + `cross-cutting` blast → `Bail out! min-fixtures-not-met: 5 < 20`. Per-axis tolerance (`tolerance_pct`) is applied per-fixture — `infra` (0%) allows zero wobble. The rigor table is NOT overrideable per-PRD in v1.

## Time + Cost axes in reports

The runner always measures `time_seconds` (wall-clock subprocess duration via monotonic clock — `python3 time.monotonic()` preferred ladder per NFR-AE-006) and derives `cost_usd` per fixture per arm from the hand-maintained `plugin-kiln/lib/pricing.json`. Both axes appear in the report's per-fixture markdown table; gate-enforcement is opt-in via `empirical_quality:`.

**Sub-second guard (NFR-AE-001)**: when a fixture's median wall-clock across baseline + candidate is < 1.0s AND `time` is declared, the runner silently un-enforces time on that fixture (harness jitter exceeds tolerance on sub-second workloads) and emits `time-axis-skipped: <slug> wall-clock <N.Ns> below 1.0s floor` in the aggregate Warnings subsection.

**Pricing-table miss (FR-AE-012)**: when a fixture's transcript model_id is absent from `pricing.json`, that fixture's `cost_usd` is `null` + a `pricing-table-miss: <model-id>` warning is emitted. The fixture is still gate-evaluated on other axes. Edge case: if `cost` is the ONLY declared axis AND every fixture is null, the runner exits 2 (`Bail out! cost axis declared but no fixture produced a cost_usd value`).

**Pricing staleness (FR-AE-013)**: an audit-time tripwire — when `pricing.json` mtime > 180 days, the auditor emits `pricing-table-stale: <days>d since mtime` to `agent-notes/audit-compliance.md`. The runner does NOT fail on this signal.

## Pointers

- Skill wrapper: `plugin-kiln/skills/kiln-research/SKILL.md`
- Token parser helper: `plugin-wheel/scripts/harness/parse-token-usage.sh`
- Report renderer helper: `plugin-wheel/scripts/harness/render-research-report.sh`
- PRD frontmatter parser: `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh`
- Per-axis direction evaluator: `plugin-wheel/scripts/harness/evaluate-direction.sh`
- Cost deriver: `plugin-wheel/scripts/harness/compute-cost-usd.sh`
- Monotonic-clock probe: `plugin-wheel/scripts/harness/resolve-monotonic-clock.sh`
- Rigor config: `plugin-kiln/lib/research-rigor.json`
- Pricing config: `plugin-kiln/lib/pricing.json`
- Foundation spec / contracts: `specs/research-first-foundation/`
- Axis-enrichment spec / contracts: `specs/research-first-axis-enrichment/`
- Foundation PRD: `docs/features/2026-04-25-research-first-foundation/PRD.md`
- Axis-enrichment PRD: `docs/features/2026-04-25-research-first-axis-enrichment/PRD.md`
