# Interface Contracts: Research-First Foundation

**Feature**: research-first-foundation
**Plan**: [../plan.md](../plan.md)
**Spec**: [../spec.md](../spec.md)
**Constitution Article**: VII (Interface Contracts Before Implementation — NON-NEGOTIABLE)

This document is the SINGLE SOURCE OF TRUTH for every exported function/script signature in the net-new code paths. Implementation MUST match these signatures exactly. If a signature needs to change, update this contract FIRST and re-run constitution check.

---

## §1 — Per-fixture result JSON shape (in-process, runner → renderer)

The runner emits one JSON object per fixture (combining baseline + candidate arm observations) and pipes the array into `render-research-report.sh` on stdin.

**Shape** (canonical, sorted keys, no trailing comma — produced by `jq -c -S`):

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
    "exit_code": 0,
    "stalled": false
  },
  "candidate": {
    "scratch_uuid": "def-456-...",
    "scratch_dir": "/tmp/kiln-test-def-456-.../",
    "transcript_path": "/abs/.kiln/logs/kiln-test-def-456-...-transcript.ndjson",
    "verdict_report_path": "/abs/.kiln/logs/kiln-test-def-456-....md",
    "assertion_pass": true,
    "tokens": {
      "input": 12,
      "output": 7,
      "cached_creation": 0,
      "cached_read": 0,
      "total": 19
    },
    "exit_code": 0,
    "stalled": false
  },
  "delta_tokens": 0,
  "verdict": "pass"
}
```

**Verdict enum**: `pass` | `regression (accuracy)` | `regression (tokens)` | `regression (accuracy + tokens)` | `inconclusive (<reason>)`.

**Inconclusive reasons** (controlled vocabulary): `missing-input-json`, `missing-expected-json`, `parse-error-baseline`, `parse-error-candidate`, `stalled-baseline`, `stalled-candidate`, `corpus-empty`.

**Wire format**: the runner emits these as one-per-line NDJSON on stdout to the renderer. The renderer reads stdin to EOF, accumulates, then emits markdown.

---

## §2 — `research-runner.sh` CLI contract

**Path**: `plugin-wheel/scripts/harness/research-runner.sh`

**Anchors**: FR-S-001, FR-S-007, FR-S-008, NFR-S-002, NFR-S-007.

### Synopsis

```text
research-runner.sh --baseline <plugin-dir> --candidate <plugin-dir> --corpus <corpus-dir> [--report-path <path>]
```

### Required flags

| Flag | Type | Description |
|---|---|---|
| `--baseline <plugin-dir>` | absolute path | Plugin source root passed to `claude --plugin-dir` for the baseline arm. MUST be a directory. |
| `--candidate <plugin-dir>` | absolute path | Same shape as `--baseline`, for the candidate arm. MUST be a directory. |
| `--corpus <corpus-dir>` | absolute path | Corpus root containing fixture subdirs. MUST be a directory; MUST contain ≥ 1 fixture subdir matching `<NNN-slug>` shape. |

### Optional flags

| Flag | Type | Description |
|---|---|---|
| `--report-path <path>` | absolute path | Override report output location. Default: `.kiln/logs/research-<uuidv4>.md`. Used by tests for determinism comparison. |

### Stdout

TAP v14 stream:

```text
TAP version 14
1..<N*2>     # N fixtures × 2 arms
ok 1 - 001-noop-passthrough (baseline)
ok 2 - 001-noop-passthrough (candidate)
ok 3 - 002-token-floor (baseline)
…
# Aggregate verdict: PASS|FAIL
# Report: /abs/.kiln/logs/research-<uuid>.md
```

Per FR-S-012, two TAP lines per fixture (one per arm). Status MUST be `ok` if the per-arm subprocess exits 0 + assertion passes; `not ok` otherwise. The TAP plan-line precedes any `ok` / `not ok` (matches `wheel-test-runner.sh` ln 170-171).

### Stderr

Diagnostics + warnings only. NEVER part of the TAP stream.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | All fixtures `verdict: pass`. Run-level `PASS`. |
| `1` | At least one fixture `verdict: regression*`. Run-level `FAIL`. |
| `2` | At least one fixture `inconclusive (<reason>)` (missing files, stalled, parse error, empty corpus, malformed args). Run-level `FAIL`. Bail-out diagnostic on stderr. |

Per FR-S-008, exits MUST match the existing kiln-test orchestrator semantics.

### Bail-out diagnostics

The script emits `Bail out! <msg>` on stdout + exits 2 on:

| Condition | Message |
|---|---|
| Missing required flag | `Bail out! missing required flag: --baseline\|--candidate\|--corpus` |
| Baseline plugin-dir not found | `Bail out! baseline plugin-dir not found: <path>` |
| Candidate plugin-dir not found | `Bail out! candidate plugin-dir not found: <path>` |
| Corpus dir not found | `Bail out! corpus dir not found: <path>` |
| Corpus contains zero fixtures | `Bail out! corpus contains zero fixtures` |
| Token-parser fails | `Bail out! parse error: usage record missing in transcript for fixture <slug> arm <baseline\|candidate>` |
| `claude` CLI missing | `Bail out! claude CLI not on PATH; install Claude Code (https://docs.claude.com/en/docs/claude-code)` |

### Determinism

Per NFR-S-001 + SC-S-006, identical inputs MUST produce a stable run-level verdict + per-fixture token observations within the recalibrated noise band. The runner achieves this via: (a) `LC_ALL=C` for sort/awk; (b) `find … | sort -z` for fixture iteration; (c) `uuidgen` for `--report-path` (changes every run, but does NOT affect verdict); (d) per-arm scratch dirs created via existing `scratch-create.sh`.

### Concurrency

Per NFR-S-007, two parallel invocations against the same corpus MUST NOT collide. UUID-namespaced report paths + scratch dirs.

---

## §3 — `parse-token-usage.sh` CLI contract

**Path**: `plugin-wheel/scripts/harness/parse-token-usage.sh`

**Anchors**: FR-S-013, NFR-S-008.

### Synopsis

```text
parse-token-usage.sh <transcript-ndjson-path>
```

### Args

| Position | Type | Description |
|---|---|---|
| 1 | absolute path | Path to the NDJSON transcript file produced by the substrate (one envelope per line; the LAST envelope of type `result` carries the `usage` record). |

### Stdout

On success: a single line, whitespace-delimited:

```text
<input> <output> <cached_creation> <cached_read> <total>
```

Where `<total> = input + output + cached_creation + cached_read`. Each value is a non-negative integer. Per Assumption A-3 + FR-S-003.

### Stderr

Diagnostics only.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Successfully parsed. Stdout populated. |
| `2` | `usage` record missing OR malformed. Stderr emits `parse error: usage record missing in transcript: <path>`. NEVER silently substitute zeros (NFR-S-008 anchor). |

### Implementation requirements

- MUST use `jq` to parse stream-json envelopes. The query MUST find the LAST `result`-typed envelope and read its `.message.usage` (or equivalent path — verified empirically against current Claude Code stream-json output).
- MUST exit 2 + emit the documented diagnostic if `.message.usage` is `null` or absent. Never coerce to zero.
- MUST be reentrant — same input → same output, byte-identical (NFR-S-001 sibling).

### Future-portability (resolves OQ-S-4)

API is symmetric. A future PRD may have `wheel-test-runner.sh` consume this helper to enrich its single-arm verdict reports. This PRD does NOT make that change (NFR-S-002 forbids).

---

## §4 — `render-research-report.sh` CLI contract

**Path**: `plugin-wheel/scripts/harness/render-research-report.sh`

**Anchors**: FR-S-004, NFR-S-005, plan §Decision 2.

### Synopsis

```text
render-research-report.sh <report-path> < <ndjson-stdin>
```

### Args

| Position | Type | Description |
|---|---|---|
| 1 | absolute path | Output path for the markdown report. Caller (runner) owns generating the UUID. |

### Stdin

NDJSON stream — one per-fixture-result JSON object per line (shape per §1). EOF terminates input.

### Stdout

Empty. (Stderr emits diagnostics if input parse fails.)

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Report written successfully. |
| `2` | Stdin parse error OR write failure. Stderr emits diagnostic. |

### Output format

The renderer writes a markdown file at `<report-path>` shaped per §8.

### Determinism

Per SC-S-006: byte-identical NDJSON input MUST produce byte-identical markdown output. Tested by `research-runner-determinism/run.sh`.

---

## §5 — Corpus directory shape

**Anchors**: FR-S-002, OQ-S-1 resolution.

### Layout

```text
<corpus-root>/
├── <NNN-slug>/
│   ├── input.json         # REQUIRED — verbatim stream-json payload (single user envelope) replayed by claude-invoke.sh
│   ├── expected.json      # REQUIRED — assertion config (see schema below)
│   └── metadata.yaml      # OPTIONAL — runner ignores; reviewers consume
├── <NNN-slug>/
│   ...
```

### `<NNN-slug>` shape

- `<NNN>`: 3-digit zero-padded sort prefix. Lexicographic order = execution order.
- `<slug>`: kebab-case, [a-z0-9-]+, ≤ 30 chars.
- Combined: `^[0-9]{3}-[a-z0-9-]+$` regex match required.

### `input.json` schema

A single JSON object matching the stream-json `user` envelope shape:

```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": "<verbatim user message text — typically a /skill invocation>"
  }
}
```

The runner replays this AS-IS to `claude-invoke.sh` as the initial-message file (NOT modified, NOT escaped — it's already JSON).

### `expected.json` schema

```json
{
  "assertion_kind": "exit-code" | "scratch-dir-state" | "transcript-final-envelope",
  "expected_exit_code": 0,
  "expected_files": ["<rel-path>", ...],
  "expected_artifacts_glob": "<glob-pattern>",
  "additional_assertions_sh": "<optional path to a custom assertions.sh>"
}
```

v1 supports the three named `assertion_kind` values. The runner consumes `expected_exit_code` for the simple case + delegates `additional_assertions_sh` for the bespoke case. Mirrors the shape `wheel-test-runner.sh` already uses for `test.yaml` + `assertions.sh` — but as a JSON-typed schema for corpus reviewability.

### `metadata.yaml` schema (informational only — runner ignores)

```yaml
axes:
  - accuracy
  - tokens
why_this_fixture: "1-2 lines describing what about the runner this fixture exercises and what would make it stale."
```

---

## §6 — Performance budgets

**Anchors**: SC-S-001, SC-S-006, NFR-S-001, NFR-S-006, plan §OQ-S-2 resolution.

### SC-S-001 wall-clock budget (RECONCILED 2026-04-25)

- **PRD literal (superseded)**: under 60 seconds for 3-fixture corpus end-to-end.
- **Reconciled budget**: **≤ 240 seconds** for 3-fixture corpus end-to-end on the seed corpus (FR-S-009).
- **Source of truth**: `specs/research-first-foundation/research.md §SC-001 wall-time projection` — researcher-baseline measured ~31 s/fixture wall-time at lightest profile (subprocess 11.2 s + harness fixed-cost ~20 s), 6× projection ≈ 186 s. 240 s adds ~30% headroom.
- **Hard ceiling**: 240 s. If a future optimization PRD wants to bring this back toward 60 s, the right lever is fixture-arm parallelism (PRD Risk 3 — explicitly deferred from v1).
- **Measurement**: wall-clock from `research-runner.sh` invocation to exit. Captured by `research-runner-pass-path/run.sh` time-bracketing the runner call.

### NFR-S-001 token-determinism band (RECONCILED 2026-04-25)

- **PRD literal (superseded)**: ±2 tokens.
- **Reconciled band**: **±10 tokens absolute per `usage` field** (`input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`). The summed `total` band is ≤ ±40 tokens (4 × 10) but per-field is the controlling assertion.
- **Source of truth**: `specs/research-first-foundation/research.md §NFR-001 token-determinism` — two consecutive runs of `kiln:kiln-version` against the same plugin-dir on the same commit observed +3 wobble on `output_tokens` and `cache_creation_input_tokens`. ±10 absolute covers observed reality with headroom.
- **What the band does NOT govern**: run-level PASS/FAIL verdict stability — that is the load-bearing determinism (FR-005's strict-gate verdict on per-fixture `total_tokens` regression). The band is a sanity-check on transcript parsing only.
- **Measurement**: 3 reruns of the same baseline=candidate=fixture; max-min of each `usage` field across reruns must be ≤ 10. Captured by `research-runner-determinism/run.sh`.

---

## §7 — `kiln:kiln-research` SKILL contract

**Path**: `plugin-kiln/skills/kiln-research/SKILL.md`

**Anchors**: FR-S-007, plan §OQ-S-3 resolution.

### Frontmatter

```yaml
---
name: kiln-research
description: "Run the baseline-vs-candidate substrate against a declared fixture corpus. Emits a comparative markdown report at .kiln/logs/research-<uuid>.md with a strict-gate verdict (any regression on accuracy OR tokens fails). Three required args: <baseline-plugin-dir> <candidate-plugin-dir> <corpus-dir>."
---
```

### Body (≤ 50 LoC of skill prose)

- 1-line purpose statement.
- Invocation forms (1: full args; 2: when run from a PRD context with `fixture_corpus:` declared — currently informational, step 6 wires it).
- "What to do" block: dual-layout sibling resolution (matches `kiln:kiln-test` SKILL.md line 33-40) + invocation:
  ```bash
  if [ -d "${WORKFLOW_PLUGIN_DIR}/../plugin-wheel" ]; then
    WHEEL_DIR="${WORKFLOW_PLUGIN_DIR}/../plugin-wheel"
  else
    WHEEL_DIR=$(ls -d "${WORKFLOW_PLUGIN_DIR}/../../wheel"/*/ 2>/dev/null | sort -V | tail -1)
  fi
  bash "${WHEEL_DIR}/scripts/harness/research-runner.sh" $ARGUMENTS
  ```
- Exit-code legend (mirrors §2 §Exit codes).
- `.kiln/logs/research-<uuid>.md` location pointer.
- Pointer to `README-research-runner.md` for full how-to.

### Constraints

- ≤ 50 lines total (NFR-S-002 sibling — no business logic in SKILL.md).
- MUST NOT reference `plugin-kiln/scripts/...` paths (workflow portability rule).
- MUST NOT depend on `plugin-kiln/` for the runner — the runner lives in `plugin-wheel/`.
- MUST mirror `kiln:kiln-test` SKILL.md's dual-layout sibling resolution shape.

---

## §8 — Report markdown shape

**Path**: written to `.kiln/logs/research-<uuid>.md` (or `--report-path` override).

**Anchors**: FR-S-004, NFR-S-005.

### Layout

```markdown
# Research Run Report

**Run UUID**: <uuid>
**Baseline plugin-dir**: <abs-path>
**Candidate plugin-dir**: <abs-path>
**Corpus**: <abs-path>
**Started**: <ISO-8601 UTC>
**Completed**: <ISO-8601 UTC>
**Wall-clock**: <N.N>s

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
- **Report UUID**: <uuid>
- **Runtime**: <N.N>s

## Diagnostics (only present on FAIL)

For each `regression*` or `inconclusive` fixture:

- **<slug>** — verdict `<verdict-string>`
  - Baseline transcript: `<abs-path>`
  - Candidate transcript: `<abs-path>`
  - Baseline scratch (retained on fail): `<abs-path>`
  - Candidate scratch (retained on fail): `<abs-path>`
```

### Constraints

- MUST fit in a 120-col terminal (NFR-S-005). Slug column ≤ 30 chars; numeric columns right-aligned.
- MUST NOT inline JSON dumps in the body. Transcripts/scratches referenced by absolute path only.
- The `Aggregate` section MUST be exactly 5 lines: `Total fixtures`, `Regressions`, `Overall`, `Report UUID`, `Runtime`.
- The `Diagnostics` section MUST be omitted entirely on a PASS run.
- `Started`/`Completed` timestamps are the ONLY non-deterministic fields; the determinism test (SC-S-006) treats them as a modulo-list (matches `wheel-test-runner-extraction §3` exclusion-comparator pattern).

---

## §9 — Test fixture contracts (SC-S-* anchors)

**Path**: `plugin-kiln/tests/research-runner-*/run.sh`

Each fixture's `run.sh`:

- MUST be executable (`chmod +x`).
- MUST exit 0 on pass, non-zero on fail (mirrors `kiln-hygiene-backfill-idempotent/run.sh` precedent).
- MUST use `mktemp -d` for any scratch state — no writes to `$HOME` or repo working tree.
- MUST clean up tempfiles on success; MAY retain on failure for post-mortem.
- MUST emit a `PASS` or `FAIL` final line on stdout.

| Fixture | SC anchor | Asserts |
|---|---|---|
| `research-runner-pass-path` | SC-S-003 | symlinked baseline=candidate produces `Overall: PASS`, exit 0, `.kiln/logs/research-*.md` exists, 3 per-fixture rows present. |
| `research-runner-regression-detect` | SC-S-002 | engineered token-regressing fixture produces `Overall: FAIL`, exit 1, regressing slug is named in the per-fixture row. |
| `research-runner-determinism` | SC-S-006 | 3 reruns produce 3 byte-identical reports modulo §8 timestamp-modulo-list, AND token observations within recalibrated NFR-S-001 band. |
| `research-runner-missing-usage` | SC-S-007 | synthetic transcript with stripped `usage` envelope causes runner to exit 2 + emit documented `Bail out! parse error: …` diagnostic. |
| `research-runner-back-compat` | SC-S-004 | runs `wheel-test-runner.sh` (NOT `research-runner.sh`) against 3 named fixtures pre-PRD vs post-PRD; diff-zero per `wheel-test-runner-extraction/contracts/interfaces.md §3` exclusion comparator. |

---

## §10 — Backward-compat invariant (NFR-S-003)

**Anchors**: NFR-S-003, SC-S-004.

The following files MUST be byte-untouched by this PRD's PR diff:

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
```

If audit-compliance discovers any of these files in the PR diff (`git diff main...HEAD --name-only` produces a match), the PR cannot ship. The auditor MUST surface this as a NFR-S-002 violation in `agent-notes/audit-compliance.md` and the implementer MUST revert the offending change.

The ONLY permitted exception: a net-new file (e.g. `parse-token-usage.sh`) is created in `plugin-wheel/scripts/harness/`. Edits to existing files are forbidden.

---

## §11 — Function/exit-code summary table (Article VII canonical)

| Symbol | Path | Inputs | Output | Exit | Anchor |
|---|---|---|---|---|---|
| `research-runner.sh` | `plugin-wheel/scripts/harness/research-runner.sh` | `--baseline <dir> --candidate <dir> --corpus <dir> [--report-path <p>]` | TAP v14 stdout; markdown report at report-path | 0/1/2 | §2 |
| `parse-token-usage.sh` | `plugin-wheel/scripts/harness/parse-token-usage.sh` | `<transcript-ndjson-path>` | `<input> <output> <cached_creation> <cached_read> <total>` on stdout | 0/2 | §3 |
| `render-research-report.sh` | `plugin-wheel/scripts/harness/render-research-report.sh` | `<report-path>` arg + NDJSON stdin | (empty stdout); markdown file at report-path | 0/2 | §4 |
| `kiln:kiln-research` SKILL | `plugin-kiln/skills/kiln-research/SKILL.md` | `<baseline> <candidate> <corpus>` via `$ARGUMENTS` | passes through to runner; emits TAP + report | (matches runner) | §7 |

All implementation MUST conform to this table. Deviations require contract amendment + constitution re-check.
