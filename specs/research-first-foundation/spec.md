# Feature Specification: Research-First Foundation — Fixture Corpus + Baseline-vs-Candidate Runner MVP

**Feature Branch**: `build/research-first-foundation-20260425`
**Created**: 2026-04-25
**Status**: Draft
**Input**: `docs/features/2026-04-25-research-first-foundation/PRD.md`
**Parent goal**: `.kiln/roadmap/items/2026-04-24-research-first-fixture-format-mvp.md` (phase `09-research-first`, step 1 of 7)
**Builds on**: `wheel-test-runner-extraction` (PR landed 2026-04-25 — runner now at `plugin-wheel/scripts/harness/wheel-test-runner.sh`)
**Baseline research**: `specs/research-first-foundation/research.md` (read first; thresholds in §Success Criteria are reconciled against it per §1.5 Baseline Checkpoint).

## Overview

The kiln test substrate (`plugin-wheel/scripts/harness/wheel-test-runner.sh`) drives a single `claude --print --verbose --input-format=stream-json … --plugin-dir <dir>` subprocess per fixture and asserts pass/fail on the resulting scratch dir. Today there is exactly ONE plugin-dir per run. This PRD adds a parallel mode that takes TWO plugin-dirs (a baseline and a candidate), runs the same fixture against each, captures per-run metrics (assertion verdict + input/output/cached tokens parsed from the stream-json transcript), and emits a comparative report at `.kiln/logs/research-<uuid>.md` with a strict-gate run-level verdict.

Three concrete deliverables:

1. **Runner extension** — a sibling script under `plugin-wheel/scripts/harness/` (e.g. `research-runner.sh`) that the `/kiln:kiln-test` SKILL does NOT touch. The new script shells into the existing wheel-test-runner internals (config-load, scratch-create, fixture-seeder, claude-invoke, watcher-runner, snapshot) twice per fixture — once per plugin-dir — without forking those helpers (NFR-002).
2. **Corpus convention** — a committed-on-disk directory shape under `plugin-<name>/fixtures/<skill>/corpus/<NNN-slug>/` with `input.json`, `expected.json`, `metadata.yaml` per fixture. v1 declared-corpus only — no synthesizer.
3. **Comparative report + strict gate** — markdown table per fixture (baseline vs candidate accuracy + tokens + delta + verdict) plus 5-line aggregate summary (N fixtures, M regressions, overall pass/fail). v1 strict gate: ANY regression on accuracy OR tokens fails the run. No per-axis `direction:`, no time/cost axes, no judge — those are explicitly deferred to steps 2-5 of the research-first phase.

## Resolution of PRD Open Questions

The PRD `## Risks & Open Questions` left one explicit Open Question and four risks. Resolved as follows; rationale anchors specific FRs/NFRs.

- **OQ-S-1 (`metadata.yaml` required vs optional)**: RESOLVED — **optional**. v1 runner ignores `metadata.yaml`; it exists for human reviewers/diff-readers. Step-4 synthesizer may later promote it to required as a corpus-level invariant. Encoded in **FR-S-002**.
- **R-S-1 (stream-json token-field stability)**: ACKNOWLEDGED. Failure surface is a `null` return from the parser (loud, not silent). Encoded as **NFR-S-008** — the runner MUST fail loudly with a `parse error: usage record missing` diagnostic on `null` token reads, never silently treat null as zero. Step 3 owns the stale-pricing-style mtime check; not this PRD.
- **R-S-2 (cached-vs-fresh token bookkeeping)**: ACKNOWLEDGED. v1 sums `input + output + cached_creation + cached_read` as `total_tokens` per the existing kiln-test parser. Step 3 splits these. Encoded as **FR-S-003** + **Assumption A-3**.
- **R-S-3 (single-fixture concurrency)**: ACKNOWLEDGED. v1 runs fixtures serially; baseline + candidate per fixture also run serially. Parallelization deferred. Encoded as **NFR-S-005** + **Assumption A-4**.
- **R-S-4 (1-fixture corpus passes-or-fails on a single example)**: ACKNOWLEDGED. v1 does NOT enforce a minimum corpus count — that's step 2's `min_fixtures` rigor scaling. Encoded as **Assumption A-2**.
- **R-S-5 (report-uuid collision)**: ACKNOWLEDGED. UUIDv4 collision is vanishingly improbable; the existing `uuidgen` substrate is reused. Encoded in **FR-S-004**.

## Reconciliation Against Researcher-Baseline (§1.5 Baseline Checkpoint) — RECONCILED 2026-04-25

The `researcher-baseline` teammate committed `specs/research-first-foundation/research.md §baseline` (207 lines, captured 2026-04-25) with two reconciliation directives. Both accepted.

### Directive 1 — SC-001 60s budget UNREACHABLE on 3-fixture corpus

**Live measurement** (research.md §SC-001 wall-time projection):

- Lightest possible fixture (`kiln:kiln-version` near-no-op probe): subprocess 11.2 s + harness fixed-cost ~20 s = **~31 s wall per fixture**.
- 6× projection (3 fixtures × 2 plugin-dirs serial) at lightest profile: **~186 s wall**.
- 6× projection at median historical fixture: **~498 s wall**.
- Harness fixed-cost overhead (~20 s/fixture × 6 = 120 s) alone exceeds the 60 s PRD literal.

**Reconciliation accepted**: Researcher Recommendation (B) — **widen SC-S-001 to ≤ 240 s on the 3-fixture seed corpus**. Rationale: (B) preserves the spirit of "fast-enough to re-run during a PR review" while admitting realistic fixture profiles + the existing serial-execution scope (PRD Risk 3 already defers parallelism). 240 s is roughly the lightest-profile 6× projection plus headroom (~30%), matching the ±20% precedent band from `wheel-test-runner-extraction §1.5` once you account for the irreducible 20s harness floor.

Recommendation (A) (reframe "seed example" as 1-fixture × 2-plugin-dirs) was rejected because it makes the seed-fixture definition load-bearing on a single hand-tuned probe and brittle to plugin-dir cache state. Recommendation (C) (mandate plugin-dir parallelism in v1) was rejected as out-of-scope per PRD Risk 3.

SC-S-001 **literal recalibrated to ≤ 240 s** below.

### Directive 2 — NFR-001 ±2 tokens TIGHT (empirically false on lightest probe)

**Live measurement** (research.md §NFR-001 token-determinism, two consecutive runs of `kiln:kiln-version` against the same plugin-dir on the same commit):

- `output_tokens`: A=492, B=495, **Δ +3** (+0.61%).
- `cache_creation_input_tokens`: A=14278, B=14281, **Δ +3** (+0.02%).
- `input_tokens` / `cache_read_input_tokens` / `num_turns` / `is_error`: identical (Δ 0).

The +3 token wobble on a 5-turn near-no-op probe means the ±2 token literal cannot be defended; richer multi-turn fixtures will produce larger per-field noise.

**Reconciliation accepted**: Researcher Recommendation (A) — **widen NFR-S-001 to ±10 tokens absolute per `usage` field**. Rationale: (A) covers the observed +3 with comfortable headroom for richer fixtures, is trivially assertable in tests, and preserves the load-bearing determinism (FR-005's strict-gate verdict on per-fixture `total_tokens` regression). The ±10 floor is what the live physics support without inviting NFR-001 follow-up issues at first contact.

Recommendation (B) (±2% per field) was rejected because small-baseline fixtures (12-token input) collapse to 0 effective tolerance. Recommendation (C) (compound max(±5, ±1%)) was rejected as more accurate but assertion-complex for v1.

NFR-S-001 **literal recalibrated to ±10 tokens absolute per `usage` field** below.

### Directive 3 (informational) — Substrate already emits everything FR-003 needs

Per research.md §Substrate-portability note: the existing kiln-test stream-json `result` envelope already exposes `usage.input_tokens`, `usage.output_tokens`, `usage.cache_read_input_tokens`, `usage.cache_creation_input_tokens`, `duration_ms`, `duration_api_ms`, `num_turns`, `total_cost_usd`. **No claude-invoke.sh shape change required**. This corroborates NFR-S-002 (no fork) — the new runner is a pure orchestration layer.

Encoded as **A-7** (Assumption) below + drives **Phase A** of `/tasks` (the token parser is already-implementable from existing transcripts).

### Reconciliation provenance

- Recalibrated SC-S-001 wall-clock budget: **≤ 240 s** (was: PRD literal 60 s).
- Recalibrated NFR-S-001 token-determinism band: **±10 tokens absolute per `usage` field** (was: PRD literal ±2 tokens).
- All other PRD thresholds unchanged.
- `## Open Questions` OQ-S-2 below RESOLVED to (B)+(A) per this reconciliation.

Specifier note (per orchestrator FR-009): thresholds reconciled against research.md §baseline.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — A maintainer runs baseline-vs-candidate against a 3-fixture corpus and gets a pass-verdict report (Priority: P1 — HARD GATE)

As a kiln maintainer planning a token-reduction change, I declare a 3-fixture corpus under `plugin-kiln/fixtures/<skill>/corpus/`, run the new runner with `--baseline <dir> --candidate <dir> --corpus <dir>`, and receive a markdown report at `.kiln/logs/research-<uuid>.md` with one row per fixture (baseline+candidate accuracy + tokens + delta + per-fixture verdict) and a 5-line aggregate summary (N fixtures, M regressions, overall verdict). On a non-regressing candidate, the overall verdict is "pass" and the runner exits 0.

**Why this priority**: P1 hard gate — this is the entire substrate. Every later step in the `09-research-first` phase (per-axis direction, time/cost, synthesizer, judge, build-prd wiring, classifier inference) is unbuildable without it.

**Independent Test**: Build a 3-fixture corpus where the candidate is a literal symlink-copy of the baseline plugin-dir (so accuracy is identical and tokens are within ±2 per NFR-S-001). Run the runner. Assert: report file exists at `.kiln/logs/research-<uuid>.md`, contains 3 per-fixture rows + a "pass" aggregate, exit code is 0, runtime is within the SC-001-recalibrated wall-clock budget.

**Acceptance Scenarios**:

1. **Given** a corpus dir with 3 fixtures (each with `input.json` + `expected.json`; `metadata.yaml` optional) and a baseline + candidate plugin-dir where the candidate is byte-identical to the baseline, **When** I run `bash plugin-wheel/scripts/harness/research-runner.sh --baseline <b> --candidate <c> --corpus <p>`, **Then** the runner emits `.kiln/logs/research-<uuid>.md` with 3 rows of `verdict: pass` and an aggregate `Overall: PASS (3 fixtures, 0 regressions)`, and exits 0.
2. **Given** the same corpus + run, **When** I read the report's per-fixture rows, **Then** each row contains baseline accuracy (pass/fail), candidate accuracy, baseline token total, candidate token total, delta tokens, and per-fixture verdict — rendered as a markdown table that fits in a terminal without horizontal scroll.
3. **Given** the runner finishes, **When** I inspect `/tmp/kiln-test-*` scratch dirs, **Then** all baseline-arm AND candidate-arm scratches are cleaned up on pass (matches existing kiln-test cleanup discipline), retained on fail.

---

### User Story 2 — A regressing candidate produces a "fail" verdict that names the regressing fixture (Priority: P1 — HARD GATE)

As a kiln maintainer reviewing a PR that claims "this is faster," I want a deliberately-regressing candidate (one fixture's input crafted to spend more output tokens) to produce a "fail" overall verdict and identify which fixture regressed by name in the per-fixture row.

**Why this priority**: P1 hard gate — without this, the substrate offers no negative-case signal and the strict gate is theoretical. The PRD's SC-002 anchors this exact scenario.

**Independent Test**: Author a 2-fixture corpus where fixture #2's candidate plugin-dir is intentionally diff'd from the baseline to produce more output tokens (e.g., a verbose-mode flag flip in a stub skill). Run the runner. Assert: per-fixture row 2 has `verdict: regression` and the row text names fixture #2 (the slug, not just an index). Aggregate line says `Overall: FAIL (2 fixtures, 1 regression: <slug>)`. Runner exits 1.

**Acceptance Scenarios**:

1. **Given** a 2-fixture corpus where fixture `002-verbose-output` is engineered such that the candidate produces strictly more output tokens than the baseline, **When** I run the runner, **Then** the report's row for `002-verbose-output` has `verdict: regression` and the per-fixture verdict column shows `regression (tokens: +N)` where N is the observed delta.
2. **Given** the same run, **When** I read the aggregate summary, **Then** it reads `Overall: FAIL` and explicitly names the regressing fixture's slug.
3. **Given** the runner exits, **When** I check the exit code, **Then** it is `1` (matches the existing kiln-test exit semantics: 0 = all pass, 1 = at least one fail, 2 = inconclusive).
4. **Given** the candidate ALSO regresses on accuracy (fails an assertion that baseline passes), **When** the runner runs, **Then** the per-fixture verdict shows `regression (accuracy)` distinctly from `regression (tokens)` — the report disambiguates which axis tripped.

---

### User Story 3 — Existing single-`--plugin-dir` `/kiln:kiln-test` invocations are byte-identically unaffected (Priority: P1 — HARD GATE)

As any developer running `/kiln:kiln-test` today, my invocation continues to work byte-identically post-PRD. The new runner is a sibling script — `wheel-test-runner.sh` is not modified, no new flags appear in its CLI, no behavior changes for single-plugin-dir mode.

**Why this priority**: P1 hard gate — backward compat is non-negotiable. PRD NFR-003 + SC-004 anchor this. If the v1 substrate disturbs existing kiln-test consumers, the PR cannot ship.

**Independent Test**: Run `/kiln:kiln-test plugin-kiln <existing-fixture>` pre-PRD and post-PRD against three representative fixtures (same set used by `wheel-test-runner-extraction` SC-R-1: `kiln-distill-basic`, `kiln-hygiene-backfill-idempotent`, plus one fast-deterministic fixture). Snapshot-diff the verdict reports via the same per-fixture exclusion comparator from `wheel-test-runner-extraction/contracts/interfaces.md §3`. Delta = 0 lines beyond the modulo-list.

**Acceptance Scenarios**:

1. **Given** the PRD shipped, **When** I run `/kiln:kiln-test plugin-kiln kiln-hygiene-backfill-idempotent`, **Then** TAP v14 stdout matches pre-PRD line-for-line modulo timestamps, the verdict report path is `.kiln/logs/kiln-test-<uuid>.md` (not `research-<uuid>.md`), and the exit code matches.
2. **Given** the same run, **When** I `git grep -nF` the changed files in this PR, **Then** `wheel-test-runner.sh` and its existing helpers (`config-load.sh`, `scratch-create.sh`, `fixture-seeder.sh`, `claude-invoke.sh`, `watcher-runner.sh`, `tap-emit.sh`, `test-yaml-validate.sh`, `dispatch-substrate.sh`, `substrate-plugin-skill.sh`, `scratch-snapshot.sh`, `snapshot-diff.sh`, `watcher-poll.sh`) are byte-untouched. Touch is permitted ONLY if `assertions.sh`-style logic must factor out (see plan).
3. **Given** the SKILL.md at `plugin-kiln/skills/kiln-test/SKILL.md`, **When** I diff it against main, **Then** zero lines change — the new runner is invoked via a separate skill or direct shell invocation, not through `/kiln:kiln-test`.

---

### User Story 4 — A maintainer can opt a PRD into research-first by declaring `fixture_corpus:` (Priority: P2)

As an early adopter, I declare `fixture_corpus: plugin-<name>/fixtures/<skill>/corpus/` in my PRD frontmatter. The runner reads that field to locate the corpus when invoked from a PRD-context wrapper (manual today; step 6 wires it into `/kiln:kiln-build-prd`).

**Why this priority**: P2 — the substrate is callable manually via explicit `--corpus <dir>` even without the frontmatter contract. Frontmatter declaration is the polish that lets later phase steps (especially step 6) read the corpus path from the PRD without prompting. Useful but not gating for v1 substrate.

**Independent Test**: Author a sample PRD with `fixture_corpus: plugin-kiln/fixtures/research-first-seed/corpus/` in the frontmatter. The v1 runner does NOT read PRD frontmatter directly (that's step 6), but the convention is documented in the README so step 6 can land it without a contract change. Validate the docs by running `git grep -nF 'fixture_corpus:' plugin-kiln/scripts/kiln-test/README.md` (or the equivalent location agreed in plan).

**Acceptance Scenarios**:

1. **Given** the PRD shipped, **When** I read the substrate's how-to README (per SC-005), **Then** it documents the `fixture_corpus:` PRD-frontmatter convention as the forward-compat handle for step 6.
2. **Given** I declare `fixture_corpus:` in a PRD, **When** I invoke the v1 runner manually with `--corpus <same-path>`, **Then** the run succeeds — the PRD frontmatter is informational in v1, not consumed by the runner.

---

### User Story 5 — The substrate is documented in a one-page how-to (Priority: P2)

As a maintainer who has never used the runner before, I can read a single README under `plugin-kiln/scripts/kiln-test/README.md` (or sibling location agreed in plan) and successfully construct a 3-fixture corpus + invoke the runner without reading any runner source.

**Why this priority**: P2 — discoverability/adoption. PRD SC-005 anchors this. Without docs, step 1's substrate is shipped-but-invisible; later phase steps can't iterate on it.

**Independent Test**: A reviewer who has never seen the runner reads only the README and follows the `Quick Start` to: (a) construct a 3-fixture corpus, (b) invoke `bash plugin-wheel/scripts/harness/research-runner.sh --baseline … --candidate … --corpus …`, (c) read the `.kiln/logs/research-<uuid>.md` report. They complete (a)+(b)+(c) without consulting source. Verified by recording the reviewer's friction-note in `agent-notes/qa-reviewer.md` (informal — not a hard gate).

**Acceptance Scenarios**:

1. **Given** the PRD shipped, **When** I read the README, **Then** it contains a "Quick Start" block with: corpus directory shape (3 files per fixture), the runner invocation shape, the report path, and a worked example using the seed corpus from FR-S-009.
2. **Given** the README, **When** I `wc -l` it, **Then** it is ≤ 200 lines (one-page invariant — PRD SC-005 prose).

---

### Edge Cases

- **Empty corpus** — runner invoked with `--corpus` pointing at a directory with zero fixture subdirs MUST exit 2 (inconclusive) with TAP-shaped diagnostic `Bail out! corpus contains zero fixtures`. NOT a pass.
- **Corpus path does not exist** — runner exits 2 with `Bail out! corpus dir not found: <path>`.
- **Baseline plugin-dir does not exist** — runner exits 2 with `Bail out! baseline plugin-dir not found: <path>`. Same shape for candidate.
- **One-armed mismatch** — fixture passes baseline but fails candidate's assertions: per-fixture verdict is `regression (accuracy)`, run-level verdict is FAIL.
- **Stream-json transcript missing usage record** — token parser returns null, runner exits 2 with `Bail out! parse error: usage record missing in transcript for fixture <slug> arm <baseline|candidate>` (NFR-S-008 anchor).
- **Watcher classifies stalled** — same shape as kiln-test's existing stall handling: report-level verdict is FAIL, per-fixture row marks `stalled (arm: baseline)` or `stalled (arm: candidate)` and includes scratch-dir path for post-mortem. (Reuses watcher-runner; no new code.)
- **Identical baseline = candidate (symlink)** — should produce token-count delta within NFR-S-001 noise band (±2 tokens or whatever the recalibration sets). Per-fixture verdict: `pass`. This is User Story 1's positive-control fixture.
- **Concurrent runner invocations** — two parallel `research-runner.sh` calls produce distinct `research-<uuid>.md` paths via `uuidgen`. No locking required.
- **Corpus fixture dir missing required files** — fixture `<slug>` has no `input.json`: skip with `# SKIP <slug> — missing input.json` in the report's per-fixture row, classify as `inconclusive`, run-level verdict is FAIL (treat skip strictly per PRD's "ANY regression fails" + the v1 conservative stance that "skip ≠ pass").

## Requirements *(mandatory)*

### Functional Requirements

- **FR-S-001** *(from: PRD FR-001)* — A new runner script MUST live at `plugin-wheel/scripts/harness/research-runner.sh` and accept three required flags: `--baseline <plugin-dir>`, `--candidate <plugin-dir>`, `--corpus <corpus-dir>`. Exactly two `--plugin-dir`-shape inputs (one baseline, one candidate) per invocation; not configurable to one or three. The script MUST NOT modify `wheel-test-runner.sh` or any of its existing helpers (NFR-S-002 anchor).
- **FR-S-002** *(from: PRD FR-002 + OQ-S-1 resolution)* — The corpus directory shape MUST be `<corpus-root>/<NNN-slug>/` with files: `input.json` (REQUIRED — verbatim stream-json payload replayed as the user envelope), `expected.json` (REQUIRED — assertion config consumed by the existing `assertions.sh`-equivalent verdict logic), `metadata.yaml` (OPTIONAL — axes covered + why-this-fixture-exists prose; runner ignores it). `<NNN-slug>` is a 3-digit zero-padded sort prefix + kebab-case slug.
- **FR-S-003** *(from: PRD FR-003 + R-S-2 resolution)* — The runner MUST capture per fixture per arm (baseline + candidate): (a) the assertion verdict (pass/fail) from the existing kiln-test verdict-extraction logic, and (b) tokens — input + output + cached_creation + cached_read summed as `total_tokens` (per the stream-json `usage` record in the `result`-typed envelope). The token parser MUST be a single shared helper (NFR-S-002).
- **FR-S-004** *(from: PRD FR-004)* — The runner MUST emit a comparative report at `.kiln/logs/research-<uuid>.md` (UUIDv4 via `uuidgen`) containing: (a) one markdown-table row per fixture with columns `Fixture | Baseline Acc | Candidate Acc | Baseline Tokens | Candidate Tokens | Δ Tokens | Verdict`; (b) a 5-line aggregate summary at the end with `Total fixtures: N`, `Regressions: M`, `Overall: PASS|FAIL`, `Report UUID: <uuid>`, `Runtime: <seconds>s`. No JSON dumps in the body; transcripts retained per-arm at `.kiln/logs/kiln-test-<arm-uuid>-transcript.ndjson` for diagnosis.
- **FR-S-005** *(from: PRD FR-005)* — The v1 gate MUST be a hardcoded strict gate: per-fixture verdict is `regression` if `candidate_accuracy < baseline_accuracy` (i.e. baseline-pass + candidate-fail) OR `candidate_total_tokens > baseline_total_tokens + tolerance` where `tolerance` is the recalibrated NFR-S-001 noise band (default ±2 tokens, possibly relaxed by reconciliation). Run-level verdict is `FAIL` if any fixture is `regression` or `inconclusive`. No tolerance flags, no per-axis configuration in v1.
- **FR-S-006** *(from: PRD FR-006)* — A PRD that wants to opt into research-first MAY declare `fixture_corpus: <path-to-corpus-dir>` in its frontmatter. v1 runner does NOT read PRD frontmatter — that is step 6 (`research-first-build-prd-wiring`). v1 documents the convention in the README (FR-S-010) so step 6 can land it without a contract change.
- **FR-S-007** *(from: PRD FR-007)* — The runner MUST be invokable as a standalone script via `bash plugin-wheel/scripts/harness/research-runner.sh --baseline … --candidate … --corpus …`. v1 does NOT require integration with `/kiln:kiln-build-prd`. The runner MUST also be exposable via a thin SKILL wrapper at `plugin-kiln/skills/kiln-research/SKILL.md` (or sibling — exact path resolved in plan) that mirrors the kiln-test SKILL.md shape: dual-layout sibling resolution, ≤ 50 lines of skill prose, no business logic in the SKILL.md itself.
- **FR-S-008** — The runner's exit code semantics MUST match the existing kiln-test orchestrator: `0` = all fixtures pass, `1` = at least one fixture regression, `2` = at least one fixture inconclusive (missing files, stall, parse error). This preserves the muscle-memory + CI-integration shape consumers already know.
- **FR-S-009** — The PRD MUST ship a seed corpus at `plugin-kiln/fixtures/research-first-seed/corpus/` containing exactly 3 fixtures, each with a 1-2-line `metadata.yaml` describing intent. The seed corpus exists to (a) anchor SC-S-001's wall-clock budget, (b) prove the User Story 1 happy path, (c) act as the worked example in the README. Concrete fixture choices: `001-noop-passthrough` (identical input/output, asserts the runner's plumbing), `002-token-floor` (small fixture verifying token-count parsing on a minimal envelope), `003-assertion-anchor` (fixture exercising the assertion-fail path).
- **FR-S-010** *(from: PRD SC-005)* — The runner MUST be documented in a one-page README at `plugin-wheel/scripts/harness/README-research-runner.md` (or sibling location resolved in plan) with: corpus directory shape, runner CLI, report path/shape, worked example using the FR-S-009 seed corpus, and the `fixture_corpus:` PRD-frontmatter forward-compat note (FR-S-006). Length ≤ 200 lines.
- **FR-S-011** — Per-arm scratch dirs MUST use the existing `/tmp/kiln-test-<uuid>/` shape (not a new prefix) so existing post-mortem tooling (`/kiln:kiln-test` retains-on-fail discipline, `.gitignore`, watcher-runner snapshot helpers) continues to work without changes. The two arms-per-fixture each get their own UUID; the report links both.
- **FR-S-012** — The runner MUST emit TAP v14 progress on stdout — one `ok N - <slug> (baseline)` + one `ok N+1 - <slug> (candidate)` line per fixture per arm, plus a final `# Aggregate verdict: PASS|FAIL` comment. This makes the runner CI-pipeable via the same TAP consumers wheel-test-runner already feeds.
- **FR-S-013** — The token-parsing helper MUST live at `plugin-wheel/scripts/harness/parse-token-usage.sh` (sibling to existing helpers) and be invokable as `bash parse-token-usage.sh <transcript-ndjson> → "<input> <output> <cached_creation> <cached_read> <total>"` (whitespace-delimited stdout, exit 0 on success, exit 2 on missing-usage-record per NFR-S-008). The runner consumes this helper for both arms.

### Non-Functional Requirements

- **NFR-S-001 — Determinism (PRD NFR-001 anchor; RECONCILED 2026-04-25)**: re-running the runner with identical baseline + candidate + corpus inputs MUST produce a per-fixture verdict that is identical except for token-count noise within **±10 tokens absolute per `usage` field** (`input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`). PRD literal was ±2 tokens; researcher-baseline showed the lightest-possible probe wobbles +3 tokens on `output_tokens` and `cache_creation_input_tokens` between consecutive runs of the same fixture against the same plugin-dir on the same commit. Run-level verdict (PASS/FAIL) MUST be stable across reruns — that is the load-bearing determinism, NOT per-field token-count exact equality.
- **NFR-S-002 — No fork (PRD NFR-002 anchor)**: the runner MUST NOT fork or reimplement any of: `config-load.sh`, `scratch-create.sh`, `fixture-seeder.sh`, `claude-invoke.sh`, `watcher-runner.sh`, `tap-emit.sh`, `test-yaml-validate.sh`, `dispatch-substrate.sh`, `substrate-plugin-skill.sh`, `scratch-snapshot.sh`, `snapshot-diff.sh`, `watcher-poll.sh`. These are sourced/invoked directly by the new runner. Net-new shared helpers (e.g. `parse-token-usage.sh` from FR-S-013) are permitted IF wheel-test-runner could equally well consume them — they MUST be callable by both runners without the new runner becoming a dependency of the old.
- **NFR-S-003 — Backward compatibility (PRD NFR-003 anchor)**: existing single-`--plugin-dir` `/kiln:kiln-test` invocations MUST work byte-identically post-PRD. SC-S-004 anchors the diff-zero check. Any change touching `wheel-test-runner.sh` or its existing helpers requires the audit-compliance teammate to re-run the `wheel-test-runner-extraction §3` exclusion comparator and confirm zero-diff (modulo timestamps + UUIDs + scratch paths).
- **NFR-S-004 — Report locality (PRD NFR-004 anchor)**: the report MUST live under `.kiln/logs/` (gitignored). Maintainers can copy into a PR description manually if they want it persisted. The runner MUST NOT write to `.kiln/research/`, `specs/`, or any non-gitignored path.
- **NFR-S-005 — Readability (PRD NFR-005 anchor)**: the report MUST be human-scannable in a 120-col terminal — markdown tables for per-fixture rows (no horizontal scroll on `Fixture | Baseline Acc | Candidate Acc | Baseline Tokens | Candidate Tokens | Δ Tokens | Verdict` with reasonable slug lengths up to 30 chars), 5-line aggregate summary at the bottom, no JSON in the body. Transcripts/scratch dirs are referenced by absolute path for post-mortem, not inlined.
- **NFR-S-006 — Wall-clock budget (RECONCILED 2026-04-25)**: a 3-fixture corpus run (baseline + candidate × 3 = 6 subprocesses, serial per Assumption A-4) MUST complete within **≤ 240 seconds** end-to-end on the seed corpus (FR-S-009). PRD literal was 60s; researcher-baseline showed the lightest-possible 6× projection lands at ~186s wall (~31s per fixture × 6) due to a ~20s/fixture irreducible harness fixed-cost (scratch-create + watcher startup + assertions + cleanup). 240s preserves "fast-enough to re-run during PR review" with ~30% headroom over the lightest-profile projection. This is SC-S-001's anchor.
- **NFR-S-007 — Concurrency-safety**: two parallel `research-runner.sh` invocations against the same corpus MUST NOT collide on report paths (UUIDv4 via `uuidgen`) or scratch dirs (existing `/tmp/kiln-test-<uuid>/` discipline). No file-locking required; concurrency-correctness inherits from the existing kiln-test substrate's design.
- **NFR-S-008 — Loud-failure on token-parse (R-S-1 resolution)**: the token-parsing helper MUST exit 2 + emit `Bail out! parse error: usage record missing in transcript for fixture <slug> arm <baseline|candidate>` on `null` / missing `usage` envelope. NEVER silently treat a missing usage record as zero tokens. The fail surface MUST be loud enough that an Anthropic stream-json shape change in CI is immediately visible.
- **NFR-S-009 — One-page README invariant (PRD SC-005)**: the FR-S-010 README MUST be ≤ 200 lines + render correctly in markdown. Reviewers MUST be able to follow the Quick Start to construct a 3-fixture corpus + invoke the runner without reading any runner source code.
- **NFR-S-010 — Test coverage (Constitution Article II)**: net-new code paths in `research-runner.sh` + `parse-token-usage.sh` + the seed-corpus harness MUST achieve ≥ 80% line coverage via the `plugin-kiln/tests/research-runner-*` test-fixture set. Coverage measured by `bashcov` (or equivalent shell coverage tool — exact tool resolved in plan).

## Key Entities

- **Corpus**: a directory `<root>/<NNN-slug>/` per fixture, containing `input.json` + `expected.json` + optional `metadata.yaml`. Reviewable, diffable, survives PR merges. Lives committed under `plugin-<name>/fixtures/<skill>/corpus/`.
- **Fixture**: one `<NNN-slug>/` subdir of a corpus. Replayed against both arms (baseline + candidate) per run.
- **Arm**: one of `baseline` or `candidate`. Each arm = one `claude --print … --plugin-dir <dir>` subprocess invocation against one fixture.
- **Per-fixture verdict**: `pass` | `regression (accuracy)` | `regression (tokens)` | `regression (accuracy + tokens)` | `inconclusive (<reason>)`.
- **Run-level verdict**: `PASS` (all fixtures `pass`) | `FAIL` (any `regression` or `inconclusive`).
- **Comparative report**: a markdown file at `.kiln/logs/research-<uuid>.md` with per-fixture table + 5-line aggregate summary. Gitignored.
- **`fixture_corpus:` PRD frontmatter field**: forward-compat handle for step 6 (`/kiln:kiln-build-prd` wiring). v1 documents but does not consume.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-S-001** *(PRD SC-001; RECONCILED 2026-04-25 — was 60 s, now ≤ 240 s)*: A maintainer can construct a 3-fixture corpus under `plugin-kiln/fixtures/research-first-seed/corpus/`, invoke `bash plugin-wheel/scripts/harness/research-runner.sh --baseline <main-tip> --candidate <main-tip> --corpus <seed-corpus>`, and receive `.kiln/logs/research-<uuid>.md` in **≤ 240 seconds** end-to-end. Reconciliation rationale lives in §"Reconciliation Against Researcher-Baseline" above. The seed-corpus fixtures (FR-S-009) are intentionally tuned to the lightest-possible profile to keep this budget reachable. Anchored to `research-runner-pass-path/run.sh` measurement.
- **SC-S-002** *(PRD SC-002)*: A deliberately-regressing candidate plugin-dir (one fixture engineered to produce strictly more output tokens) MUST produce an `Overall: FAIL` aggregate AND identify the regressing fixture by slug in the per-fixture row's verdict column.
- **SC-S-003** *(PRD SC-003)*: A non-regressing candidate plugin-dir (byte-identical to baseline OR a strict improvement on tokens) MUST produce `Overall: PASS`.
- **SC-S-004** *(PRD SC-004 — backward compat)*: Pre-PRD vs post-PRD `/kiln:kiln-test plugin-kiln <fixture>` runs against the three representative fixtures (`kiln-distill-basic`, `kiln-hygiene-backfill-idempotent`, plus one fast-deterministic plugin-skill fixture) MUST diff-zero per the `wheel-test-runner-extraction/contracts/interfaces.md §3` exclusion comparator. NFR-S-003 anchor.
- **SC-S-005** *(PRD SC-005)*: A reviewer who has never used the runner reads only the FR-S-010 README and successfully constructs a 3-fixture corpus + invokes the runner + reads the report. ≤ 200-line README invariant per NFR-S-009.
- **SC-S-006** *(NFR-S-001 stability)*: Re-running the runner against the same baseline + candidate + corpus 3 times in succession produces 3 byte-identical run-level verdicts (PASS/FAIL stable) AND token-count observations within the recalibrated NFR-S-001 noise band on every per-fixture row. Captured by `plugin-kiln/tests/research-runner-determinism/`.
- **SC-S-007** *(NFR-S-008 loud-failure tripwire)*: A synthetic transcript with a stripped `usage` envelope MUST cause the runner to exit 2 + emit the documented `Bail out! parse error: …` diagnostic. Captured by `plugin-kiln/tests/research-runner-missing-usage/`.

## Assumptions

- **A-1**: The wheel-test-runner extraction (PR landed 2026-04-25) is the substrate baseline. All file paths in this spec assume `plugin-wheel/scripts/harness/` is the runner home, not the historical `plugin-kiln/scripts/harness/`.
- **A-2**: 1-fixture corpora are accepted by the runner without enforcement of a minimum count. Step 2 (`research-first-per-axis-gate-and-rigor`) introduces `min_fixtures` rigor scaling — out of scope here.
- **A-3**: `total_tokens = input + output + cached_creation + cached_read`. Step 3 splits cached vs fresh as separate axes — v1 sums them.
- **A-4**: Fixtures within a corpus run serially; baseline + candidate per fixture also run serially. Two `--plugin-dir`-arm subprocesses per fixture; no parallelism. Step-N decision deferred.
- **A-5**: The `research-<uuid>.md` filename uses `uuidgen`'s default UUIDv4. No collision-handling logic.
- **A-6**: `metadata.yaml` is optional; runner ignores it. Reviewers consume it.
- **A-7**: The runner depends on the same dependency set as wheel-test-runner: bash 5.x, `claude` CLI v2.1.119+, POSIX utilities, `jq` + `python3` for stream-json parsing. No net-new runtime dependency.
- **A-8**: Backward compat is verified by snapshot-diff (per `wheel-test-runner-extraction §3` comparator); not by re-running the entire `plugin-kiln/tests/` suite. The auditor may scope SC-S-004 to the three named fixtures + a sanity sweep.
- **A-9**: The seed corpus at `plugin-kiln/fixtures/research-first-seed/corpus/` is committed to git (NOT gitignored). It is reviewable as a corpus exemplar and must survive PR merges.

## Dependencies

- **D-1**: PR landed 2026-04-25 (`wheel-test-runner-extraction`) — runner now at `plugin-wheel/scripts/harness/wheel-test-runner.sh`. This PRD assumes that PR is in main.
- **D-2**: Constitution v2.0.0 — Article VII (Interface Contracts) requires `contracts/interfaces.md` before any task generation. Article VIII (Incremental Task Completion) governs `/implement` cadence.
- **D-3**: `plugin-wheel/scripts/harness/snapshot-diff.sh` + `wheel-test-runner-extraction/contracts/interfaces.md §3` per-fixture exclusion contract — the audit gate for NFR-S-003 (SC-S-004) reuses these.
- **D-4**: `bashcov` (or equivalent shell coverage tool — `kcov` is the alternative) for NFR-S-010 coverage measurement. Plan resolves the exact tool. The kiln test-runner extraction's coverage measurement scheme is the precedent.

## Open Questions

- **OQ-S-2 (tolerance for SC-S-001 wall-clock)**: RESOLVED 2026-04-25 per §Reconciliation directive 1 — researcher-baseline measured the lightest-possible 6× projection at ~186 s, far above the 60 s PRD literal. SC-S-001 widened to ≤ 240 s. The "≤ baseline-median + 20%" framing was abandoned because the harness fixed-cost overhead (~20 s/fixture × 6 = 120 s) is irreducible — a percentage-based recalibration would distort the budget. 240 s is an absolute envelope tuned to the lightest-profile projection plus ~30% headroom. Step-N (parallelism) is the right place to bring the budget back down toward 60 s if maintainers complain.
- **OQ-S-3 (SKILL wrapper location)**: FR-S-007 says a thin SKILL wrapper exists. Should the slug be `kiln-research` (descriptive of the goal), `kiln-test --baseline-vs-candidate` (subcommand of existing skill — risks coupling), or a completely separate plugin-prefixed skill? **Default**: `kiln-research` — separate skill, separate slug, separate file. Plan resolves.
- **OQ-S-4 (token-parse helper portability)**: FR-S-013 places `parse-token-usage.sh` under `plugin-wheel/scripts/harness/`. Does wheel-test-runner ALSO benefit from invoking it (to add a token-usage column to its own verdict reports)? If yes, the helper's signature must be designed to serve both consumers. **Default**: design it generically; do not modify wheel-test-runner in this PRD (NFR-S-002), but ensure the helper's API supports a future wheel-test-runner integration. Resolution due in plan.

## Notes for Reviewers

- The PRD is one of seven steps in the `09-research-first` phase. Per-axis `direction:` (step 2), time/cost axes (step 3), synthesizer (step 4), output-quality judge (step 5), `/kiln:kiln-build-prd` wiring (step 6), and classifier inference (step 7) are EXPLICITLY out of scope for this PRD. Reviewers MUST flag any FR/NFR drift toward those steps.
- The "no fork" invariant (NFR-S-002) is the load-bearing constraint. If implementation finds it impractical, that's an architectural escalation — surface in `specs/research-first-foundation/blockers.md` rather than papering over.
- Backward compat (NFR-S-003 / SC-S-004) is non-negotiable. The existing `/kiln:kiln-test` consumer base is the entire user surface — if this PRD perturbs it byte-non-identically, the PR cannot ship.
