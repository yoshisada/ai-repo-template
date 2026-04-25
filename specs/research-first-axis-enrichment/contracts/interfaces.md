# Interface Contracts: Research-First Axis Enrichment

**Feature**: research-first-axis-enrichment
**Plan**: [../plan.md](../plan.md)
**Spec**: [../spec.md](../spec.md)
**Foundation contracts**: [`../../research-first-foundation/contracts/interfaces.md`](../../research-first-foundation/contracts/interfaces.md) (sections referenced as "foundation §N")
**Constitution Article**: VII (Interface Contracts Before Implementation — NON-NEGOTIABLE)

This document is the SINGLE SOURCE OF TRUTH for every exported function/script signature in the net-new code paths AND the additive extensions to foundation helpers. Implementation MUST match these signatures exactly. If a signature needs to change, update this contract FIRST and re-run constitution check.

Foundation contracts (foundation §1..§11) are unchanged where not extended below. Extensions are explicitly marked.

---

## §1 — Extended per-fixture result JSON shape (in-process, runner → renderer)

**Anchors**: foundation §1 + FR-AE-009, FR-AE-011, FR-AE-014, FR-AE-015.

The runner emits one JSON object per fixture (combining baseline + candidate arm observations) and pipes the array into `render-research-report.sh` on stdin. This PRD EXTENDS the foundation §1 shape additively — existing fields are preserved byte-identically; new fields are added.

**Extended shape** (canonical, sorted keys, no trailing comma — produced by `jq -c -S`):

```json
{
  "fixture_slug": "001-noop-passthrough",
  "fixture_path": "/abs/path/to/plugin-kiln/fixtures/research-first-seed/corpus/001-noop-passthrough",
  "baseline": {
    "scratch_uuid": "abc-123-...",
    "scratch_dir": "/tmp/kiln-test-abc-123-.../",
    "transcript_path": "/abs/.kiln/logs/kiln-test-abc-123-...-transcript.ndjson",
    "verdict_report_path": "/abs/.kiln/logs/kiln-test-abc-123-....md",
    "assertion_pass": true,
    "tokens": {
      "input": 12,
      "output": 7,
      "cached_creation": 0,
      "cached_read": 0,
      "total": 19
    },
    "time_seconds": 0.4523,
    "cost_usd": 0.00012,
    "model_id": "claude-opus-4-7",
    "exit_code": 0,
    "stalled": false
  },
  "candidate": { /* same shape as baseline */ },
  "delta_tokens": 0,
  "delta_time_seconds": -0.0023,
  "delta_cost_usd": -0.00001,
  "verdict": "pass",
  "per_axis_verdicts": {
    "accuracy": "pass",
    "tokens": "not-enforced",
    "time": "pass",
    "cost": "not-enforced"
  },
  "warnings": [
    "time-axis-skipped: 002-noop-tiny wall-clock 0.4s below 1.0s floor"
  ]
}
```

**New fields** (vs foundation §1):

- `baseline.time_seconds` / `candidate.time_seconds` — float, monotonic-clock-derived, 4dp precision. Per FR-AE-009.
- `baseline.cost_usd` / `candidate.cost_usd` — float (4dp) OR `null`. Per FR-AE-011 + FR-AE-012.
- `baseline.model_id` / `candidate.model_id` — string OR `null` (when `message.model` absent from transcript). Per FR-AE-011.
- `delta_time_seconds` — float (candidate - baseline).
- `delta_cost_usd` — float (candidate - baseline) OR `null` if either side is null.
- `per_axis_verdicts` — object mapping each declared axis to `pass` / `regression` / `not-enforced`. `accuracy` is always present (implicitly enforced per FR-AE-002). Other axes present iff declared in `empirical_quality:` OR if `gate_mode=foundation_strict` (which always includes `tokens`).
- `warnings` — array of per-fixture warning strings (empty if none). Includes `time-axis-skipped: <slug> wall-clock <N.Ns> below 1.0s floor` when sub-second guard fires.

**Verdict enum** (foundation §1 + extensions):

- `pass` — all per-axis verdicts pass or not-enforced.
- `regression (<axis>)` — single-axis regression.
- `regression (<axis> + <axis>)` — multi-axis regression (axes joined by ` + ` in declaration order).
- `inconclusive (<reason>)` — same as foundation §1.

**Inconclusive reasons** (extends foundation §1):

- foundation reasons: `missing-input-json`, `missing-expected-json`, `parse-error-baseline`, `parse-error-candidate`, `stalled-baseline`, `stalled-candidate`, `corpus-empty`.
- new reasons: `cost-axis-all-null` (per Edge Case "PRD declares ONLY cost and all fixtures null"), `min-fixtures-not-met` (per US-2 — fail-fast PRE-subprocess; emitted as a top-level run-level inconclusive, not per-fixture).

**Wire format**: the runner emits these as one-per-line NDJSON on stdout to the renderer. The renderer reads stdin to EOF, accumulates, then emits markdown.

---

## §2 — Extended `research-runner.sh` CLI contract

**Path**: `plugin-wheel/scripts/harness/research-runner.sh`

**Anchors**: foundation §2 + FR-AE-001, FR-AE-008, FR-AE-009, FR-AE-014.

### Synopsis (extends foundation §2 with `--prd <path>`)

```text
research-runner.sh --baseline <plugin-dir> --candidate <plugin-dir> --corpus <corpus-dir> [--prd <path>] [--report-path <path>]
```

### New required-or-optional flag

| Flag | Type | Description |
|---|---|---|
| `--prd <path>` | absolute path | Path to the calling PRD (typically `docs/features/<dated-slug>/PRD.md`). When omitted, runner takes the foundation strict-gate codepath (NFR-AE-003 / FR-AE-008). When provided, runner reads `empirical_quality:`, `blast_radius:`, `excluded_fixtures:` from the PRD's frontmatter via `parse-prd-frontmatter.sh`. |

Foundation §2 required + optional flags (`--baseline`, `--candidate`, `--corpus`, `--report-path`) are unchanged.

### Gate-mode dispatch

- **`gate_mode=foundation_strict`** — `--prd` omitted OR PRD has no `empirical_quality:`. Behavior: byte-identical to foundation §2 exit-code semantics + report shape modulo `time_seconds` / `cost_usd` columns (which ARE always populated per FR-AE-014, but NOT gate-enforced in this mode).
- **`gate_mode=per_axis_direction`** — `--prd` provided AND PRD has `empirical_quality:`. Behavior: per FR-AE-002 + FR-AE-005 + FR-AE-006.

### Stdout (extends foundation §2)

TAP v14 stream — same shape as foundation §2. The aggregate-verdict comment line MAY include `gate_mode=foundation_strict` or `gate_mode=per_axis_direction` for traceability:

```text
TAP version 14
1..6
ok 1 - 001-noop-passthrough (baseline)
ok 2 - 001-noop-passthrough (candidate)
…
# Aggregate verdict: PASS (gate_mode=per_axis_direction)
# Report: /abs/.kiln/logs/research-<uuid>.md
```

### Exit codes (foundation §2 unchanged)

| Code | Meaning |
|---|---|
| `0` | All fixtures `verdict: pass`. Run-level `PASS`. |
| `1` | At least one fixture `verdict: regression*`. Run-level `FAIL`. |
| `2` | At least one fixture `inconclusive (<reason>)` OR pre-subprocess validation failure (missing `--prd` referent file, malformed `research-rigor.json`, malformed `pricing.json`, monotonic-clock-probe abort, min-fixtures-not-met, etc.). |

### New bail-out diagnostics (additive to foundation §2)

| Condition | Message |
|---|---|
| `--prd` path doesn't exist | `Bail out! --prd path not found: <path>` |
| Unknown blast_radius value | `Bail out! unknown blast_radius: <value> (allowed: isolated\|feature\|cross-cutting\|infra)` |
| min_fixtures not met | `Bail out! min-fixtures-not-met: <N> < <M> (blast_radius: <radius>[, <K> fixtures excluded])` |
| Unknown empirical_quality metric | `Bail out! unknown metric: <metric> (allowed: accuracy\|tokens\|time\|cost\|output_quality)` |
| Unknown empirical_quality direction | `Bail out! unknown direction: <direction> (allowed: lower\|higher\|equal_or_better)` |
| Duplicate metric in empirical_quality | `Bail out! duplicate metric in empirical_quality: <metric>` |
| `research-rigor.json` malformed/missing | `Bail out! research-rigor.json malformed-or-missing: <error>` |
| `pricing.json` malformed | `Bail out! pricing.json malformed: <jq parse error>` |
| `pricing.json` missing AND cost is declared | `Bail out! cost axis declared but plugin-kiln/lib/pricing.json not found` |
| Cost axis declared AND all fixtures null | `Bail out! cost axis declared but no fixture produced a cost_usd value (all model IDs missing from pricing.json)` |
| `excluded_fixtures` path not in corpus | `Bail out! excluded_fixtures path not found in corpus: <slug>` |
| Monotonic-clock probe fails | `Bail out! no monotonic %N-precision clock available; install python3 (preferred) or coreutils (gdate)` |

### Determinism

Per NFR-AE-002 + foundation §2: identical inputs MUST produce a stable run-level verdict. `time` axis may vary; `tolerance_pct` absorbs the variance. `accuracy`, `tokens`, `cost` are deterministic given identical transcript inputs. Sub-second-fixture guard (NFR-AE-001) silently un-enforces time-axis on fixtures with median wall-clock < 1.0s.

---

## §3 — `parse-prd-frontmatter.sh` CLI contract

**Path**: `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh`

**Anchors**: FR-AE-001, FR-AE-004, FR-AE-006.

### Synopsis

```text
parse-prd-frontmatter.sh <prd-path>
```

### Args

| Position | Type | Description |
|---|---|---|
| 1 | absolute path | Path to PRD markdown file with YAML frontmatter. MUST exist. |

### Stdout

A single JSON object on stdout, sorted keys, `jq -c -S`-byte-stable:

```json
{
  "blast_radius": "isolated",
  "empirical_quality": [
    {"metric": "tokens", "direction": "equal_or_better", "priority": "primary"},
    {"metric": "time", "direction": "lower", "priority": "secondary"}
  ],
  "excluded_fixtures": [
    {"path": "002-flaky", "reason": "intermittent stream-json shape drift"}
  ]
}
```

When a field is absent from the PRD's frontmatter, the JSON emits a `null` (NOT an empty array/string). Caller distinguishes "absent" vs "empty list" via JSON null vs `[]`.

### Stderr

Diagnostics only.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Successfully parsed (even if fields are absent — null projection is still success). |
| `2` | PRD path missing OR YAML frontmatter malformed. Stderr emits `Bail out! parse error: <reason>`. |

### Implementation requirements

- MUST hand-roll a YAML frontmatter parser (PyYAML is not a kiln dependency). Same regex approach as `plugin-wheel/scripts/agents/compose-context.sh`.
- MUST validate metric ∈ {accuracy, tokens, time, cost, output_quality}, direction ∈ {lower, higher, equal_or_better}, priority ∈ {primary, secondary}, blast_radius ∈ {isolated, feature, cross-cutting, infra}. Invalid values → exit 2 with the documented `Bail out!` for the runner to surface.
- MUST be reentrant — same input → byte-identical output (NFR-AE-002 sibling).

---

## §4 — `evaluate-direction.sh` CLI contract

**Path**: `plugin-wheel/scripts/harness/evaluate-direction.sh`

**Anchors**: FR-AE-002, FR-AE-005.

### Synopsis

```text
evaluate-direction.sh --axis <axis> --direction <dir> --tolerance-pct <int> --baseline <num> --candidate <num>
```

### Required flags

| Flag | Type | Description |
|---|---|---|
| `--axis <axis>` | string | One of `accuracy` / `tokens` / `time` / `cost`. (`output_quality` is reserved; runner does not invoke this script with `output_quality` per FR-AE-001.) |
| `--direction <dir>` | string | One of `lower` / `higher` / `equal_or_better`. |
| `--tolerance-pct <int>` | non-negative int | Per-axis wobble budget. `0` = strict comparison. |
| `--baseline <num>` | non-negative number (float OK) | Baseline value for the axis on this fixture. |
| `--candidate <num>` | non-negative number (float OK) | Candidate value for the axis on this fixture. |

### Stdout

A single token on stdout — one of:

- `pass` — candidate satisfies direction within tolerance.
- `regression` — candidate violates direction beyond tolerance.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Verdict emitted (always 0 on valid inputs, regardless of pass/regression). |
| `2` | Invalid input (missing flag, unknown axis/direction, non-numeric value). Stderr emits `Bail out! <reason>`. |

### Decision logic (FR-AE-002 + FR-AE-005)

For `direction=lower`: regression iff `(candidate - baseline) / max(baseline, 1) > tolerance_pct/100`.
For `direction=equal_or_better`: regression iff `(baseline - candidate) / max(baseline, 1) > tolerance_pct/100`.
For `direction=higher`: regression iff `candidate <= baseline` (strict — tolerance does NOT lift this).
For `accuracy` axis with `direction=equal_or_better`: `pass` (assertion pass) is treated as `1.0`, `fail` as `0.0`. Regression iff `(0.0 - 1.0) / 1.0 > 0` AKA candidate=fail + baseline=pass.

### Determinism

Same inputs → byte-identical stdout. Floating-point comparison via `awk` with `-v` flag for portability.

---

## §5 — `compute-cost-usd.sh` CLI contract

**Path**: `plugin-wheel/scripts/harness/compute-cost-usd.sh`

**Anchors**: FR-AE-011, FR-AE-012.

### Synopsis

```text
compute-cost-usd.sh --pricing-json <path> --model-id <id> --input-tokens <int> --output-tokens <int> --cached-input-tokens <int>
```

### Required flags

| Flag | Type | Description |
|---|---|---|
| `--pricing-json <path>` | absolute path | Path to `plugin-kiln/lib/pricing.json`. MUST exist + be valid JSON (loud-failure per NFR-AE-007). |
| `--model-id <id>` | string OR empty | Model ID from transcript's `message.model`. Empty/missing → emit `null` + warning. |
| `--input-tokens <int>` | non-negative int | From `parse-token-usage.sh` output. |
| `--output-tokens <int>` | non-negative int | From `parse-token-usage.sh` output. |
| `--cached-input-tokens <int>` | non-negative int | Sum of `cached_creation` + `cached_read` from `parse-token-usage.sh` output (per A-AE-8). |

### Stdout

- On success: a single token on stdout — the cost in USD as a 4dp-precision float (e.g., `0.00012`).
- On model-miss: a single token `null` on stdout. Stderr emits `pricing-table-miss: <model-id>` (warning, not bail).
- On empty/missing model-id: same as model-miss (`null` + warning `pricing-table-miss: <empty>` on stderr).

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success (including the model-miss case — null is a valid result). |
| `2` | `pricing.json` malformed or missing. Stderr emits `Bail out! pricing.json malformed: <jq error>` or `Bail out! pricing.json not found: <path>`. |

### Formula (FR-AE-011)

```text
cost_usd = (input_tokens × input_per_mtok + output_tokens × output_per_mtok + cached_input_tokens × cached_input_per_mtok) / 1_000_000
```

Result rounded to 4 decimal places via `printf "%.4f"`.

### Determinism

Same inputs → byte-identical stdout (NFR-AE-002).

---

## §6 — `resolve-monotonic-clock.sh` CLI contract

**Path**: `plugin-wheel/scripts/harness/resolve-monotonic-clock.sh`

**Anchors**: FR-AE-009, NFR-AE-006.

### Synopsis

```text
resolve-monotonic-clock.sh
```

(No flags — pure environment probe.)

### Stdout

A single line on stdout — the resolved monotonic-clock invocation string. One of:

- `python3 -c 'import time; print(time.monotonic())'`
- `gdate +%s.%N`
- `/bin/date +%s.%N`

The caller captures this string and uses it via `eval` for per-fixture timing. The probe order MUST be deterministic — running twice on the same host MUST resolve to the same string both times.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | A monotonic-clock candidate was resolved. |
| `2` | All ladder rungs failed. Stderr emits `Bail out! no monotonic %N-precision clock available; install python3 (preferred) or coreutils (gdate)`. |

### Probe ladder (NFR-AE-006)

1. `python3 -c 'import time; print(time.monotonic())'` — try; if exit 0 + stdout is parseable as a non-zero float, accept.
2. `gdate +%s.%N` — try; if exit 0 + stdout matches `^[0-9]+\.[0-9]{6,}$`, accept.
3. `/bin/date +%s.%N` — try; if exit 0 + stdout matches `^[0-9]+\.[0-9]{6,}$`, accept (regex requires ≥6 fractional digits to reject BSD-date implementations that emit literal `%N`).
4. Abort with documented bail-out.

NEVER fall back to integer-second `date +%s` (would silently miss 800ms → 1.2s regressions per NFR-AE-007 loud-failure).

---

## §7 — `research-rigor.json` schema

**Path**: `plugin-kiln/lib/research-rigor.json`

**Anchors**: FR-AE-004, FR-AE-005.

### Schema

```json
{
  "isolated":      { "min_fixtures": 3,  "tolerance_pct": 5 },
  "feature":       { "min_fixtures": 10, "tolerance_pct": 2 },
  "cross-cutting": { "min_fixtures": 20, "tolerance_pct": 1 },
  "infra":         { "min_fixtures": 20, "tolerance_pct": 0 }
}
```

### Validation (loud-failure per NFR-AE-007)

- MUST be valid JSON parseable by `jq`.
- MUST contain exactly the four keys above (no more, no fewer).
- Each value MUST have exactly two keys: `min_fixtures` (non-negative int) + `tolerance_pct` (non-negative int).
- ANY validation failure → runner exits 2 at startup with `Bail out! research-rigor.json malformed-or-missing: <error>`.

---

## §8 — `pricing.json` schema

**Path**: `plugin-kiln/lib/pricing.json`

**Anchors**: FR-AE-010 (RECONCILED 2026-04-25), FR-AE-011, FR-AE-012, FR-AE-013.

### Schema (RECONCILED 2026-04-25 against research.md §FR-010)

```json
{
  "claude-opus-4-7":            { "input_per_mtok": 5.00, "output_per_mtok": 25.00, "cached_input_per_mtok": 0.50 },
  "claude-sonnet-4-6":          { "input_per_mtok": 3.00, "output_per_mtok": 15.00, "cached_input_per_mtok": 0.30 },
  "claude-haiku-4-5-20251001":  { "input_per_mtok": 1.00, "output_per_mtok": 5.00,  "cached_input_per_mtok": 0.10 }
}
```

**Numeric values are RECONCILED — DO NOT use PRD example numbers ($15/$75/$1.50 for opus, $0.80/$4.00/$0.08 for haiku). The PRD examples track legacy Opus 4/4.1 + Haiku 3.5 pricing; current rates are 1/3 the opus rate and 25% MORE than haiku.**

### Validation (loud-failure per NFR-AE-007)

- MUST be valid JSON parseable by `jq`.
- Each top-level key MUST be a model ID (string).
- Each value MUST have exactly three keys: `input_per_mtok` (non-negative number), `output_per_mtok` (non-negative number), `cached_input_per_mtok` (non-negative number).
- Malformed → runner exits 2 with `Bail out! pricing.json malformed: <jq error>`.
- Missing entirely + cost axis declared → runner exits 2 with `Bail out! cost axis declared but plugin-kiln/lib/pricing.json not found` (per Edge Case).

### Auditor mtime check (FR-AE-013, SC-AE-007)

- Auditor (NOT runner) reads `pricing.json` mtime via `stat` (cross-platform — `stat -c %Y` Linux, `stat -f %m` macOS).
- If `current_epoch - mtime > 180 * 86400`, auditor emits `pricing-table-stale: <days>d since mtime` to `agent-notes/audit-compliance.md`.
- Research run does NOT fail on this signal.

---

## §9 — Extended report markdown shape

**Path**: written to `.kiln/logs/research-<uuid>.md` (or `--report-path` override).

**Anchors**: foundation §8 + FR-AE-015, FR-AE-016, plan §Decision 1, plan §Decision 2.

### Layout (extends foundation §8)

```markdown
# Research Run Report

**Run UUID**: <uuid>
**Baseline plugin-dir**: <abs-path>
**Candidate plugin-dir**: <abs-path>
**Corpus**: <abs-path>
**PRD**: <abs-path-or-"(none — foundation strict-gate fallback)">
**Gate mode**: per_axis_direction | foundation_strict
**Blast radius**: isolated | feature | cross-cutting | infra | (n/a — strict gate)
**Rigor row**: min_fixtures=<N>, tolerance_pct=<P>
**Declared axes**: tokens (equal_or_better), time (lower) | (none — strict gate)
**Started**: <ISO-8601 UTC>
**Completed**: <ISO-8601 UTC>
**Wall-clock**: <N.N>s

## Per-Fixture Results

| Fixture | Acc B/C | Tokens B/C | Δ Tok | Time B/C | Δ Time | Cost B/C | Δ Cost | Per-Axis Verdict |
|---|---|---|---|---|---|---|---|---|
| 001-noop-passthrough | pass/pass | 19/19 | 0 | 0.45/0.43 | -0.02 | $0.00012/$0.00011 | -$0.00001 | tokens:pass, time:pass |
| 002-token-floor | pass/pass | 24/24 | 0 | 0.51/0.49 | -0.02 | $0.00015/$0.00014 | -$0.00001 | tokens:pass, time:pass |
| 003-assertion-anchor | pass/pass | 31/31 | 0 | 0.62/0.60 | -0.02 | $0.00019/$0.00018 | -$0.00001 | tokens:pass, time:pass |

## Aggregate

- **Total fixtures**: 3
- **Excluded fixtures**: 0
- **Regressions**: 0
- **Overall**: PASS
- **Report UUID**: <uuid>
- **Runtime**: <N.N>s

## Excluded Fixtures (only present when excluded_fixtures: declared)

| Fixture | Reason |
|---|---|
| 002-flaky | intermittent stream-json shape drift |

## Warnings (only present when warnings exist)

- pricing-table-miss: claude-haiku-4-7-experimental
- time-axis-skipped: 002-noop-tiny wall-clock 0.4s below 1.0s floor
- excluded-fraction-high: 4/10 (40%) exceeds 30% threshold

## Diagnostics (only present on FAIL)

For each `regression*` or `inconclusive` fixture:

- **<slug>** — verdict `<verdict-string>`
  - Baseline transcript: `<abs-path>`
  - Candidate transcript: `<abs-path>`
  - Baseline scratch (retained on fail): `<abs-path>`
  - Candidate scratch (retained on fail): `<abs-path>`
  - Per-axis breakdown: tokens=pass, time=regression(+0.5s ≥ tolerance 5%), cost=pass
```

### Constraints

- MUST fit in a 120-col terminal (NFR-S-005 + plan §Decision 1). Total width on a 30-char-slug fixture: ~118 chars.
- `Acc B/C` / `Tokens B/C` / `Time B/C` / `Cost B/C` columns use compact `B/C` shorthand (e.g., `pass/pass`, `19/19`, `0.45/0.43`, `$0.00012/$0.00011`).
- `Δ` (delta) columns adjacent to each axis surface deltas without doubling the table width.
- `Per-Axis Verdict` column emits one verdict per declared axis joined by `, ` (e.g., `tokens:pass, time:pass`).
- Aggregate section MAY exceed the foundation §8 strict 5-line invariant — it adds `Excluded fixtures` line + the optional Warnings/Excluded subsections. The CORE 5 lines (Total, Regressions, Overall, Report UUID, Runtime) are PRESERVED.
- Excluded Fixtures section: present iff `excluded_fixtures: [...]` declared.
- Warnings section: present iff at least one warning emitted.
- Diagnostics section: present iff FAIL run (foundation §8 unchanged).

### Determinism (foundation §8 sibling)

Per SC-AE-005 + foundation SC-S-006: byte-identical NDJSON input MUST produce byte-identical markdown output (modulo timestamps + UUIDs + scratch paths per the §3 exclusion comparator). Tested by `research-runner-axis-fallback-strict-gate/run.sh` for backward-compat AND foundation's `research-runner-determinism/run.sh` for re-run stability.

---

## §10 — Extended `kiln:kiln-research` SKILL contract

**Path**: `plugin-kiln/skills/kiln-research/SKILL.md`

**Anchors**: foundation §7 + FR-AE-001 (PRD-frontmatter contract).

### Frontmatter (foundation §7 unchanged + extended description)

```yaml
---
name: kiln-research
description: "Run the baseline-vs-candidate substrate against a declared fixture corpus. Emits a comparative markdown report at .kiln/logs/research-<uuid>.md with a strict-gate or per-axis-direction verdict (declared via PRD `empirical_quality:`). Required args: <baseline-plugin-dir> <candidate-plugin-dir> <corpus-dir>. Optional: --prd <path> to opt into per-axis direction enforcement."
---
```

### Body extension (foundation §7 + ~5 LoC added — total stays ≤ 50 LoC)

- Add a paragraph documenting `--prd <path>` usage and the gate-mode dispatch.
- Pointer to the extended `README-research-runner.md` for full how-to (per FR-AE-016).

### Constraints (foundation §7 unchanged)

- ≤ 50 lines total (foundation NFR-S-002 sibling — no business logic in SKILL.md).
- MUST NOT reference `plugin-kiln/scripts/...` paths (workflow portability rule).
- MUST mirror `kiln:kiln-test` SKILL.md's dual-layout sibling resolution shape.

---

## §11 — Foundation-untouchable invariant

**Anchors**: NFR-AE-009, foundation §10.

The following foundation files MUST be byte-untouched by this PRD's PR diff:

```text
plugin-wheel/scripts/harness/wheel-test-runner.sh
plugin-wheel/scripts/harness/claude-invoke.sh
plugin-wheel/scripts/harness/config-load.sh
plugin-wheel/scripts/harness/dispatch-substrate.sh
plugin-wheel/scripts/harness/fixture-seeder.sh
plugin-wheel/scripts/harness/scratch-create.sh
plugin-wheel/scripts/harness/scratch-snapshot.sh
plugin-wheel/scripts/harness/snapshot-diff.sh
plugin-wheel/scripts/harness/substrate-plugin-skill.sh
plugin-wheel/scripts/harness/tap-emit.sh
plugin-wheel/scripts/harness/test-yaml-validate.sh
plugin-wheel/scripts/harness/watcher-poll.sh
plugin-wheel/scripts/harness/watcher-runner.sh
plugin-kiln/skills/kiln-test/SKILL.md
plugin-wheel/scripts/harness/parse-token-usage.sh   # NEW — also untouchable per NFR-AE-009 (already emits all fields cost-derivation needs)
```

The following foundation files MAY be modified ONLY in additive ways that preserve foundation determinism + back-compat fixtures:

```text
plugin-wheel/scripts/harness/research-runner.sh        # extended for --prd flag, gate dispatch, time/cost capture
plugin-wheel/scripts/harness/render-research-report.sh # extended for 4 new columns + extended aggregate
plugin-wheel/scripts/harness/README-research-runner.md # extended with 3 new sections (Authoring empirical_quality, Configuring blast-radius rigor, Time + Cost axes)
plugin-kiln/skills/kiln-research/SKILL.md              # extended for --prd flag documentation; total LoC ≤ 50
```

Audit-compliance teammate MUST run `git diff main...HEAD --name-only` + check that every untouchable file is absent from output. If a touchable-but-additive file appears in the diff, audit-compliance MUST run the foundation's 5 existing test fixtures + verify diff-zero against pre-PRD outputs (modulo foundation §3 exclusion comparator).

---

## §12 — Test fixture contracts (SC-AE-* anchors)

**Path**: `plugin-kiln/tests/research-runner-axis-*/run.sh`

Each fixture's `run.sh` follows the foundation §9 shape: executable, exit 0 on pass, `mktemp -d` for scratch, clean up on success, emit `PASS`/`FAIL` final line.

| Fixture | SC anchor | Asserts |
|---|---|---|
| `research-runner-axis-direction-pass` | SC-AE-001 | empirical_quality time/tokens, candidate improves time + holds tokens flat → `Overall: PASS`. Same candidate against single-axis time-only declaration → still pass. |
| `research-runner-axis-min-fixtures-cross-cutting` | SC-AE-002 | 5-fixture corpus + cross-cutting blast → `Bail out! min-fixtures-not-met: 5 < 20` PRE-subprocess. |
| `research-runner-axis-infra-zero-tolerance` | SC-AE-003 | 20-fixture corpus + infra blast + tokens equal_or_better + 1-token regression on one fixture → `Overall: FAIL`. |
| `research-runner-axis-cost-mixed-models` | SC-AE-004 | mixed opus/haiku fixtures + reconciled pricing.json → per-fixture `cost_usd` matches hand-computed to 4dp. |
| `research-runner-axis-fallback-strict-gate` | SC-AE-005 | no `--prd` flag (or PRD with no `empirical_quality:`) → byte-identical to foundation strict-gate output modulo §3 comparator. PLUS re-runs foundation's 5 existing fixtures with diff-zero. |
| `research-runner-axis-excluded-fixtures` | SC-AE-006 | `excluded_fixtures: [{path, reason}]` skips fixture, records in "Excluded" section, counts AGAINST min_fixtures. |
| `research-runner-axis-pricing-table-miss` | FR-AE-012 / Edge case | unknown model_id → `cost_usd: null` + `pricing-table-miss: <model>` warning. Run still proceeds on other axes. |
| `research-runner-axis-no-monotonic-clock` | SC-AE-009 | mock PATH to remove python3, gdate, /bin/date — runner exits 2 at startup with documented bail-out. |
| `research-runner-axis-pricing-stale-audit` | SC-AE-007 | 200-day-old pricing.json → audit-compliance.md gets `pricing-table-stale: 200d since mtime` finding. Runner does NOT fail. |

---

## §13 — Function/exit-code summary table (Article VII canonical)

| Symbol | Path | Inputs | Output | Exit | Anchor |
|---|---|---|---|---|---|
| `research-runner.sh` (extended) | `plugin-wheel/scripts/harness/research-runner.sh` | `--baseline <dir> --candidate <dir> --corpus <dir> [--prd <path>] [--report-path <p>]` | TAP v14 stdout; markdown report at report-path | 0/1/2 | §2 |
| `parse-prd-frontmatter.sh` (NEW) | `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh` | `<prd-path>` | JSON object on stdout (jq -c -S byte-stable) | 0/2 | §3 |
| `evaluate-direction.sh` (NEW) | `plugin-wheel/scripts/harness/evaluate-direction.sh` | `--axis <a> --direction <d> --tolerance-pct <int> --baseline <num> --candidate <num>` | `pass`/`regression` token on stdout | 0/2 | §4 |
| `compute-cost-usd.sh` (NEW) | `plugin-wheel/scripts/harness/compute-cost-usd.sh` | `--pricing-json <p> --model-id <id> --input-tokens <n> --output-tokens <n> --cached-input-tokens <n>` | `<cost-usd-4dp>` or `null` token on stdout | 0/2 | §5 |
| `resolve-monotonic-clock.sh` (NEW) | `plugin-wheel/scripts/harness/resolve-monotonic-clock.sh` | (none) | resolved-clock-invocation string on stdout | 0/2 | §6 |
| `parse-token-usage.sh` | foundation §3 — UNTOUCHED | (foundation) | (foundation) | (foundation) | foundation §3 |
| `render-research-report.sh` (extended) | `plugin-wheel/scripts/harness/render-research-report.sh` | `<report-path>` arg + NDJSON stdin (extended shape per §1) | (empty stdout); markdown file with 4-column extension at report-path | 0/2 | §9 |
| `kiln:kiln-research` SKILL (extended) | `plugin-kiln/skills/kiln-research/SKILL.md` | `<baseline> <candidate> <corpus> [--prd <p>]` via `$ARGUMENTS` | passes through to runner | (matches runner) | §10 |
| `research-rigor.json` (NEW) | `plugin-kiln/lib/research-rigor.json` | (data file) | (data file) | n/a | §7 |
| `pricing.json` (NEW) | `plugin-kiln/lib/pricing.json` | (data file) | (data file) | n/a | §8 |

All implementation MUST conform to this table. Deviations require contract amendment + constitution re-check.
