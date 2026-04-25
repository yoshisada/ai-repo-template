# Feature Specification: Research-First Axis Enrichment — Per-Axis Direction Gate + Time/Cost Axes

**Feature Branch**: `build/research-first-axis-enrichment-20260425`
**Created**: 2026-04-25
**Status**: Draft
**Input**: `docs/features/2026-04-25-research-first-axis-enrichment/PRD.md`
**Parent goal**: `.kiln/roadmap/items/2026-04-24-research-first-per-axis-gate-and-rigor.md` + `.kiln/roadmap/items/2026-04-24-research-first-time-and-cost-axes.md` (phase `09-research-first`, steps 2 + 3 of 7)
**Builds on**: `specs/research-first-foundation/spec.md` + `contracts/interfaces.md` (PR #176, runner already lives at `plugin-wheel/scripts/harness/research-runner.sh`).
**Baseline research**: `specs/research-first-axis-enrichment/research.md` (read first; thresholds in §Success Criteria are reconciled against it per §1.5 Baseline Checkpoint).

## Overview

The foundation runner ships with a hardcoded strict gate (`candidate_total > baseline_total * 1.5` ⇒ regression on tokens; any candidate_accuracy < baseline_accuracy ⇒ regression on accuracy) and only collects two axes — accuracy + tokens. This PRD does THREE structurally-coupled things in ONE pipeline pass and ONE PR:

1. **Per-axis direction gate** — replace the foundation's strict gate with declarative `empirical_quality:` enforcement keyed off the calling PRD's frontmatter. Each declared axis has a direction (`lower` / `higher` / `equal_or_better`) and a per-axis-per-fixture tolerance band sourced from blast-radius-scaled rigor.
2. **Blast-radius-dynamic rigor** — `min_fixtures` (corpus floor) and `tolerance_pct` (per-axis wobble) scale with the calling PRD's `blast_radius:` value. Config lives at `plugin-kiln/lib/research-rigor.json`. Isolated changes don't pay 20-fixture overhead; infra changes can't skate by with three.
3. **Time + cost axes** — runner captures `time_seconds` (wall-clock subprocess duration via monotonic clock) and derives `cost_usd` per fixture per arm using a hand-maintained pricing table at `plugin-kiln/lib/pricing.json`. All four axes (`accuracy`, `tokens`, `time`, `cost`) are opt-in via `empirical_quality:`; un-declared axes are measured + reported but not gate-enforced. PRDs that declare nothing fall through to the foundation strict gate (NFR-003 backward-compat).

The pairing is structural, not editorial. A gate-refactor that ships before the time/cost axes lands a `direction:` enforcer with no `time` or `cost` columns to enforce on. A time/cost-axes ship that lands before the gate refactor produces measured-but-not-load-bearing axes. The atomic pairing invariant (NFR-S-005) forbids carving out an "axes-only" or "gate-only" subset.

## Resolution of PRD Open Questions

The PRD `## Risks & Open Questions` left six items. Resolved as follows; rationale anchors specific FRs/NFRs.

- **OQ-AE-1 (rigor table overrideable per PRD)**: RESOLVED — **NO** in v1. The rigor table at `plugin-kiln/lib/research-rigor.json` is the single source of truth; PRDs cannot override `min_fixtures` or `tolerance_pct` per-PRD. Encoded in **FR-AE-004**. If real authoring friction emerges (e.g. a `feature`-blast PRD with a genuinely narrow surface needing only 5 fixtures), a `rigor_override:` PRD frontmatter field is a follow-on item.
- **R-AE-1 (time-axis noise floor)**: ACKNOWLEDGED. v1 of the time axis is single-run with `tolerance_pct` applied. Multi-run averaging is deferred per source-item hint. Encoded as **NFR-AE-001** + **A-AE-3**.
- **R-AE-2 (pricing-table whitespace-touch evades 180-day staleness)**: ACKNOWLEDGED. The 180-day mtime heuristic catches obviously-old tables but not whitespace-only edits. Acceptable v1 — tighter validation needs an Anthropic-published pricing endpoint that doesn't exist. Encoded as **A-AE-7**.
- **R-AE-3 (model-id missing from stream-json)**: ACKNOWLEDGED. Per FR-012 of PRD, missing model IDs resolve to `cost_usd: null` + a "pricing-table-miss" warning surfaced prominently in the report aggregate. Encoded as **FR-AE-012** + **NFR-AE-003**.
- **R-AE-4 (excluded-fraction 30% threshold)**: ACKNOWLEDGED. The threshold is arbitrary; the warning is a smell signal, not a hard rule. Open to adjustment after first real use. Encoded as **FR-AE-007**.
- **R-AE-5 (tolerance_pct on cost axis)**: ACKNOWLEDGED. Cost is a pure derivation of tokens, but the runner enforces `direction:` on cost INDEPENDENTLY of tokens (e.g., a tokens-flat candidate that shifts 100% of input from cached → fresh would fail cost but pass tokens). v1 enforces declared axes independently. Encoded as **FR-AE-002** + **A-AE-4**.
- **R-AE-6 (blast_radius source of truth — item vs PRD)**: RESOLVED — **PRD wins**. When `blast_radius:` differs between a roadmap item and the PRD that distilled it, the PRD value is the runner's input. Item-PRD drift is a roadmap-management concern, not a runner concern. Encoded as **A-AE-6**.

## Reconciliation Against Researcher-Baseline (§1.5 Baseline Checkpoint) — RECONCILED 2026-04-25

The `researcher-baseline` teammate committed `specs/research-first-axis-enrichment/research.md §baseline` (66 lines, captured 2026-04-25) with three reconciliation directives. All three accepted.

### Directive 1 — Pricing values (PRD FR-010 was wrong on opus + haiku)

**Live measurement** (research.md §FR-010 pricing confirmation, sourced from `https://platform.claude.com/docs/en/docs/about-claude/pricing` 2026-04-25):

| model                     | PRD example                | Confirmed (2026-04-25)     | Verdict |
|---------------------------|-----------------------------|----------------------------|---------|
| `claude-opus-4-7`         | $15 / $75 / $1.50           | **$5 / $25 / $0.50**       | PRD example tracks Opus 4 / 4.1 legacy pricing — Opus 4.5+ is 1/3 the rate. **REPLACE.** |
| `claude-sonnet-4-6`       | $3.00 / $15.00 / $0.30      | $3.00 / $15.00 / $0.30     | match — ship as-PRD'd. |
| `claude-haiku-4-5-20251001` | $0.80 / $4.00 / $0.08     | **$1.00 / $5.00 / $0.10**  | PRD example tracks Haiku 3.5 — Haiku 4.5 is 25% more expensive. **REPLACE.** |

**Reconciliation accepted**: implementer MUST ship `plugin-kiln/lib/pricing.json` with the **2026-04-25-confirmed values** above. SC-AE-004 hand-computed checks MUST use the confirmed numbers — running them against the PRD-example numbers WILL fail by ≥3x on opus rows + 25% on haiku rows.

**FR-AE-010 seed payload recalibrated** below: opus = `$5 / $25 / $0.50`, sonnet = `$3 / $15 / $0.30` (PRD value preserved), haiku = `$1 / $5 / $0.10`.

### Directive 2 — Time-axis tolerance (PRD-table values STAY; sub-second fixture guard ADDED)

**Live measurement** (research.md §FR-005 time-noise calibration, 5 consecutive runs of `plugin-wheel/tests/agent-resolver/run.sh` on the same shell):

- Per-run wall-clock (seconds, monotonic): [0.1864, 0.1834, 0.1763, 0.1942, 0.1696].
- min=0.1696s, max=0.1942s, median=0.1834s, range=0.0246s = **13.41 % of median**.

The 13.41 % wobble blows past every blast-radius `tolerance_pct` from PRD-table (`isolated: 5%`, `feature: 2%`, `cross-cutting: 1%`, `infra: 0%`). BUT — the harness floor is the wrong baseline. `agent-resolver` is a 180 ms Bash fixture; real kiln-test research runs wrap a `claude --print --plugin-dir` subprocess dominated by API latency (5–60 s per call). The same ±25 ms harness jitter shrinks from 13 % to <0.5 % of total when the denominator is a real research-run subprocess.

**Reconciliation accepted**: Researcher Recommendation 1+2 — **keep PRD-table `tolerance_pct` values as-is** (5 / 2 / 1 / 0) AND **add a sub-second-fixture guard** below which the time axis is silently un-enforced. Rationale: (1) PRD-table tolerances are appropriate for real research-run workloads; pre-emptive widening would mask genuine regressions on multi-second fixtures. (2) Sub-second fixtures are degenerate for time-axis enforcement regardless of `tolerance_pct` — harness jitter exceeds 1 % of any candidate ≤2 s wall-clock; gating is meaningless. (3) Per source-item hint R-AE-1, time-axis flakes on FIRST real use land in `specs/research-first-axis-enrichment/blockers.md` for follow-on multi-run-averaging PRD scoping — NOT silent tolerance widening.

**NFR-AE-001 ADDS sub-second guard** below: when a fixture's median wall-clock across baseline + candidate is < 1.0 s, the runner MUST silently un-enforce the time axis on that fixture and emit `time-axis-skipped: <slug> wall-clock <N.Ns> below 1.0s floor` warning in the aggregate summary. Other axes still gate-evaluated normally.

### Directive 3 — Monotonic clock (`python3 time.monotonic()` is the canonical source)

**Live probe** (research.md §NFR-002, on macOS Darwin):

| candidate | available? | notes |
|-----------|------------|-------|
| `gdate +%s.%N` (coreutils on macOS) | **NOT INSTALLED** | `which gdate` → not found. coreutils NOT in homebrew profile. |
| `/bin/date +%s.%N` (BSD date) | **WORKS surprisingly** on this macOS Darwin host (emits 9-digit nanoseconds). Cannot confirm portable across all macOS versions; older / clean installs likely do not support `%N`. |
| `python3 -c 'import time; print(time.monotonic())'` | **WORKS** | genuinely monotonic (immune to NTP slew + mid-run clock changes), portable across Linux + macOS, `python3` already a kiln Active Technologies dependency. |
| Linux `date +%s.%N` | assumed-available (GNU date supports `%N` natively); not measured on this host. |

**Reconciliation accepted**: Researcher Recommendation 1+2 — **prefer `python3 -c 'import time; print(time.monotonic())'`** as the cross-platform canonical monotonic source, with a fallback ladder. Rationale: `python3` is the ONLY candidate that's both (a) genuinely monotonic and (b) portable across Linux + macOS without coreutils. PRD's "POSIX `date +%s.%N` (Linux) or `gdate +%s.%N` from coreutils (macOS)" framing was wrong — `gdate` is NOT a default macOS dep, and `/bin/date +%N` works on SOME macOS builds but isn't portable. `python3` adds zero new runtime dependency (NFR-AE-006).

**Fallback ladder** (encoded in NFR-AE-006 below):

1. `python3 -c 'import time; print(time.monotonic())'` — preferred.
2. `gdate +%s.%N` — Linux GNU date OR macOS+coreutils.
3. `/bin/date +%s.%N` — works on some macOS builds; non-portable but free signal.
4. ABORT with `Bail out! no monotonic %N-precision clock available; install python3 (preferred) or coreutils (gdate)`. **NEVER fall back to integer-second `date +%s`** — second-resolution would silently miss 800ms → 1.2s regressions (the gate would see 1s → 1s and pass).

**NFR-AE-006 fallback ladder recalibrated** below.

### Reconciliation provenance

- **Recalibrated FR-AE-010 pricing seed values**: opus `$5/$25/$0.50`, haiku `$1/$5/$0.10` (was: PRD example `$15/$75/$1.50` opus, `$0.80/$4.00/$0.08` haiku). Sonnet unchanged.
- **Reconfirmed NFR-AE-001 tolerance band**: PRD-table values STAY (5/2/1/0). NEW sub-second-fixture guard added.
- **Recalibrated NFR-AE-006 monotonic-clock ladder**: `python3 time.monotonic()` preferred over `gdate`/`date`. PRD's gdate-first framing rejected.
- All other PRD thresholds unchanged.
- `## Open Questions` OQ-AE-2, OQ-AE-3, OQ-AE-4 below RESOLVED per this reconciliation.

Specifier note (per orchestrator FR-009): thresholds reconciled against research.md §baseline.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — A maintainer declares `empirical_quality: time/tokens` and a candidate that improves time but holds tokens flat MUST pass (Priority: P1 — HARD GATE)

As a kiln maintainer planning a "make this faster without spending more tokens" change, I declare `empirical_quality: [{metric: time, direction: lower}, {metric: tokens, direction: equal_or_better}]` in my PRD frontmatter, run `bash plugin-wheel/scripts/harness/research-runner.sh --baseline <b> --candidate <c> --corpus <p>`, and the gate enforces what I actually intend. A candidate that reduces time on at least one fixture and holds tokens flat (within `tolerance_pct` from blast-radius rigor) MUST pass with `Overall: PASS`. The same candidate without the `equal_or_better` declaration on tokens MUST also pass — un-declared axes are measured + reported but NOT gate-enforced.

**Why this priority**: P1 hard gate — this is the entire substrate's reason for existing. Step 2 of phase `09-research-first` (per-axis direction) is unbuildable without this exact behavior shipping.

**Independent Test**: Build a 3-fixture corpus, declare `empirical_quality: [{metric: time, direction: lower}, {metric: tokens, direction: equal_or_better}]` in a PRD-frontmatter test fixture, and run the runner with a candidate engineered to be ~10% faster on at least one fixture and ±2% on tokens. Assert: per-fixture rows show `pass (time: -X.Xs, tokens: ±N)`, aggregate is `Overall: PASS`, exit 0.

**Acceptance Scenarios**:

1. **Given** a 3-fixture corpus + PRD declaring `empirical_quality: [{metric: time, direction: lower}, {metric: tokens, direction: equal_or_better}]`, **When** I run the runner with a candidate that reduces wall-clock time on every fixture and holds tokens within `tolerance_pct`, **Then** the report's per-fixture rows show `verdict: pass`, the aggregate is `Overall: PASS (3 fixtures, 0 regressions)`, and exit code is `0`.
2. **Given** the same setup but tokens drift ABOVE `tolerance_pct` on one fixture (declared `direction: equal_or_better`), **When** the runner runs, **Then** that fixture's verdict is `regression (tokens)` and aggregate is `Overall: FAIL`.
3. **Given** a PRD that declares ONLY `empirical_quality: [{metric: time, direction: lower}]`, **When** the runner runs, **Then** tokens is measured + shown in the report but NOT gate-enforced; a candidate that reduces time + increases tokens 10x still passes.

---

### User Story 2 — A `blast_radius: cross-cutting` PRD with a 5-fixture corpus MUST fail-fast before subprocesses run (Priority: P1 — HARD GATE)

As a kiln maintainer reviewing a cross-cutting refactor PR, I want the runner to refuse a corpus that's too small for the declared blast radius. A PRD declaring `blast_radius: cross-cutting` (rigor row: `min_fixtures: 20, tolerance_pct: 1`) with a corpus containing only 5 fixtures MUST fail before any `claude --print` subprocess runs, with an explicit error naming the deficit.

**Why this priority**: P1 hard gate — without `min_fixtures` enforcement, the rigor table is decorative. PRD SC-002 anchors this exact scenario.

**Independent Test**: Author a 5-fixture corpus + PRD declaring `blast_radius: cross-cutting`. Run the runner. Assert: exit code is 2, stderr emits `Bail out! min-fixtures-not-met: 5 < 20 (blast_radius: cross-cutting)`, no scratch dirs created under `/tmp/kiln-test-*`, no transcripts written.

**Acceptance Scenarios**:

1. **Given** a 5-fixture corpus + PRD declaring `blast_radius: cross-cutting`, **When** I run the runner, **Then** it exits 2 with `Bail out! min-fixtures-not-met: 5 < 20 (blast_radius: cross-cutting)` BEFORE any subprocess invocation.
2. **Given** a 3-fixture corpus + PRD declaring `blast_radius: isolated` (rigor row: `min_fixtures: 3`), **When** I run the runner, **Then** it proceeds normally — 3 fixtures meets the floor exactly.
3. **Given** a corpus + PRD declaring an unknown `blast_radius:` value (e.g., `blast_radius: tiny`), **When** I run the runner, **Then** it exits 2 with `Bail out! unknown blast_radius: tiny (allowed: isolated|feature|cross-cutting|infra)`.

---

### User Story 3 — A `blast_radius: infra` change with a 1-token regression on one fixture MUST fail (Priority: P1 — HARD GATE)

As a kiln maintainer reviewing infra changes, I want zero wobble allowed. A PRD declaring `blast_radius: infra` (rigor row: `min_fixtures: 20, tolerance_pct: 0`) whose candidate produces 1 extra token on one fixture (declared `empirical_quality: [{metric: tokens, direction: equal_or_better}]`) MUST fail the gate.

**Why this priority**: P1 hard gate — `tolerance_pct: 0` is the load-bearing infra-rigor invariant. PRD SC-003 anchors this.

**Independent Test**: Author a 20-fixture corpus + PRD declaring `blast_radius: infra` + `empirical_quality: [{metric: tokens, direction: equal_or_better}]`. Engineer one fixture's candidate to produce exactly 1 more output token than baseline. Run the runner. Assert: per-fixture row for that fixture has `verdict: regression (tokens)`, aggregate is `Overall: FAIL`, exit 1.

**Acceptance Scenarios**:

1. **Given** a 20-fixture corpus + PRD with `blast_radius: infra` + `empirical_quality: [{metric: tokens, direction: equal_or_better}]`, **When** the candidate produces +1 token on a single fixture, **Then** that fixture's verdict is `regression (tokens)` and aggregate is `Overall: FAIL`.
2. **Given** the same setup but 0 tokens of drift across all fixtures, **When** the runner runs, **Then** aggregate is `Overall: PASS`.
3. **Given** the same setup but `direction: lower` (token-reduction required), **When** the candidate produces 0 tokens of drift on every fixture (no improvement), **Then** aggregate is `Overall: PASS` — `equal_or_better` and `lower` both accept zero-delta within tolerance.

---

### User Story 4 — A research run on mixed-model fixtures produces accurate per-fixture `cost_usd` (Priority: P1 — HARD GATE)

As a kiln maintainer reviewing a research run, I want a per-fixture cost figure in dollars so I can immediately see whether the candidate is more or less expensive than baseline, without manually multiplying tokens × rates. A corpus mixing fixtures from `claude-opus-4-7` and `claude-haiku-4-5-20251001` model assignments MUST produce per-fixture `cost_usd` values that match a hand-computed `(in × $/in + out × $/out + cached_in × $/cached_in) / 1_000_000` to within 4 decimal places.

**Why this priority**: P1 hard gate — cost is half the value proposition of step 3. PRD SC-004 anchors this.

**Independent Test**: Author a 2-fixture corpus where fixture #1's stream-json transcript has `message.model = "claude-opus-4-7"` and fixture #2's has `message.model = "claude-haiku-4-5-20251001"`. Hand-compute expected costs using the (researcher-baseline-confirmed) pricing table. Run the runner. Assert: report's per-fixture `Cost USD` column matches hand-computed values to 4 decimal places.

**Acceptance Scenarios**:

1. **Given** a corpus with mixed-model fixtures + a populated `pricing.json`, **When** the runner runs, **Then** per-fixture `cost_usd` matches the formula `(input × input_per_mtok + output × output_per_mtok + cached_input × cached_input_per_mtok) / 1_000_000` to 4 decimal places for both arms.
2. **Given** a fixture whose stream-json transcript has `message.model = "<unknown-model>"`, **When** the runner runs, **Then** that fixture's `cost_usd` is `null`, the report's per-fixture row shows `Cost USD: —`, and the aggregate-summary section emits `pricing-table-miss: <unknown-model>` as a warning.
3. **Given** a fixture whose stream-json transcript omits `message.model` entirely, **When** the runner runs, **Then** the same `null`-cost behavior applies (FR-AE-012); the fixture is still gate-evaluated on other axes.

---

### User Story 5 — A PRD with `excluded_fixtures:` skips named fixtures with their reasons rendered in the report (Priority: P2)

As a kiln maintainer with one known-noisy fixture, I declare `excluded_fixtures: [{path: 005-flaky-network-call, reason: "API latency spikes ±200ms unrelated to candidate"}]` in my PRD. The runner skips that fixture, records the exclusion in the report's "excluded" section with the reason verbatim, and counts it AGAINST the `min_fixtures` floor (excluded fixtures do NOT satisfy the minimum).

**Why this priority**: P2 — the escape hatch is genuinely useful but not gating for substrate correctness. PRD SC-006 anchors this.

**Independent Test**: Author a 4-fixture corpus + PRD declaring `blast_radius: isolated` (rigor row: `min_fixtures: 3`) + `excluded_fixtures: [{path: 002-flaky, reason: "intermittent stream-json shape drift"}]`. Run the runner. Assert: report's "Excluded" section contains a single row with `002-flaky | intermittent stream-json shape drift`, `min_fixtures` check sees 3 active fixtures (4 declared - 1 excluded), the run proceeds, exit code matches the gate verdict on the active 3.

**Acceptance Scenarios**:

1. **Given** a 4-fixture corpus + `excluded_fixtures: [{path: 002-flaky, reason: "..."}]` + `blast_radius: isolated`, **When** the runner runs, **Then** fixture `002-flaky` is skipped (no scratch dirs created for it), the report's "Excluded" section names it + the reason, and `min_fixtures` (3) is satisfied by the remaining 3 active fixtures.
2. **Given** a 4-fixture corpus + `excluded_fixtures: [{path: 002-flaky, reason: "..."}, {path: 003-noisy, reason: "..."}]` + `blast_radius: isolated`, **When** the runner runs, **Then** `min_fixtures: 3` is NOT satisfied (only 2 active fixtures remain), runner exits 2 with `Bail out! min-fixtures-not-met: 2 < 3 (blast_radius: isolated, 2 fixtures excluded)`.
3. **Given** a 10-fixture corpus + 4 excluded fixtures (40% > 30% threshold), **When** the runner runs, **Then** the report emits an `excluded-fraction-high: 4/10 (40%) exceeds 30% threshold` warning in the aggregate summary, but the run proceeds normally if `min_fixtures` is otherwise met.

---

### User Story 6 — A PRD with no `empirical_quality:` declared falls through to the foundation strict gate (Priority: P1 — HARD GATE)

As any maintainer running the foundation runner against a pre-axis-enrichment PRD, my run continues to work byte-identically. PRDs without `empirical_quality:` see no behavior change — the runner falls through to the foundation's hardcoded strict gate (per-fixture `regression (tokens)` iff `candidate_total > baseline_total * 1.5`; per-fixture `regression (accuracy)` iff `candidate_accuracy < baseline_accuracy`). Reports for fall-through PRDs MUST diff-zero against the foundation's report shape modulo the exclusion comparator (timestamps + UUIDs + scratch paths).

**Why this priority**: P1 hard gate — backward compat is non-negotiable. PRD NFR-003 + SC-005 anchor this.

**Independent Test**: Take the foundation PRD's `research-runner-pass-path` test fixture (pre-axis-enrichment), run it post-PRD against a PRD that does NOT declare `empirical_quality:`, and snapshot-diff the report against the pre-PRD report via the same exclusion comparator from `wheel-test-runner-extraction/contracts/interfaces.md §3`. Delta = 0 lines beyond the modulo-list.

**Acceptance Scenarios**:

1. **Given** a PRD with no `empirical_quality:` in frontmatter, **When** the runner runs, **Then** the gate is the foundation's strict gate — per-fixture verdicts and aggregate are byte-identical to a pre-axis-enrichment run modulo timestamps/UUIDs.
2. **Given** the same PRD, **When** I read the report, **Then** the new columns (`Time s`, `Cost USD`) are still rendered (since both axes are now collected by default per FR-AE-014), but they are NOT gate-enforced.
3. **Given** the foundation's existing `plugin-kiln/tests/research-runner-pass-path/` + `research-runner-regression-detect/` fixtures, **When** I re-run them post-PRD, **Then** they pass with their pre-PRD verdicts (PASS for the symlinked-identical case, FAIL for the engineered-regression case).

---

### User Story 7 — An auditor surfaces a "pricing-table-stale" finding when `pricing.json` is older than 180 days (Priority: P2)

As an auditor reviewing a PR with a research run, I want a clear signal when the pricing table hasn't been refreshed recently. If `plugin-kiln/lib/pricing.json` has an mtime more than 180 days ago, the auditor MUST surface a finding labeled `pricing-table-stale: <days>d since mtime` in `agent-notes/audit-compliance.md`. The research run itself does NOT fail on this signal — it's an audit-time tripwire, not a gate.

**Why this priority**: P2 — discoverability/maintainability over time. PRD SC-007 anchors this.

**Independent Test**: Touch `plugin-kiln/lib/pricing.json` to set its mtime to 200 days ago (`touch -d "200 days ago" plugin-kiln/lib/pricing.json` on Linux, `touch -t YYYYMMDDHHMM` on macOS). Run the auditor. Assert: `agent-notes/audit-compliance.md` contains `pricing-table-stale: 200d since mtime`. The runner itself MUST exit normally on the same setup (no gate failure).

**Acceptance Scenarios**:

1. **Given** `plugin-kiln/lib/pricing.json` with mtime 200 days ago, **When** the auditor runs, **Then** `agent-notes/audit-compliance.md` contains `pricing-table-stale: 200d since mtime`.
2. **Given** the same file with mtime 30 days ago, **When** the auditor runs, **Then** no staleness finding is emitted.
3. **Given** the same 200-day-old file, **When** the runner runs, **Then** it exits normally on the gate verdict — no `Bail out!` for staleness.

---

### Edge Cases

- **`empirical_quality:` declares an unknown metric** (e.g., `metric: latency_p99`): runner exits 2 with `Bail out! unknown metric: latency_p99 (allowed: accuracy|tokens|time|cost|output_quality)`. `output_quality` is reserved for step 5 — when declared in step 2/3, the runner emits a warning + ignores it (does NOT gate-enforce; per PRD FR-AE-001).
- **`empirical_quality:` declares an unknown direction** (e.g., `direction: tighter`): runner exits 2 with `Bail out! unknown direction: tighter (allowed: lower|higher|equal_or_better)`.
- **`empirical_quality:` declares the same metric twice** (e.g., two `time` rows with conflicting directions): runner exits 2 with `Bail out! duplicate metric in empirical_quality: time`.
- **`empirical_quality:` declares `direction: higher` on `cost`**: runner accepts but emits a "suspicious-direction: cost direction=higher (cost normally direction=lower)" warning. The gate still enforces what's declared.
- **`pricing.json` is malformed JSON**: runner exits 2 with `Bail out! pricing.json malformed: <jq parse error>`. Loud-failure per NFR-AE-005.
- **`pricing.json` is missing entirely**: runner falls back to `cost_usd: null` for all fixtures and emits a single "pricing-table-missing" warning at run start. The gate still operates on declared axes; cost-axis declarations fail-fast at run start with `Bail out! cost axis declared but plugin-kiln/lib/pricing.json not found`.
- **`research-rigor.json` is malformed or missing**: runner exits 2 with `Bail out! research-rigor.json malformed-or-missing: <error>` — there is no fallback rigor table.
- **Time measurement on a system without any monotonic %N-precision clock**: runner walks the NFR-AE-006 ladder (`python3 time.monotonic()` → `gdate` → `/bin/date +%s.%N` → abort). Exits 2 at startup with `Bail out! no monotonic %N-precision clock available; install python3 (preferred) or coreutils (gdate)` only when ALL ladder rungs fail. NEVER falls back to integer-second `date +%s`.
- **Identical baseline = candidate (symlink) on a `time`-declared PRD**: time-axis observed wobble may exceed `tolerance_pct` for the most-permissive `isolated` blast (5%) on lightest-fixture profiles. v1 accepts the noise; if reviewers report nondeterministic gate failures driven solely by time-axis noise, follow-on item is multi-run averaging (deferred per source-item hint).
- **`excluded_fixtures:` references a path that doesn't exist in the corpus**: runner exits 2 with `Bail out! excluded_fixtures path not found in corpus: <slug>`. Catches typos; refuses silent ignores.
- **`excluded_fixtures:` count is 0 or the field is absent**: no behavior change — equivalent to declaring an empty list.
- **PRD declares `blast_radius:` with surrounding whitespace** (`blast_radius:   isolated  `): runner trims + accepts. Fail-fast only on values not in the allowed list after trim.
- **Mixed-model corpus with some pricing entries missing**: each fixture is independently evaluated; the present-pricing fixtures get `cost_usd` populated, the missing-pricing fixtures get `cost_usd: null` + a "pricing-table-miss: <model-id>" warning. Per FR-AE-012.
- **PRD declares ONLY `cost` and the candidate's `cost_usd` is null on every fixture** (because every fixture's model is missing from the table): runner exits 2 with `Bail out! cost axis declared but no fixture produced a cost_usd value (all model IDs missing from pricing.json)`. Catches the silent-pass-through that would happen if undeclared null values were treated as "passing."

## Requirements *(mandatory)*

### Functional Requirements

#### Per-axis direction gate (step 2)

- **FR-AE-001** *(from: PRD FR-001)* — A PRD MAY declare `empirical_quality:` as a list of `{metric, direction, priority}` objects in its frontmatter. `metric` ∈ `{accuracy, tokens, time, cost, output_quality}` (the `output_quality` value is RESERVED for step 5; this PRD emits a warning + ignores it if declared). `direction` ∈ `{lower, higher, equal_or_better}`. `priority` ∈ `{primary, secondary}` (used for surfacing in the report; both gate-enforced).
- **FR-AE-002** *(from: PRD FR-002 + R-AE-5)* — When `empirical_quality:` is declared, the gate MUST enforce `direction:` per declared axis INDEPENDENTLY: `direction=lower` → `candidate ≤ baseline + tolerance`; `direction=equal_or_better` → `candidate ≥ baseline − tolerance`; `direction=higher` → `candidate > baseline` (strict — `tolerance` does NOT lift this). `accuracy` is ALWAYS implicitly enforced with `direction=equal_or_better` even if not declared (a regression in pass/fail count always fails the run).
- **FR-AE-003** *(from: PRD FR-003)* — A change that improves one declared axis and holds another flat (within tolerance) MUST pass. A change that holds all declared axes flat MUST pass. The gate enforces non-regression, not improvement (`direction: higher` is the lone exception — reserved for explicit "this MUST get faster" assertions).
- **FR-AE-004** *(from: PRD FR-004 + OQ-AE-1)* — A rigor configuration file MUST live at `plugin-kiln/lib/research-rigor.json` with the shape `{<blast_radius>: {min_fixtures: int, tolerance_pct: int}}` for the four blast-radius values (`isolated`, `feature`, `cross-cutting`, `infra`). The runner reads the calling PRD's `blast_radius:` (from PRD frontmatter — `A-AE-6` resolves item-vs-PRD precedence in favor of PRD), looks up the rigor row, and enforces both `min_fixtures` (corpus floor; failure mode is fail-fast pre-subprocess per US-2) and `tolerance_pct` (per-axis wobble budget per FR-AE-005). The table is NOT overrideable per-PRD in v1.
- **FR-AE-005** *(from: PRD FR-005)* — `tolerance_pct` MUST be applied per-axis-per-fixture. For an axis with `direction=lower`, a fixture's candidate value is a regression iff `(candidate - baseline) / max(baseline, 1) > tolerance_pct/100`. For `direction=equal_or_better`, regression iff `(baseline - candidate) / max(baseline, 1) > tolerance_pct/100`. For `direction=higher`, no tolerance applied (strict comparison). `tolerance_pct=0` allows zero wobble (infra blast).
- **FR-AE-006** *(from: PRD FR-006)* — A PRD MAY declare `excluded_fixtures: [{path, reason}, ...]` to skip specific known-noisy fixtures. The runner skips them at fixture-load time (no scratch dirs created), records each exclusion in the report's "Excluded" section with the reason verbatim, and counts them AGAINST the `min_fixtures` floor (excluded fixtures do NOT satisfy the minimum — see US-5 acceptance scenario 2).
- **FR-AE-007** *(from: PRD FR-007 + R-AE-4)* — If excluded-fixture count exceeds 30% of the declared corpus size, the runner MUST emit an `excluded-fraction-high: <N>/<M> (<P>%) exceeds 30% threshold` warning in the aggregate summary. The auditor MUST surface this as a finding when reviewing PRDs with research runs. Threshold is open to adjustment after first real use.
- **FR-AE-008** *(from: PRD FR-008)* — When `empirical_quality:` is NOT declared in PRD frontmatter, the runner MUST fall back to the foundation's strict gate (NFR-S-003 of foundation PRD). This preserves backward compatibility. The foundation strict gate path is an explicit codepath, not a "no axes declared" branch — both paths share the parser + report-renderer but diverge on gate-rule application.

#### Time and cost axes (step 3)

- **FR-AE-009** *(from: PRD FR-009)* — The runner MUST capture, per fixture per arm, a `time_seconds` measurement: wall-clock duration of the subprocess invocation using a monotonic clock. Implementation MUST resolve the clock at runner startup: prefer `gdate +%s.%N` (macOS coreutils), fall back to `date +%s.%N` (Linux + macOS-with-coreutils-replacing-default), exit 2 with documented `Bail out!` if neither resolves (NFR-AE-006).
- **FR-AE-010** *(from: PRD FR-010; RECONCILED 2026-04-25 against research.md §FR-010)* — A pricing table MUST live at `plugin-kiln/lib/pricing.json` keyed by exact model ID. Each entry contains three numeric fields: `input_per_mtok`, `output_per_mtok`, `cached_input_per_mtok` (USD per million tokens). v1 ships entries for the three models below with the **2026-04-25-confirmed Anthropic-published rates** (NOT the PRD example numbers — see §Reconciliation Directive 1):
  - `claude-opus-4-7`: `input_per_mtok: 5.00`, `output_per_mtok: 25.00`, `cached_input_per_mtok: 0.50`
  - `claude-sonnet-4-6`: `input_per_mtok: 3.00`, `output_per_mtok: 15.00`, `cached_input_per_mtok: 0.30`
  - `claude-haiku-4-5-20251001`: `input_per_mtok: 1.00`, `output_per_mtok: 5.00`, `cached_input_per_mtok: 0.10`
- **FR-AE-011** *(from: PRD FR-011)* — The runner MUST derive `cost_usd` per fixture per arm as `(input_tokens × input_per_mtok + output_tokens × output_per_mtok + cached_input_tokens × cached_input_per_mtok) / 1_000_000` to at least 4 decimal places of precision. `cached_input_tokens` is the sum of `cache_creation_input_tokens + cache_read_input_tokens` from the foundation's existing token-parser (per Assumption A-3 of foundation spec). Model ID comes from the fixture's stream-json output's `message.model` field in the assistant turn.
- **FR-AE-012** *(from: PRD FR-012 + R-AE-3)* — If a fixture's resolved model ID is missing from `pricing.json` (or `message.model` is absent from the transcript), the runner MUST emit `cost_usd: null` for that fixture and a `pricing-table-miss: <model-id>` warning in the aggregate summary. The fixture is still gate-evaluated on other axes; it does NOT fail solely due to missing pricing. EDGE CASE: when ALL fixtures produce `cost_usd: null` AND `cost` is a declared axis, runner fails per the §Edge Cases entry.
- **FR-AE-013** *(from: PRD FR-013)* — An auditor subcheck MUST flag `plugin-kiln/lib/pricing.json` as stale if the file's mtime is more than 180 days old. The auditor reads the mtime via `stat` (cross-platform — `stat -c %Y` on Linux, `stat -f %m` on macOS — runner abstracts via a small helper), compares to `current_epoch - 180*86400`, and emits `pricing-table-stale: <days>d since mtime` to `agent-notes/audit-compliance.md`. The research run itself does NOT fail on this signal (audit-time tripwire, not a gate per US-7).
- **FR-AE-014** *(from: PRD FR-014)* — All four axes (`accuracy`, `tokens`, `time`, `cost`) MUST be opt-in via `empirical_quality:`. Un-declared axes are still measured + reported (so the maintainer sees the full picture) but are NOT gate-enforced. Default behavior (no `empirical_quality:` in frontmatter) is the foundation strict-gate fallback per FR-AE-008.

#### Report extensions

- **FR-AE-015** *(from: PRD FR-015)* — The comparative report at `.kiln/logs/research-<uuid>.md` MUST include, per-fixture: baseline + candidate values for `accuracy`, `tokens`, `time_seconds`, `cost_usd`; the delta on each axis; and the per-axis verdict (`pass` / `regression` / `not-enforced`). The aggregate summary MUST list the declared axes (or "(strict-gate fallback)" when none declared per FR-AE-008), the rigor row used (`blast_radius` + `min_fixtures` + `tolerance_pct`), the count of excluded fixtures + threshold-warning if applicable (FR-AE-007), the count of `pricing-table-miss` warnings if any (FR-AE-012), and the overall verdict.
- **FR-AE-016** — The report's per-fixture markdown table MUST add four columns to the foundation's existing layout: `Time s` (baseline + candidate combined as `B/C` for column-budget; delta as `Δ` adjacent), `Cost USD` (same `B/C` shape), `Per-Axis Verdict` (verbatim list of declared axes + their per-fixture pass/regression-on-axis status). Layout MUST stay scrollable in a 120-col terminal — slug column ≤ 30 chars (carried from foundation NFR-S-005). Layout details deferred to plan §Report layout decision; spec mandates the columns + scroll-fit invariant only.

### Non-Functional Requirements

- **NFR-AE-001 — Time-axis tolerance band (PRD NFR-001 sibling; RECONCILED 2026-04-25)**: PRD-table `tolerance_pct` values (`isolated: 5`, `feature: 2`, `cross-cutting: 1`, `infra: 0`) are appropriate for real research-run workloads (multi-second `claude --print --plugin-dir` subprocesses dominated by API latency). Sub-second fixtures are degenerate for time-axis enforcement regardless of `tolerance_pct` — harness jitter exceeds 1% of any candidate ≤2s wall-clock. **Sub-second fixture guard**: when a fixture's median wall-clock across baseline + candidate is `< 1.0` seconds AND `time` is a declared axis, the runner MUST silently un-enforce the time axis on THAT fixture and emit `time-axis-skipped: <slug> wall-clock <N.Ns> below 1.0s floor` warning in the aggregate summary. Other axes (accuracy, tokens, cost) still gate-evaluated normally on the same fixture. Time-axis flakes on FIRST real use of multi-second fixtures land in `specs/research-first-axis-enrichment/blockers.md` for follow-on multi-run-averaging PRD scoping (per source-item hint R-AE-1) — the response is NOT silent tolerance widening.
- **NFR-AE-002 — Determinism on declared axes (PRD NFR-001 anchor)**: re-running the runner on identical inputs MUST produce identical pass/fail verdicts on `accuracy`, `tokens`, and `cost` (cost being a pure function of tokens). `time` may vary; `tolerance_pct` absorbs the variance. Run-level verdict (PASS/FAIL) stability is the load-bearing determinism, NOT per-field exact equality. Foundation NFR-S-001 ±10 tokens absolute per `usage` field is unchanged.
- **NFR-AE-003 — Backward compatibility with foundation (PRD NFR-003 anchor)**: PRDs without `empirical_quality:` see no gate behavior change. PRDs with `empirical_quality:` get the per-axis gate; the foundation's strict gate is still callable as a fallback codepath (FR-AE-008). Foundation's existing `plugin-kiln/tests/research-runner-pass-path/` + `research-runner-regression-detect/` + `research-runner-determinism/` + `research-runner-missing-usage/` + `research-runner-back-compat/` fixtures MUST pass post-PRD. The audit-compliance teammate MUST re-run all five fixtures + diff-zero against pre-PRD reports modulo the §3 exclusion comparator.
- **NFR-AE-004 — Pricing-table portability (PRD NFR-004 anchor)**: `pricing.json` MUST be checked into the repo and shipped with the plugin (under `plugin-kiln/lib/`), so consumer projects get the same pricing the substrate authors validated. NO environment variable or external lookup. NO auto-refresh.
- **NFR-AE-005 — Atomic axis pairing (PRD NFR-005 anchor — NON-NEGOTIABLE)**: step 2's gate-refactor and step 3's metric additions MUST land in the same PR. NO partial-ship state where the gate knows about a `time` axis but the runner doesn't measure it (or vice versa). The tasks.md MUST interleave step-2 and step-3 work — NO carved-out "axes-only" or "gate-only" phase. The PR diff MUST contain BOTH `plugin-kiln/lib/research-rigor.json` AND `plugin-kiln/lib/pricing.json` AND the runner extensions for both surfaces. Audit-compliance teammate MUST flag any PR that violates this (e.g., a `research-rigor.json` ship without a `pricing.json` ship is NFR-AE-005-non-compliant).
- **NFR-AE-006 — Monotonic-clock runtime check (PRD Tech Stack anchor; RECONCILED 2026-04-25)**: at runner startup, before any fixture iteration, the runner MUST resolve a sub-second monotonic clock by walking the following ladder in order, taking the first that succeeds:
  1. `python3 -c 'import time; print(time.monotonic())'` — preferred. Genuinely monotonic (immune to NTP slew + mid-run clock changes), portable across Linux + macOS, `python3` already a documented kiln dependency (CLAUDE.md Active Technologies).
  2. `gdate +%s.%N` — Linux GNU date OR macOS+coreutils.
  3. `/bin/date +%s.%N` — works on some macOS Darwin builds (BSD date with `%N` support); free signal where it works, non-portable.
  4. **ABORT** with `Bail out! no monotonic %N-precision clock available; install python3 (preferred) or coreutils (gdate)` and exit 2. **NEVER fall back to integer-second `date +%s`** — second-resolution would silently miss 800ms → 1.2s regressions (gate would see 1s → 1s and pass; loud-failure invariant per NFR-AE-007).

  The resolved clock command is captured at startup and used for all `time_seconds` measurements in the run. The probe order MUST be deterministic — running the runner twice on the same host MUST resolve to the same clock command both times.
- **NFR-AE-007 — Loud-failure on config malformation**: `research-rigor.json` and `pricing.json` are parsed at runner startup via `jq`. ANY parse error MUST exit 2 with `Bail out! <file> malformed: <jq error>`. NEVER silently fall back to a hardcoded default. NEVER silently skip the rigor or cost gate when a config file is broken.
- **NFR-AE-008 — Test coverage (Constitution Article II)**: net-new code paths in the gate refactor + time/cost capture + report extensions MUST achieve ≥ 80% line coverage via the `plugin-kiln/tests/research-runner-axis-*` test-fixture set. Coverage measured by the same tool the foundation used (resolved in plan; foundation NFR-S-010 anchor).
- **NFR-AE-009 — Foundation file untouchability (Foundation NFR-S-002 sibling)**: this PRD MUST NOT modify any of the foundation's listed-untouchable files (per `specs/research-first-foundation/contracts/interfaces.md §10`). The runner script `plugin-wheel/scripts/harness/research-runner.sh` IS modified (it is THIS PRD's primary work surface), but `parse-token-usage.sh` + `render-research-report.sh` MAY be modified ONLY in additive ways that preserve foundation determinism + back-compat fixtures.

## Key Entities

- **Empirical-quality declaration**: a YAML-frontmatter list on a PRD declaring which axes the runner enforces. Shape: `[{metric, direction, priority}, ...]`. Optional — absence triggers foundation strict-gate fallback (FR-AE-008).
- **Rigor row**: one entry in `plugin-kiln/lib/research-rigor.json`, keyed by blast radius. Carries `min_fixtures` (corpus floor) + `tolerance_pct` (per-axis wobble budget). Resolved at runner startup from PRD's `blast_radius:` field.
- **Pricing entry**: one entry in `plugin-kiln/lib/pricing.json`, keyed by exact model ID. Carries `input_per_mtok`, `output_per_mtok`, `cached_input_per_mtok` (USD per million tokens). Hand-maintained.
- **Per-axis verdict**: per-fixture per-axis status — `pass` / `regression` / `not-enforced` (un-declared axis). Distinct from the per-fixture verdict, which aggregates all axes.
- **Time axis**: wall-clock subprocess duration in seconds (monotonic clock, `%N` precision). Single-run measurement in v1.
- **Cost axis**: derived USD value per fixture per arm. Pure function of tokens × pricing. `null` when model ID is missing from pricing.json.
- **Excluded-fixture entry**: one item in `excluded_fixtures: [{path, reason}, ...]`. Skips the named fixture, records the reason in the report, counts AGAINST `min_fixtures`.
- **`pricing-table-miss` warning**: emitted when a fixture's model ID is absent from `pricing.json`. Per-fixture, surfaced in aggregate.
- **`pricing-table-stale` audit finding**: emitted by the auditor (NOT the runner) when `pricing.json` mtime > 180 days. Audit-time tripwire, not a gate.
- **`excluded-fraction-high` warning**: emitted when excluded-fixture count > 30% of corpus. Smell signal in aggregate; not a gate.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-AE-001** *(PRD SC-001)* — A PRD declaring `empirical_quality: [{metric: time, direction: lower}, {metric: tokens, direction: equal_or_better}]` and a candidate that improves time on every fixture and holds tokens flat (within `tolerance_pct` from blast-radius rigor) MUST pass with `Overall: PASS`. The same candidate run against a PRD declaring ONLY `[{metric: time, direction: lower}]` MUST also pass — un-declared tokens is measured but not gate-enforced. Anchor: `plugin-kiln/tests/research-runner-axis-direction-pass/run.sh`.
- **SC-AE-002** *(PRD SC-002)* — A PRD declaring `blast_radius: cross-cutting` whose corpus has only 5 fixtures MUST exit 2 with `Bail out! min-fixtures-not-met: 5 < 20 (blast_radius: cross-cutting)` BEFORE any subprocess invocation. Anchor: `plugin-kiln/tests/research-runner-axis-min-fixtures-cross-cutting/run.sh`.
- **SC-AE-003** *(PRD SC-003)* — A PRD declaring `blast_radius: infra` (rigor row: `tolerance_pct: 0`) + `empirical_quality: [{metric: tokens, direction: equal_or_better}]` whose candidate produces +1 token on a single fixture MUST fail with `Overall: FAIL`. Anchor: `plugin-kiln/tests/research-runner-axis-infra-zero-tolerance/run.sh`.
- **SC-AE-004** *(PRD SC-004)* — A research run on a corpus mixing fixtures from `claude-opus-4-7` and `claude-haiku-4-5-20251001` MUST produce per-fixture `cost_usd` matching the formula `(in × $/in + out × $/out + cached_in × $/cached_in) / 1_000_000` to within 4 decimal places. Pricing values sourced from researcher-baseline-confirmed `pricing.json`. Anchor: `plugin-kiln/tests/research-runner-axis-cost-mixed-models/run.sh`.
- **SC-AE-005** *(PRD SC-005 / NFR-AE-003)* — A PRD with no `empirical_quality:` declared MUST produce a report whose per-fixture verdicts + aggregate are byte-identical to the foundation strict-gate path modulo the §3 exclusion comparator. The foundation's existing 5 test fixtures (`research-runner-pass-path`, `research-runner-regression-detect`, `research-runner-determinism`, `research-runner-missing-usage`, `research-runner-back-compat`) MUST pass post-PRD with their pre-PRD verdicts. Anchor: `plugin-kiln/tests/research-runner-axis-fallback-strict-gate/run.sh` + the foundation's existing 5 fixtures re-run.
- **SC-AE-006** *(PRD SC-006)* — `excluded_fixtures: [{path: <name>, reason: <text>}]` MUST cause the named fixture to be skipped (no scratch dirs created), recorded in the report's "Excluded" section with the reason verbatim, and counted AGAINST the `min_fixtures` floor (excluded fixtures do NOT satisfy the minimum). Anchor: `plugin-kiln/tests/research-runner-axis-excluded-fixtures/run.sh`.
- **SC-AE-007** *(PRD SC-007)* — `pricing.json` modified more than 180 days ago MUST trigger an auditor finding `pricing-table-stale: <days>d since mtime` in `agent-notes/audit-compliance.md`. The research run itself MUST NOT fail on this signal. Anchor: `plugin-kiln/tests/research-runner-axis-pricing-stale-audit/run.sh`.
- **SC-AE-008** *(NFR-AE-005 — atomic pairing tripwire)* — The PR diff against `main` MUST contain BOTH `plugin-kiln/lib/research-rigor.json` AND `plugin-kiln/lib/pricing.json` AND the runner extensions for both surfaces. An auditor running `git diff main...HEAD --name-only | grep -E 'research-rigor.json|pricing.json'` MUST find both files. If only one is present, audit-compliance MUST flag the PR as NFR-AE-005-non-compliant and BLOCK ship. Anchor: `agent-notes/audit-compliance.md` "atomic-pairing" subcheck.
- **SC-AE-009** *(NFR-AE-006 — monotonic clock)* — On a system without `%N`-precision date (synthetic test by mocking `date` + `gdate` out of PATH), the runner MUST exit 2 at startup with the documented `Bail out!` diagnostic. Anchor: `plugin-kiln/tests/research-runner-axis-no-monotonic-clock/run.sh`.

## Assumptions

- **A-AE-1**: The foundation runner (`plugin-wheel/scripts/harness/research-runner.sh`, `parse-token-usage.sh`, `render-research-report.sh`) is in main and shipped via PR #176. All file paths in this spec assume the foundation's substrate is the baseline.
- **A-AE-2**: Rigor table values (`{"isolated": {min_fixtures: 3, tolerance_pct: 5}, "feature": {min_fixtures: 10, tolerance_pct: 2}, "cross-cutting": {min_fixtures: 20, tolerance_pct: 1}, "infra": {min_fixtures: 20, tolerance_pct: 0}}`) are taken directly from PRD `## Implementation Hints`. These are the v1 seed values; tuning is a follow-on item.
- **A-AE-3**: Time-axis measurement is single-run per fixture per arm. Multi-run averaging is deferred per source-item hint R-AE-1.
- **A-AE-4**: Cost axis is enforced INDEPENDENTLY of tokens when both are declared. A tokens-flat candidate that shifts cached → fresh tokens MAY fail cost while passing tokens (this is intentional — cost is the load-bearing economic axis when declared).
- **A-AE-5**: `output_quality` metric in `empirical_quality:` is RESERVED for step 5 (`research-first-output-quality-judge`). v1 emits a warning when declared + ignores it (does NOT gate-enforce).
- **A-AE-6**: When `blast_radius:` differs between a roadmap item and the PRD that distilled it, the PRD value wins. Item-PRD drift is a roadmap-management concern.
- **A-AE-7**: Pricing-table whitespace-only edits evade the 180-day mtime staleness check. Acceptable v1 — tighter validation needs an Anthropic-published pricing endpoint that doesn't exist.
- **A-AE-8**: `cached_input_tokens` (used in cost derivation per FR-AE-011) is the sum of `cache_creation_input_tokens + cache_read_input_tokens` from the foundation's existing token-parser (Assumption A-3 of foundation spec). Step-N may split these as separate cost components if Anthropic's pricing differentiates further.
- **A-AE-9**: The runner depends on the same dependency set as the foundation: bash 5.x, `claude` CLI v2.1.119+, POSIX utilities, `jq` + `python3` for stream-json parsing, plus `gdate`/`date +%s.%N` for monotonic time. NO net-new runtime dependency beyond the monotonic-clock probe.
- **A-AE-10**: The seed values for `pricing.json` are RECONCILED to research.md §baseline 2026-04-25-confirmed Anthropic-published rates (per FR-AE-010): opus `$5/$25/$0.50`, sonnet `$3/$15/$0.30`, haiku `$1/$5/$0.10`. PRD example numbers were wrong on opus + haiku rows; sonnet is unchanged.
- **A-AE-11**: The monotonic clock for time-axis measurement is `python3 -c 'import time; print(time.monotonic())'` on hosts where `python3` is available, with `gdate` and `/bin/date +%s.%N` as fallback rungs (per NFR-AE-006). Sub-second fixtures (median wall-clock < 1.0s) are silently un-enforced on the time axis per NFR-AE-001 sub-second guard.

## Dependencies

- **D-AE-1**: PR #176 (`research-first-foundation`) — foundation runner + parse helper + report renderer in main. This PRD assumes that PR is shipped.
- **D-AE-2**: `specs/research-first-foundation/contracts/interfaces.md §1` (per-fixture result JSON shape) — this PRD extends the shape with `time_seconds` + `cost_usd` per arm + per-axis verdict. Exact extension shape resolved in plan.
- **D-AE-3**: Constitution v2.0.0 — Article VII (Interface Contracts) requires `contracts/interfaces.md` before any task generation. Article VIII (Incremental Task Completion) governs `/implement` cadence.
- **D-AE-4**: `research.md §baseline` from researcher-baseline teammate — REQUIRED before `/tasks` finalizes. Carries pricing values + time-axis variance + monotonic-clock availability findings.
- **D-AE-5**: `bashcov` (or equivalent shell coverage tool — exact tool resolved in plan, foundation precedent applies) for NFR-AE-008 coverage measurement.

## Open Questions

- **OQ-AE-2 (RESOLVED 2026-04-25 per §Reconciliation Directive 2)**: PRD-table `tolerance_pct` values STAY (5/2/1/0); the harness floor measurement (13.41 % wobble on 180ms Bash fixture) is NOT representative of real research-run workloads (multi-second `claude --print` subprocesses dominated by API latency). Sub-second fixtures get a guard (NFR-AE-001) that silently un-enforces time on fixtures with median wall-clock < 1.0s. Multi-run averaging deferred per R-AE-1.
- **OQ-AE-3 (RESOLVED 2026-04-25 per §Reconciliation Directive 1)**: pricing seed values RECONCILED to 2026-04-25 Anthropic-published rates. Opus = `$5/$25/$0.50` (PRD example was wrong — tracked Opus 4/4.1 legacy pricing). Sonnet = `$3/$15/$0.30` (matches PRD). Haiku = `$1/$5/$0.10` (PRD example was wrong — tracked Haiku 3.5).
- **OQ-AE-4 (RESOLVED 2026-04-25 per §Reconciliation Directive 3)**: `gdate` is NOT reliably available on macOS dev environments. Probe ladder is now `python3 time.monotonic()` (preferred) → `gdate` → `/bin/date +%s.%N` → abort. `python3` is already a documented kiln dependency, so no new runtime cost.
- **OQ-AE-5 (report layout for 4 axes in 120-col terminal)**: FR-AE-016 mandates four new columns on the per-fixture markdown table. The 120-col scroll-fit invariant from foundation NFR-S-005 MAY require column-shape compromise (e.g., `Time s` rendered as `B/C` shorthand instead of separate columns; `Cost USD` rendered as `Δ` only with full values in a footer). Plan resolves the layout decision; spec mandates the columns + scroll-fit invariant only.
- **OQ-AE-6 (per-fixture time-axis warning vs aggregate-only warning)**: FR-AE-001 + NFR-AE-001 imply per-fixture `time-axis-noisy` warnings when variance exceeds tolerance. Should this be per-fixture (loud) or aggregate-only (quiet)? Default: per-fixture (loud — maintainers should see noise on the fixture that triggered it). Plan resolves.

## Notes for Reviewers

- This PRD is steps 2 + 3 of the seven-step `09-research-first` phase. Steps 4-7 (synthesizer, judge, build-prd wiring, classifier inference) are EXPLICITLY out of scope. Reviewers MUST flag any FR/NFR drift toward those steps.
- The atomic pairing invariant (NFR-AE-005) is non-negotiable. Reviewers MUST verify the PR diff contains BOTH `research-rigor.json` AND `pricing.json` AND the runner extensions for both surfaces. A "gate-only" or "axes-only" subset cannot ship.
- Backward compat (NFR-AE-003 / SC-AE-005) is non-negotiable. PRDs without `empirical_quality:` MUST see byte-identical foundation strict-gate behavior. The audit-compliance teammate re-runs the foundation's 5 existing test fixtures.
- Loud-failure on config malformation (NFR-AE-007) is the load-bearing safety property. NEVER silently fall back to a hardcoded default rigor or pricing table — that surface is exactly how research-runs would silently produce-misleading-numbers in CI.
- Researcher-baseline reconciliation (§Reconciliation Against Researcher-Baseline above) is REQUIRED before `/tasks` finalizes. Pricing seed values + time-axis tolerance + monotonic-clock availability are the three thresholds that need live data, not PRD-literal lockdown.
