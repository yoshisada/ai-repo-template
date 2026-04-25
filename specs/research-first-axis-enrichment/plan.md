# Implementation Plan: Research-First Axis Enrichment — Per-Axis Direction Gate + Time/Cost Axes

**Branch**: `build/research-first-axis-enrichment-20260425` | **Date**: 2026-04-25 | **Spec**: [spec.md](./spec.md)
**Input**: `specs/research-first-axis-enrichment/spec.md`
**PRD**: `docs/features/2026-04-25-research-first-axis-enrichment/PRD.md`
**Foundation dependency**: `specs/research-first-foundation/{spec.md,plan.md,contracts/interfaces.md}` (PR #176, in main).
**Baseline research**: `specs/research-first-axis-enrichment/research.md` (RECONCILED 2026-04-25 — pricing + time-noise + monotonic clock).

## Summary

Extend the foundation runner (`plugin-wheel/scripts/harness/research-runner.sh`, ~309 LoC currently) with FOUR atomic-paired surfaces shipped in ONE PR:

1. **PRD-frontmatter parser** — read `empirical_quality:`, `blast_radius:`, `excluded_fixtures:` from the calling PRD into a runtime context. Frontmatter parsing lives in a new helper at `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh`. The runner gains a `--prd <path>` flag (optional — when omitted, falls through to foundation strict gate per FR-AE-008/NFR-AE-003).
2. **Per-axis direction gate** — replace the foundation's hardcoded `> baseline_total * 1.5` strict gate with a declarative direction-evaluator at `plugin-wheel/scripts/harness/evaluate-direction.sh` keyed off `empirical_quality:` + `tolerance_pct` from `plugin-kiln/lib/research-rigor.json`. Backward-compat path (no `empirical_quality:` declared) is preserved via an explicit fall-through codepath.
3. **Time + cost axes** — runner captures `time_seconds` per fixture per arm via the `python3 time.monotonic()` ladder (NFR-AE-006), derives `cost_usd` per fixture per arm via a new helper `plugin-wheel/scripts/harness/compute-cost-usd.sh` reading the hand-maintained `plugin-kiln/lib/pricing.json`. Per-fixture sub-second guard (NFR-AE-001) silently un-enforces time-axis on fixtures with median wall-clock < 1.0s.
4. **Report extensions** — `render-research-report.sh` gains four columns (`Time s`, `Cost USD`, two `Per-Axis Verdict` cells), aggregate summary lists declared axes + rigor row + excluded count + pricing-table-miss warnings + sub-second-skipped warnings.

The atomic pairing invariant (NFR-AE-005) is the load-bearing structural constraint: both `research-rigor.json` AND `pricing.json` AND the runner extensions for both surfaces MUST land in the same PR diff. tasks.md interleaves step-2 + step-3 work — no carved-out "axes-only" or "gate-only" phase.

Implementation is an **extension**, not a refactor. Foundation-listed-untouchable files (`wheel-test-runner.sh` + 12 sibling helpers) remain byte-untouched (NFR-AE-009 sibling of foundation NFR-S-002). `parse-token-usage.sh` + `render-research-report.sh` MAY be modified ONLY in additive ways that preserve foundation determinism + back-compat fixtures.

## Technical Context

**Language/Version**: Bash 5.x (the runner + helpers are Bash; no JS/TS in net-new code paths).
**Primary Dependencies**:
- Existing `plugin-wheel/scripts/harness/research-runner.sh` + `parse-token-usage.sh` + `render-research-report.sh` (foundation — additively extended, NOT forked).
- `claude` CLI v2.1.119+ (inherited from foundation).
- `jq` for JSON parsing of `research-rigor.json` + `pricing.json` + PRD frontmatter (loud-failure on parse error per NFR-AE-007).
- `python3` for `time.monotonic()` AND for YAML frontmatter parsing in `parse-prd-frontmatter.sh` (stdlib `re`/`json`; YAML is parsed by hand-rolled regex since PyYAML is not a kiln dependency — same approach as the existing `plugin-wheel/scripts/agents/compose-context.sh`).
- POSIX `find`/`sort`/`awk`/`stat` (no net-new utilities).
**Storage**: filesystem only — `research-rigor.json` + `pricing.json` committed at `plugin-kiln/lib/`, reports at `.kiln/logs/research-<uuid>.md` (gitignored, foundation precedent).
**Testing**: shell-test fixtures under `plugin-kiln/tests/research-runner-axis-*/` matching the foundation's 5-fixture precedent shape. Each fixture is a `run.sh` + `fixtures/` directory with synthetic transcripts + plugin-dirs + PRD-frontmatter probe files.
**Target Platform**: macOS + Linux developer machines + GitHub Actions (matches foundation target surface).
**Project Type**: developer-tooling extension to an existing CLI substrate (no service layer, no UI, no DB).
**Performance Goals**: foundation budget (≤ 240s on 3-fixture corpus, recalibrated 2026-04-25 in foundation spec) is preserved. Axis-enrichment adds < 1% wall-clock overhead per fixture (the `evaluate-direction.sh` + `compute-cost-usd.sh` helpers are sub-millisecond shell + jq operations; they do NOT add subprocess calls).
**Constraints**:
- Zero modifications to the 14 foundation-untouchable files (NFR-AE-009 — extends NFR-S-003 from foundation).
- Backward compat: PRDs without `empirical_quality:` MUST diff-zero against foundation strict-gate output modulo the §3 exclusion comparator (NFR-AE-003).
- Atomic pairing: BOTH `research-rigor.json` AND `pricing.json` AND runner extensions in the same PR (NFR-AE-005).
- Loud-failure on config malformation: NEVER silently fall back to a hardcoded default rigor or pricing table (NFR-AE-007).
- Report layout: 4 new columns must fit a 120-col terminal — see Decision 1 below.
**Scale/Scope**:
- Existing `research-runner.sh`: extends ~309 → ~450 LoC (gate refactor + time-capture + cost-derivation + report-extension wiring).
- New helpers: `parse-prd-frontmatter.sh` (~80 LoC), `evaluate-direction.sh` (~60 LoC), `compute-cost-usd.sh` (~50 LoC), `resolve-monotonic-clock.sh` (~40 LoC). Total net-new shell ≤ 230 LoC across 4 helpers.
- Existing `render-research-report.sh`: extends ~134 → ~200 LoC (4 new columns + extended aggregate).
- Existing `parse-token-usage.sh`: byte-untouched (already emits all the fields cost-derivation needs — confirmed against foundation contracts/interfaces.md §3).
- Config files: `plugin-kiln/lib/research-rigor.json` (~15 LoC), `plugin-kiln/lib/pricing.json` (~20 LoC).
- Test fixtures: ~9 new fixtures under `plugin-kiln/tests/research-runner-axis-*/` (anchored to SC-AE-001..009).
- Total net-new shell ≤ 600 LoC across helpers + extensions; total artifacts ≤ 800 LoC including tests.

## Resolution of OQ-AE-5..OQ-AE-6 (Spec Open Questions)

The spec left two Open Questions for plan-phase resolution. Resolved as follows:

- **OQ-AE-5 (report layout for 4 axes in 120-col terminal)**: RESOLVED — see Decision 1 below. Layout: `Fixture | Acc B/C | Tokens B/C | Δ Tok | Time B/C | Δ Time | Cost B/C | Δ Cost | Per-Axis Verdict`. The `Acc`, `Tokens`, `Time`, `Cost` columns use compact `B/C` shorthand (e.g., `pass/pass`, `19/19`, `0.45/0.43`, `$0.00012/$0.00011`). The `Per-Axis Verdict` column emits one line per declared axis (`tokens:pass`, `time:pass`) joined by `, `. Slug column ≤ 30 chars (foundation precedent). Total terminal width: ~118 chars on a 30-char-slug fixture, fits the 120-col invariant.
- **OQ-AE-6 (per-fixture vs aggregate-only sub-second-skipped warnings)**: RESOLVED — **per-fixture (loud)**. NFR-AE-001 sub-second guard emits `time-axis-skipped: <slug> wall-clock <N.Ns> below 1.0s floor` ONCE per affected fixture in the aggregate summary's "Warnings" subsection. This makes the noise visible to the maintainer with per-fixture provenance. Suppressing to aggregate-only would obscure WHICH fixtures triggered the guard; emitting per-fixture in the table itself would consume column budget and break OQ-AE-5's 120-col invariant.

## Constitution Check

*GATE: Must pass before Phase 1 design. Re-check after Phase 1.*

| Article | Pass | Justification |
|---|---|---|
| **I. Spec-First** | ✅ | spec.md committed; FRs/NFRs/SCs all numbered; every plan task references an FR/NFR/SC anchor. |
| **II. 80% Coverage** | ✅ | Net-new code paths exercised by 9 dedicated test fixtures + foundation's 5 existing fixtures re-run for backward-compat (NFR-AE-003). `bashcov` if installed; foundation precedent (fixture-suite-as-coverage-proof) applies. NFR-AE-008 anchor. |
| **III. PRD Source of Truth** | ✅ | Plan does not contradict PRD. Pricing values + time-tolerance + monotonic-clock decisions are reconciled to research.md §baseline (NOT silently widened). |
| **IV. Hooks Enforce Rules** | ✅ | `.claude/settings.json` hooks (`require-spec.sh`) enforce that `src/` edits are gated. Net-new files live under `plugin-wheel/scripts/harness/`, `plugin-kiln/lib/`, `plugin-kiln/tests/` — outside `src/` scope, matching foundation precedent. |
| **V. E2E Testing** | ✅ | The 9 axis-enrichment test fixtures invoke `bash plugin-wheel/scripts/harness/research-runner.sh --prd <path>` directly with synthetic + live PRD-frontmatter probe files. Foundation's 5 fixtures re-run for backward-compat (SC-AE-005). |
| **VI. Small, Focused Changes** | ✅ | Net-new code ≤ 600 LoC. Largest single file (extended `research-runner.sh`) reaches ~450 LoC, under Article VI's 500-line ceiling. Four small helpers (≤ 80 LoC each) keep the orchestrator lean. |
| **VII. Interface Contracts** | ✅ | `contracts/interfaces.md` enumerates exact signatures for the 4 net-new helpers + extended runner CLI + extended report layout + extended per-fixture JSON shape. All implementation tasks reference contract sections. |
| **VIII. Incremental Task Completion** | ✅ | tasks.md (next phase) MUST partition into 4 phases: (A) config files + frontmatter parser, (B) gate refactor + direction-evaluator, (C) time/cost axes + helpers, (D) report extensions + tests. Phases B+C are STRICTLY interleaved per NFR-AE-005 atomic-pairing. Implementer commits per phase. |

**Gate result**: PASS. No violations. Complexity Tracking section unused.

## Project Structure

### Documentation (this feature)

```text
specs/research-first-axis-enrichment/
├── plan.md                    # this file
├── spec.md                    # ✅ written this PR (RECONCILED 2026-04-25)
├── research.md                # ✅ written by researcher-baseline teammate (Phase 0 sibling)
├── contracts/
│   └── interfaces.md          # written this PR — Article VII anchor
├── checklists/
│   └── requirements.md        # ✅ written this PR
├── tasks.md                   # written by /tasks (next chained command)
├── blockers.md                # written ONLY if NFR-AE-005 (atomic pairing) or NFR-AE-009 (foundation untouchability) becomes infeasible
└── agent-notes/
    ├── specifier.md           # FR-009 friction note (this teammate)
    ├── researcher-baseline.md # FR-009 friction note (researcher-baseline teammate, ✅ committed)
    ├── impl-runner.md         # FR-009 friction note (impl-runner teammate)
    ├── audit-compliance.md    # FR-009 friction note
    ├── audit-smoke.md         # FR-009 friction note
    ├── audit-pr.md            # FR-009 friction note
    └── retrospective.md       # FR-009 friction note
```

### Source Code (repository root)

```text
plugin-wheel/scripts/harness/
├── research-runner.sh                    # EXTENDED (~309 → ~450 LoC) — adds --prd flag, gate dispatch, time-capture, cost-derivation
├── parse-token-usage.sh                  # UNTOUCHED — already emits all fields needed (foundation contract §3)
├── render-research-report.sh             # EXTENDED (~134 → ~200 LoC) — 4 new columns + aggregate extensions
├── parse-prd-frontmatter.sh              # NEW (~80 LoC) — reads empirical_quality, blast_radius, excluded_fixtures
├── evaluate-direction.sh                 # NEW (~60 LoC) — applies direction + tolerance_pct per axis per fixture
├── compute-cost-usd.sh                   # NEW (~50 LoC) — derives cost_usd from tokens × pricing.json
├── resolve-monotonic-clock.sh            # NEW (~40 LoC) — startup probe (python3 → gdate → /bin/date → abort)
├── README-research-runner.md             # EXTENDED — appends "Per-axis gate" + "Time/Cost axes" + "Authoring empirical_quality:" sections
├── wheel-test-runner.sh                  # UNTOUCHED (foundation NFR-S-002)
├── claude-invoke.sh                      # UNTOUCHED
├── config-load.sh                        # UNTOUCHED
├── scratch-create.sh                     # UNTOUCHED
├── scratch-snapshot.sh                   # UNTOUCHED
├── snapshot-diff.sh                      # UNTOUCHED — used by SC-AE-005 backward-compat audit
├── tap-emit.sh                           # UNTOUCHED
├── test-yaml-validate.sh                 # UNTOUCHED
├── dispatch-substrate.sh                 # UNTOUCHED
├── substrate-plugin-skill.sh             # UNTOUCHED
├── fixture-seeder.sh                     # UNTOUCHED
├── watcher-runner.sh                     # UNTOUCHED
└── watcher-poll.sh                       # UNTOUCHED

plugin-kiln/lib/
├── research-rigor.json                   # NEW (~15 LoC) — {isolated, feature, cross-cutting, infra}: {min_fixtures, tolerance_pct}
├── pricing.json                          # NEW (~20 LoC) — RECONCILED 2026-04-25 rates: opus 5/25/0.5, sonnet 3/15/0.3, haiku 1/5/0.1
└── task-shapes/                          # UNTOUCHED (existing)

plugin-kiln/skills/
└── kiln-research/
    └── SKILL.md                          # EXTENDED — appends "--prd <path>" flag documentation; total LoC stays ≤ 50

plugin-kiln/tests/
├── research-runner-axis-direction-pass/             # SC-AE-001 — empirical_quality time/tokens, candidate improves time, holds tokens
│   ├── run.sh
│   └── fixtures/
├── research-runner-axis-min-fixtures-cross-cutting/ # SC-AE-002 — 5-fixture corpus + cross-cutting blast → fail-fast
│   ├── run.sh
│   └── fixtures/
├── research-runner-axis-infra-zero-tolerance/       # SC-AE-003 — infra blast + 1-token regression → fail
│   ├── run.sh
│   └── fixtures/
├── research-runner-axis-cost-mixed-models/          # SC-AE-004 — mixed opus/haiku fixtures → cost_usd to 4dp
│   ├── run.sh
│   └── fixtures/
├── research-runner-axis-fallback-strict-gate/       # SC-AE-005 — no empirical_quality → diff-zero with foundation
│   ├── run.sh
│   └── fixtures/
├── research-runner-axis-excluded-fixtures/          # SC-AE-006 — excluded_fixtures + min_fixtures interaction
│   ├── run.sh
│   └── fixtures/
├── research-runner-axis-pricing-stale-audit/        # SC-AE-007 — 200-day-old pricing.json → audit finding
│   ├── run.sh
│   └── fixtures/
├── research-runner-axis-no-monotonic-clock/         # SC-AE-009 — mocked-out clocks → bail-out diagnostic
│   ├── run.sh
│   └── fixtures/
├── research-runner-axis-pricing-table-miss/         # FR-AE-012 / Edge case — unknown model → cost_usd null
│   ├── run.sh
│   └── fixtures/
├── research-runner-pass-path/                       # FOUNDATION — re-run for SC-AE-005 backward-compat
├── research-runner-regression-detect/               # FOUNDATION — re-run for SC-AE-005 backward-compat
├── research-runner-determinism/                     # FOUNDATION — re-run for SC-AE-005 backward-compat
├── research-runner-missing-usage/                   # FOUNDATION — re-run for SC-AE-005 backward-compat
└── research-runner-back-compat/                     # FOUNDATION — re-run for SC-AE-005 backward-compat
```

**Structure Decision**: Single-project layout extending the foundation's CLI substrate. Net-new helpers colocated with foundation harness scripts under `plugin-wheel/scripts/harness/`. Config files under `plugin-kiln/lib/` (foundation precedent — `task-shapes/` lives at the same level). Test fixtures under `plugin-kiln/tests/research-runner-axis-*/` matching the foundation's 5-fixture precedent.

## Phase 0 — Outline & Research

### Status

- **researcher-baseline teammate** — committed `research.md §baseline` (✅, 2026-04-25, 66 lines). Three reconciliation directives applied (pricing, time-tolerance, monotonic-clock) — all integrated into spec.md §Reconciliation Against Researcher-Baseline.
- **specifier teammate** (this teammate) — owns spec.md (✅), plan.md (✅), contracts/interfaces.md (✅ next), tasks.md (next).

### Phase 0 Deliverables

| Deliverable | Owner | Status |
|---|---|---|
| `research.md §baseline` (pricing values + time-noise + monotonic-clock probe) | researcher-baseline | ✅ committed 2026-04-25 |
| `spec.md` reconciliation block updates (post-baseline) | specifier | ✅ this PR |
| `plan.md §Phase 0` technology-decisions block (this section, immediately below) | specifier | ✅ this PR |

### Technology Decisions (Phase 0 sibling)

#### Decision 1: Report layout for 4 axes in 120-col terminal (resolves OQ-AE-5)

- **Decision**: Per-fixture markdown table layout:

  ```text
  | Fixture | Acc B/C | Tokens B/C | Δ Tok | Time B/C | Δ Time | Cost B/C | Δ Cost | Per-Axis Verdict |
  ```

  Compact `B/C` shorthand (e.g., `pass/pass`, `19/19`, `0.45/0.43`, `$0.00012/$0.00011`). `Per-Axis Verdict` emits one verdict per declared axis joined by `, ` (e.g., `tokens:pass, time:pass`). Slug column ≤ 30 chars (foundation NFR-S-005 precedent).
- **Rationale**: Total terminal width on a worst-case 30-char slug fixture: ~118 chars, fits the 120-col invariant. `B/C` shorthand collapses 8 numeric cells to 4 visual cells. `Δ` adjacent columns surface the deltas without doubling the table width.
- **Alternatives considered**: (a) full separate baseline + candidate columns for each axis (8 numeric cells) — rejected (exceeds 120-col by ~40 chars on representative fixture slugs); (b) emitting `Time` + `Cost` only in a footer section, not per-fixture — rejected (loses per-fixture provenance for the maintainer); (c) using ASCII art table separators (`├` / `┤`) — rejected (inconsistent rendering on terminal vs markdown viewer; foundation uses pipes).

#### Decision 2: Per-fixture vs aggregate-only sub-second-skipped warnings (resolves OQ-AE-6)

- **Decision**: Per-fixture warnings emitted in the aggregate summary's "Warnings" subsection (not the per-fixture table). One line per affected fixture: `time-axis-skipped: <slug> wall-clock <N.Ns> below 1.0s floor`.
- **Rationale**: Per-fixture provenance is preserved without consuming column budget. Maintainers see WHICH fixtures triggered the guard and can act on them.
- **Alternatives considered**: (a) per-fixture in the table (`time:skipped` instead of `time:pass`) — rejected (consumes column budget, breaks OQ-AE-5's 120-col invariant); (b) aggregate-only count (`5 fixtures sub-second-skipped`) — rejected (loses per-fixture provenance, maintainer can't know which ones); (c) silent skip with no warning — rejected (violates loud-failure invariant per NFR-AE-007).

#### Decision 3: PRD frontmatter parser placement

- **Decision**: A standalone helper at `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh` consumed by `research-runner.sh` only.
- **Rationale**: Co-located with sibling harness helpers ⇒ same dual-layout discovery surface as foundation's `parse-token-usage.sh`. Generic API (PRD path → JSON-shaped frontmatter projection on stdout) leaves the door open for future PRDs to consume it. Avoids inlining YAML-parsing complexity in the orchestrator.
- **Alternatives considered**: (a) inlining in `research-runner.sh` — rejected (orchestrator would balloon past Article VI 500-line ceiling); (b) placing under `plugin-kiln/scripts/research/` — rejected (couples to plugin-kiln when it's plugin-agnostic, mirroring foundation Decision 1); (c) reusing `plugin-wheel/scripts/agents/compose-context.sh`'s YAML-parsing logic — partially adopted (we follow its hand-rolled regex approach since PyYAML is not a kiln dependency), but separate file because its API shape differs.

#### Decision 4: Direction-evaluator helper placement

- **Decision**: A standalone helper at `plugin-wheel/scripts/harness/evaluate-direction.sh` consumed by `research-runner.sh` only. Takes a per-axis verdict request (axis, direction, tolerance_pct, baseline_value, candidate_value) on stdin or via flags; emits `pass` / `regression` / `not-enforced` on stdout.
- **Rationale**: Separating "data measurement" (runner) from "verdict adjudication" (evaluator) keeps the runner's gate-dispatch logic ≤ 30 LoC and makes the direction-evaluator unit-testable in isolation. Mirrors foundation's `parse-token-usage.sh` separation.
- **Alternatives considered**: (a) inlining as a Bash function in the runner — rejected (5 axes × 3 directions × tolerance interaction balloons the orchestrator past Article VI ceiling); (b) Python implementation — rejected (Bash is more grep-able, matches foundation discipline).

#### Decision 5: Cost derivation as a separate helper

- **Decision**: A standalone helper at `plugin-wheel/scripts/harness/compute-cost-usd.sh` consumed by `research-runner.sh` only. Takes per-fixture token counts + model_id + path-to-pricing.json; emits `<cost_usd>` (4dp precision) on stdout, exits with `cost_usd: null` and a stderr warning on missing model_id, exits 2 with `Bail out!` on malformed pricing.json.
- **Rationale**: Isolates the FR-AE-011 formula (`(in × $/in + out × $/out + cached × $/cached) / 1_000_000`) for unit testability + future portability. Mirrors `parse-token-usage.sh` precedent.
- **Alternatives considered**: (a) inlining in runner — rejected (5-line formula × 3 lookup branches × null-handling balloons past Article VI ceiling); (b) deriving cost in `render-research-report.sh` — rejected (couples presentation to derivation; cost is gate-evaluated input data, not just rendering).

#### Decision 6: Monotonic-clock startup-probe as a separate helper

- **Decision**: A standalone helper at `plugin-wheel/scripts/harness/resolve-monotonic-clock.sh`. Walks the NFR-AE-006 ladder (`python3 time.monotonic()` → `gdate +%s.%N` → `/bin/date +%s.%N` → abort). Emits the resolved invocation as a single string on stdout (e.g., `python3 -c 'import time; print(time.monotonic())'`); exits 2 with `Bail out!` if all rungs fail.
- **Rationale**: Isolates the OS-portability probe for unit-testability (the SC-AE-009 fixture mocks PATH to verify the abort path). Caller captures stdout + uses it via `eval` for the per-fixture timing.
- **Alternatives considered**: (a) inlining in runner — rejected (probe + ladder + error message is ~30 LoC, would dilute the orchestrator); (b) using shell `command -v` directly without abstraction — rejected (mocking out PATH for SC-AE-009 testability requires an isolated helper).

#### Decision 7: Backward-compat dispatch via explicit fall-through codepath

- **Decision**: When `--prd <path>` is omitted OR the PRD's frontmatter has NO `empirical_quality:` field, the runner takes an explicit `gate_mode=foundation_strict` codepath that bypasses `evaluate-direction.sh` entirely and uses the foundation's hardcoded `> baseline_total * 1.5` rule. The two codepaths share the parser + report-renderer but diverge ONLY on gate-rule application.
- **Rationale**: Explicit codepath split (vs. emulating strict-gate via direction-evaluator with synthetic inputs) makes backward-compat audit (NFR-AE-003 / SC-AE-005) trivial — the audit-compliance teammate runs the foundation's 5 existing fixtures + diff-zero. An "emulated" strict gate would have subtle output drift from edge cases like accuracy-only declaration.
- **Alternatives considered**: (a) emulate strict gate via direction-evaluator with `direction: equal_or_better, tolerance_pct: 50` — rejected (subtle drift on tolerance edge cases, violates byte-identical SC-AE-005); (b) deprecate strict-gate path entirely + force all PRDs to declare `empirical_quality:` — rejected (breaks backward compat NFR-AE-003 outright).

#### Decision 8: Atomic-pairing tripwire enforcement

- **Decision**: SC-AE-008 anchors a CI-runnable check via `git diff main...HEAD --name-only | grep -E 'plugin-kiln/lib/(research-rigor|pricing)\.json'`. Audit-compliance teammate executes this check + emits a pass/fail to `agent-notes/audit-compliance.md`. If only ONE of the two files is in the diff, the audit-compliance teammate REJECTS the PR and surfaces an NFR-AE-005-non-compliant blocker.
- **Rationale**: NFR-AE-005 atomic-pairing is the load-bearing structural invariant of this PRD. A CI-runnable assertion (vs. reviewer judgment call) makes the invariant non-bypassable.
- **Alternatives considered**: (a) reviewer-judgment-only — rejected (atomic pairing is a structural property, not editorial); (b) git pre-commit hook — rejected (consumer projects can disable hooks; CI gate is the fallback).

### Phase 0 Output

- `research.md §baseline` — researcher-baseline teammate (✅).
- This `plan.md §Phase 0` block — ✅ this PR.

## Phase 1 — Design & Contracts

**Prerequisites**: `research.md §baseline` committed (✅) AND spec.md reconciliation block updated (✅).

### Entities (from spec.md §Key Entities)

| Entity | Storage | Validation |
|---|---|---|
| **Empirical-quality declaration** | PRD frontmatter (YAML list) | parse via `parse-prd-frontmatter.sh`; validate metric ∈ {accuracy, tokens, time, cost, output_quality}, direction ∈ {lower, higher, equal_or_better}, priority ∈ {primary, secondary} |
| **Rigor row** | `plugin-kiln/lib/research-rigor.json` | parse via `jq`; validate keys ∈ {isolated, feature, cross-cutting, infra}; each value has min_fixtures (int) + tolerance_pct (int) |
| **Pricing entry** | `plugin-kiln/lib/pricing.json` | parse via `jq`; per-model {input_per_mtok, output_per_mtok, cached_input_per_mtok} all numeric |
| **Per-axis verdict** | bash variable | enum: `pass` / `regression` / `not-enforced` |
| **Time axis** | bash variable (float, monotonic-derived) | non-negative; sub-second guard if median < 1.0s |
| **Cost axis** | bash variable (float, 4dp) | derived; `null` if model_id missing from pricing.json |
| **Excluded-fixture entry** | PRD frontmatter (YAML list) | parse via `parse-prd-frontmatter.sh`; path must exist in corpus |
| **Pricing-table-miss warning** | bash array, surfaced in aggregate | one entry per fixture with missing model_id |
| **Pricing-table-stale audit finding** | `agent-notes/audit-compliance.md` | emitted by auditor (not runner) when mtime > 180 days |
| **Excluded-fraction-high warning** | bash variable, surfaced in aggregate | emitted when excluded count > 30% of corpus |

No data-model.md emitted — entity set is small enough that the table above + `contracts/interfaces.md` is canonical (foundation precedent).

### Interface Contracts

See `contracts/interfaces.md` (this PR). Contract section anchors:

- **§1 — Extended per-fixture result JSON shape** (foundation §1 + `time_seconds` + `cost_usd` + per-axis verdict).
- **§2 — Extended `research-runner.sh` CLI contract** (foundation §2 + `--prd <path>` flag).
- **§3 — `parse-prd-frontmatter.sh` CLI contract**.
- **§4 — `evaluate-direction.sh` CLI contract**.
- **§5 — `compute-cost-usd.sh` CLI contract**.
- **§6 — `resolve-monotonic-clock.sh` CLI contract**.
- **§7 — `research-rigor.json` schema**.
- **§8 — `pricing.json` schema**.
- **§9 — Extended report markdown shape** (foundation §8 + 4 new columns + extended aggregate).
- **§10 — Extended `kiln:kiln-research` SKILL contract** (foundation §7 + `--prd <path>`).
- **§11 — Foundation-untouchable invariant** (foundation §10 + this PRD's runner+renderer additive-only constraint).
- **§12 — Test fixture contracts** (SC-AE-001..009 anchors).
- **§13 — Function/exit-code summary table**.

### Quickstart

The foundation's `README-research-runner.md` is EXTENDED with three new sections: "Authoring `empirical_quality:` in PRD frontmatter", "Configuring blast-radius rigor", "Time + Cost axes in reports". Total length stays ≤ 250 LoC (foundation invariant was ≤ 200 LoC; we widen by 50 LoC for the three sections). Path: `plugin-wheel/scripts/harness/README-research-runner.md`.

### Agent context update

CLAUDE.md "Active Technologies" block is auto-trimmed to the last 5 feature branches per the rubric. This PRD's tech stack inherits from existing branches (foundation = `wheel-as-runtime` precursor + `wheel-test-runner-extraction`). NEW entries to add: `python3 time.monotonic()` (canonical monotonic clock), `plugin-kiln/lib/research-rigor.json` + `plugin-kiln/lib/pricing.json` (hand-maintained config files). The `update-agent-context.sh` invocation is REQUIRED for this PRD — adds one line under Active Technologies.

## Phase 2 — Tasks (handled by `/tasks`, NOT this command)

Outline of what `/tasks` will produce (informational — not the actual task list). Atomic-pairing invariant (NFR-AE-005) requires Phases B + C to be **strictly interleaved** — no carved-out "axes-only" or "gate-only" subset:

### Phase A — Config files + frontmatter parser (no orchestration changes yet)

1. Author `plugin-kiln/lib/research-rigor.json` per `contracts/interfaces.md §7`. Values from PRD `## Implementation Hints` table (verbatim).
2. Author `plugin-kiln/lib/pricing.json` per `contracts/interfaces.md §8`. Values RECONCILED from research.md §baseline (opus 5/25/0.5, sonnet 3/15/0.3, haiku 1/5/0.1).
3. Author `parse-prd-frontmatter.sh` (~80 LoC) per `contracts/interfaces.md §3`. Test against synthetic PRDs.
4. Author `resolve-monotonic-clock.sh` (~40 LoC) per `contracts/interfaces.md §6`. SC-AE-009 anchor.

### Phase B+C — Gate refactor + time/cost axes (interleaved per NFR-AE-005)

5. Author `evaluate-direction.sh` (~60 LoC) per `contracts/interfaces.md §4`. Unit-test against synthetic verdict requests.
6. Author `compute-cost-usd.sh` (~50 LoC) per `contracts/interfaces.md §5`. Unit-test against pricing.json + token tuples.
7. Extend `research-runner.sh` to add the `--prd <path>` flag, dispatch on presence/absence of `empirical_quality:` (Decision 7), invoke `parse-prd-frontmatter.sh` at startup, capture `time_seconds` + `cost_usd` per arm, surface `pricing-table-miss` + sub-second-skipped warnings.
8. Extend `research-runner.sh` to enforce `min_fixtures` fail-fast PRE-subprocess (US-2 anchor) + per-axis tolerance via `evaluate-direction.sh` invocation per declared axis per fixture.
9. Author `research-runner-axis-direction-pass/run.sh` (SC-AE-001).
10. Author `research-runner-axis-min-fixtures-cross-cutting/run.sh` (SC-AE-002).
11. Author `research-runner-axis-infra-zero-tolerance/run.sh` (SC-AE-003).
12. Author `research-runner-axis-cost-mixed-models/run.sh` (SC-AE-004).
13. Author `research-runner-axis-fallback-strict-gate/run.sh` (SC-AE-005).
14. Author `research-runner-axis-excluded-fixtures/run.sh` (SC-AE-006).
15. Author `research-runner-axis-pricing-table-miss/run.sh` (FR-AE-012 / Edge case).
16. Author `research-runner-axis-no-monotonic-clock/run.sh` (SC-AE-009).

### Phase D — Report extensions + audit + docs

17. Extend `render-research-report.sh` to add 4 columns + extended aggregate per `contracts/interfaces.md §9`. Verify per-fixture column-budget (Decision 1) on representative slugs.
18. Author `research-runner-axis-pricing-stale-audit/run.sh` (SC-AE-007). The audit-compliance teammate's mtime probe lives under `agent-notes/audit-compliance.md` — runner does NOT fail on stale pricing.
19. Extend `README-research-runner.md` with three new sections (≤ 250 LoC total).
20. Re-run foundation's 5 existing fixtures (`research-runner-pass-path`, `research-runner-regression-detect`, `research-runner-determinism`, `research-runner-missing-usage`, `research-runner-back-compat`) — diff-zero per the §3 exclusion comparator (NFR-AE-003 / SC-AE-005).
21. Run end-to-end smoke against axis-enrichment seed corpus to verify atomic-pairing invariant (SC-AE-008 — `git diff main...HEAD --name-only` contains both `research-rigor.json` AND `pricing.json`).

### Phase E — Audit + retrospective

22. PRD compliance audit (audit-compliance teammate) — verifies every PRD FR/NFR/SC has a spec FR/NFR/SC + implementation + test.
23. Smoke audit (audit-smoke teammate) — runtime invocation of axis-enrichment seed corpus + verifies report shape.
24. Atomic-pairing tripwire audit (audit-compliance teammate) — verifies SC-AE-008 git-diff invariant.

## Tooling Decisions (Bash discipline)

- All shell scripts: `set -euo pipefail` at top, `harness_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)` for sibling resolution. Mirrors foundation's `wheel-test-runner.sh` precedent.
- Logging: stderr for diagnostics + warnings, stdout reserved for TAP + report-uuid + helper outputs (frontmatter projection, direction verdict, cost_usd, monotonic-clock invocation). Never mix.
- Error handling: `bail_out()` helper emits `Bail out! <msg>` + exit 2 (foundation NFR-S-008 / spec NFR-AE-007 anchor).
- Tempfile cleanup: `trap 'rm -f $tmpfiles' EXIT` for any tmpfile work.
- JSON shaping: `jq` for parse + emit. `python3` reserved for monotonic-clock probe + YAML frontmatter parsing (no PyYAML).
- Determinism: `LC_ALL=C` + `sort -z` for any iteration over directories. `jq -c -S` for byte-stable JSON output.
- Loud-failure: ALL config-file parse errors `Bail out!` + exit 2; NEVER silently fall back to a hardcoded default rigor or pricing table (NFR-AE-007).

## Risk Tracking

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Atomic-pairing violation (only one of `research-rigor.json` / `pricing.json` ships) | Low | High (ship-blocking) | SC-AE-008 git-diff tripwire enforced by audit-compliance teammate. |
| Backward-compat regression on PRDs without `empirical_quality:` | Medium | High (ship-blocking) | Decision 7 explicit fall-through codepath; foundation's 5 fixtures re-run + diff-zero per SC-AE-005. |
| Monotonic-clock probe fails on a host without python3 AND coreutils AND BSD-date-with-%N | Low | Low | NFR-AE-006 ladder + SC-AE-009 fixture documents the abort behavior; abort message names actionable remediation. |
| Sub-second fixture sub-second guard fires on a fixture maintainer expects to gate on time | Medium | Low | Per-fixture warning surfaced in aggregate (Decision 2); maintainer can see + adjust corpus. |
| Pricing-table refresh forgotten on Anthropic price change | Medium | Medium | SC-AE-007 pricing-table-stale audit finding (180-day mtime); auditor surfaces but does NOT fail run. Source-item hint R-AE-2 acknowledges whitespace-edit evasion. |
| Stream-json `message.model` absent on harness-generated fixtures | Medium | Low | FR-AE-012 `cost_usd: null` + warning; Edge Case "PRD declares ONLY cost and all fixtures null" prevents silent pass-through. |
| Article VI 500-line ceiling violation on extended `research-runner.sh` | Medium | Medium | Decisions 3-6 split logic into 4 small helpers; orchestrator stays ~450 LoC. |
| Loud-failure on malformed pricing.json blocks unrelated runs | Low | Low | Edge Case "pricing.json malformed" emits clear `Bail out!` with `jq` parse error verbatim. Maintainer fixes the file or removes it (cost-axis-declaration would then fail at startup with a different `Bail out!`). |
| Time-axis variance > 5% on real research-run fixtures (vs harness floor) | Low (per research.md) | Low | Sub-second guard (NFR-AE-001) handles the degenerate case; multi-run averaging deferred per R-AE-1 if real-fixture flakes emerge. |

## Open Questions

- None outstanding. All spec Open Questions (OQ-AE-2..6) resolved either in spec.md §Reconciliation (OQ-AE-2..4) or this plan §Resolution of OQ-AE-5..6.

## Complexity Tracking

> No constitutional violations. Section unused.

## Re-evaluate Constitution Check (Post-Design)

Post-Phase-1 design re-check: all 8 articles still pass. NFR-AE-009 (foundation untouchability) is the most likely violation source; the additive-only invariant on `parse-token-usage.sh` + `render-research-report.sh` is enforceable via diff-review (audit-compliance teammate runs `git diff main...HEAD plugin-wheel/scripts/harness/parse-token-usage.sh` + verifies output is empty). The renderer extension is a careful additive change (4 new columns + extended aggregate; existing rows + foundation aggregate untouched). Plan stands.
