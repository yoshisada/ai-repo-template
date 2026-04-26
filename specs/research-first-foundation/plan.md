# Implementation Plan: Research-First Foundation — Fixture Corpus + Baseline-vs-Candidate Runner MVP

**Branch**: `build/research-first-foundation-20260425` | **Date**: 2026-04-25 | **Spec**: [spec.md](./spec.md)
**Input**: `specs/research-first-foundation/spec.md`
**PRD**: `docs/features/2026-04-25-research-first-foundation/PRD.md`
**Baseline research**: `specs/research-first-foundation/research.md` (read first; Phase 0 contract)

## Summary

Add a sibling Bash script under `plugin-wheel/scripts/harness/` (`research-runner.sh`) that drives the existing `wheel-test-runner.sh` substrate twice per fixture (baseline arm + candidate arm) without forking it, captures per-arm metrics (assertion verdict + tokens parsed from the stream-json `usage` envelope), and emits a comparative markdown report at `.kiln/logs/research-<uuid>.md` with a strict-gate run-level verdict. Ship a 3-fixture seed corpus + a token-parser helper + a one-page README + a thin `kiln:kiln-research` SKILL wrapper. Five test fixtures under `plugin-kiln/tests/research-runner-*/` lock backward compat (NFR-S-003), determinism (SC-S-006), regression detection (SC-S-002), pass path (SC-S-003), and loud-failure (SC-S-007).

Implementation is an **extension**, not a refactor. The existing 13 harness helpers are untouched; the new runner SOURCES them via dot-include where appropriate (e.g. `config-load.sh`'s `eval` pattern) or invokes them as subprocesses (e.g. `claude-invoke.sh`). The "no fork" invariant (NFR-S-002) is the load-bearing constraint.

## Technical Context

**Language/Version**: Bash 5.x (the runner is Bash; no JS/TS in net-new code paths).
**Primary Dependencies**:
- Existing `plugin-wheel/scripts/harness/` helpers (NFR-S-002 — no fork).
- `claude` CLI v2.1.119+ (inherited from `claude-invoke.sh`).
- `jq` + `python3` (stdlib `json`) for stream-json parsing.
- `uuidgen`, POSIX `find`/`sort`/`awk`/`sed` (no net-new utilities).
**Storage**: filesystem only — corpus committed at `plugin-<name>/fixtures/<skill>/corpus/`, reports at `.kiln/logs/research-<uuid>.md` (gitignored), per-arm scratches at `/tmp/kiln-test-<uuid>/` (gitignored).
**Testing**: shell-test fixtures under `plugin-kiln/tests/research-runner-*/`. Each fixture is a directory with a `run.sh` exit-coded test (existing `plugin-kiln/tests/` precedent — see `kiln-hygiene-backfill-idempotent/run.sh` for shape). Coverage measurement via `bashcov` if installed; otherwise the smoke test gate (FR-S-009 seed corpus + 5 fixtures) is the de-facto coverage proof. Resolution in §Tooling Decisions below.
**Target Platform**: macOS + Linux developer machines + GitHub Actions (matches existing kiln-test target surface).
**Project Type**: developer-tooling extension to an existing CLI substrate (no service layer, no UI, no DB).
**Performance Goals**: 3-fixture corpus end-to-end in **≤ 240 seconds** (PRD literal 60 s superseded by RECONCILED 2026-04-25 budget per `spec.md §Reconciliation directive 1`; live measurement at lightest profile ~186 s with ~30% headroom).
**Constraints**:
- Zero modifications to `wheel-test-runner.sh` and its 12 sibling helpers (NFR-S-002).
- `/kiln:kiln-test` consumer behavior byte-identical post-PRD (NFR-S-003).
- Token-count noise ≤ **±10 tokens absolute per `usage` field** (PRD literal ±2 superseded by RECONCILED 2026-04-25 band per `spec.md §Reconciliation directive 2`; live measurement showed +3 wobble on lightest probe).
- Report ≤ 200-line README invariant (NFR-S-009).
**Scale/Scope**: 1 new runner script (~150 LoC), 1 token-parser helper (~80 LoC), 1 SKILL wrapper (~40 LoC), 1 README (~150 LoC), 3 seed fixtures, 5 test fixtures. Total net-new shell ≤ 600 LoC.

## Resolution of OQ-S-2..OQ-S-4 (Spec Open Questions)

The spec left three Open Questions for plan-phase resolution. Resolved as follows:

- **OQ-S-2 (SC-S-001 wall-clock recalibration policy)**: RESOLVED 2026-04-25 against research.md §baseline — recalibrated to **≤ 240 s** for the 3-fixture seed corpus end-to-end (was: PRD literal 60 s). Researcher-baseline showed the lightest-possible 6× wall-clock projection lands at ~186 s due to a ~20 s/fixture irreducible harness fixed-cost. The "≤ baseline-median + 20%" framing was abandoned as percentage-incompatible with an irreducible-fixed-cost workload. 240 s is an absolute envelope, not a percentage band. Step-N (parallelism, PRD Risk 3) is the right place to lower this budget toward 60 s if maintainers complain. Encoded in `contracts/interfaces.md §6` (RECONCILED 2026-04-25) and `spec.md §Reconciliation Against Researcher-Baseline directive 1`.
- **OQ-S-3 (SKILL wrapper slug)**: RESOLVED — **`kiln:kiln-research`**, separate slug, separate skill file at `plugin-kiln/skills/kiln-research/SKILL.md`. Rationale: (a) avoids coupling to `kiln-test`'s muscle-memory invocation (which is single-`--plugin-dir`, intentionally), (b) gives step 6 a clean target to wire `/kiln:kiln-build-prd` against without subcommand parsing, (c) matches the existing skill-naming convention (`kiln:kiln-fix`, `kiln:kiln-distill`, `kiln:kiln-roadmap`). The SKILL.md is a thin façade — same dual-layout sibling resolution as `kiln:kiln-test`. Encoded in **plan.md §Project Structure** and **`contracts/interfaces.md §7 (skill wrapper)`**.
- **OQ-S-4 (`parse-token-usage.sh` portability — does wheel-test-runner consume it too?)**: RESOLVED — **design generically; do NOT modify wheel-test-runner in this PRD**. The helper takes a transcript NDJSON path + writes whitespace-delimited token totals on stdout. Its API is symmetric: it does not assume a baseline-vs-candidate caller. A future PRD may wire `wheel-test-runner.sh` to call it for single-arm verdict reports (NFR-S-002 forbids that change here). Encoded in `contracts/interfaces.md §3 (parse-token-usage)`.

## Constitution Check

*GATE: Must pass before Phase 1 design. Re-check after Phase 1.*

| Article | Pass | Justification |
|---|---|---|
| **I. Spec-First** | ✅ | spec.md committed, FRs/NFRs/SCs all numbered, every plan task references an FR/NFR. |
| **II. 80% Coverage** | ✅ (with caveat) | Net-new code paths are exercised by 5 dedicated test fixtures + 3-fixture seed corpus smoke. `bashcov` is the preferred measurement tool; if not available in CI, the seed-corpus + fixture suite serves as the coverage proof per dev-tooling precedent (`wheel-test-runner-extraction` plan.md §Coverage). NFR-S-010 anchor. |
| **III. PRD Source of Truth** | ✅ | Plan does not contradict PRD. SC-S-001 + NFR-S-001 placeholders are flagged for live recalibration, not silent override. |
| **IV. Hooks Enforce Rules** | ✅ | `.claude/settings.json` hooks (`require-spec.sh`) enforce that `src/` edits are gated on spec+plan+tasks+[X]. Net-new files live under `plugin-wheel/scripts/harness/`, `plugin-kiln/skills/`, `plugin-kiln/fixtures/`, `plugin-kiln/tests/`, `plugin-wheel/scripts/harness/README-*.md`. The hook scope (`src/`) does not gate harness/skill/fixture/test edits — verified against `.claude/settings.json`. Implementer commits artifacts before code. |
| **V. E2E Testing** | ✅ | The 5 test fixtures invoke `bash plugin-wheel/scripts/harness/research-runner.sh` directly with real stream-json transcripts (synthesized for determinism / parse-error fixtures; live for SC-S-001 budget). E2E shape mirrors `kiln-hygiene-backfill-idempotent`. |
| **VI. Small, Focused Changes** | ✅ | Net-new code ≤ 600 LoC. No file > 500 lines. No new abstractions beyond the runner + helper. NFR-S-002 forbids touching the 13 existing harness scripts. |
| **VII. Interface Contracts** | ✅ | `contracts/interfaces.md` enumerates exact signatures for the 4 net-new scripts (runner, token-parser, SKILL invocation contract, report shape). All implementation tasks reference contract sections. |
| **VIII. Incremental Task Completion** | ✅ | tasks.md (next pipeline phase) MUST partition into 3 phases: (1) helpers + contracts (token-parser + report-emitter), (2) runner orchestration, (3) tests + seed corpus + README. Implementer commits per phase. |

**Gate result**: PASS. No violations. Complexity Tracking section unused.

## Project Structure

### Documentation (this feature)

```text
specs/research-first-foundation/
├── plan.md                    # this file (this PR)
├── spec.md                    # ✅ written this PR
├── research.md                # written by researcher-baseline teammate (Phase 0 sibling)
├── contracts/
│   └── interfaces.md          # written this PR — Article VII anchor
├── checklists/
│   └── requirements.md        # ✅ written this PR
├── tasks.md                   # written by /tasks (next chained command)
├── blockers.md                # written ONLY if NFR-S-002 (no fork) becomes infeasible
└── agent-notes/
    ├── specifier.md           # FR-009 friction note (this teammate)
    ├── researcher-baseline.md # FR-009 friction note (researcher-baseline teammate)
    ├── impl-runner.md         # FR-009 friction note (impl-runner teammate)
    ├── audit-compliance.md    # FR-009 friction note
    ├── audit-smoke.md         # FR-009 friction note
    ├── audit-pr.md            # FR-009 friction note
    └── retrospective.md       # FR-009 friction note
```

### Source Code (repository root)

```text
plugin-wheel/scripts/harness/
├── research-runner.sh                    # NEW (~150 LoC) — top-level orchestrator
├── parse-token-usage.sh                  # NEW (~80 LoC) — stream-json `usage` parser
├── render-research-report.sh             # NEW (~100 LoC) — emits .kiln/logs/research-<uuid>.md
├── README-research-runner.md             # NEW (≤200 LoC) — one-page how-to per FR-S-010
├── wheel-test-runner.sh                  # UNTOUCHED (NFR-S-002)
├── claude-invoke.sh                      # UNTOUCHED — sourced by research-runner via subprocess
├── config-load.sh                        # UNTOUCHED — sourced via `eval`
├── scratch-create.sh                     # UNTOUCHED — sourced via subprocess
├── scratch-snapshot.sh                   # UNTOUCHED — sourced via subprocess
├── snapshot-diff.sh                      # UNTOUCHED — used by SC-S-004 audit gate
├── tap-emit.sh                           # UNTOUCHED — sourced via subprocess
├── test-yaml-validate.sh                 # UNTOUCHED — NOT used by research-runner (corpus has its own shape)
├── dispatch-substrate.sh                 # UNTOUCHED
├── substrate-plugin-skill.sh             # UNTOUCHED
├── fixture-seeder.sh                     # UNTOUCHED
├── watcher-runner.sh                     # UNTOUCHED — sourced via subprocess
└── watcher-poll.sh                       # UNTOUCHED

plugin-kiln/skills/
└── kiln-research/
    └── SKILL.md                          # NEW (~40 LoC) — thin façade per FR-S-007 + OQ-S-3

plugin-kiln/fixtures/
└── research-first-seed/
    └── corpus/
        ├── 001-noop-passthrough/
        │   ├── input.json                # NEW — minimal stream-json payload
        │   ├── expected.json             # NEW — assertion config: exit 0
        │   └── metadata.yaml             # NEW — "anchors runner plumbing"
        ├── 002-token-floor/
        │   ├── input.json
        │   ├── expected.json
        │   └── metadata.yaml             # "verifies token parsing on minimal envelope"
        └── 003-assertion-anchor/
            ├── input.json
            ├── expected.json             # asserts a value the baseline emits but candidate may not
            └── metadata.yaml             # "exercises assertion-fail path"

plugin-kiln/tests/
├── research-runner-pass-path/            # SC-S-003 — happy path, byte-identical baseline=candidate
│   ├── run.sh
│   └── fixtures/                         # synthetic 3-fixture corpus + 2 plugin-dir copies
├── research-runner-regression-detect/    # SC-S-002 — engineered token regression
│   ├── run.sh
│   └── fixtures/
├── research-runner-determinism/          # SC-S-006 — 3-rerun stability
│   ├── run.sh
│   └── fixtures/
├── research-runner-missing-usage/        # SC-S-007 — synthetic transcript with stripped `usage`
│   ├── run.sh
│   └── fixtures/
└── research-runner-back-compat/          # SC-S-004 — diff-zero against pre-PRD wheel-test-runner output
    ├── run.sh
    └── fixtures/                         # uses 3 named pre-PRD-baselined fixtures
```

**Structure Decision**: Single-project layout extending an existing CLI substrate. New scripts colocated with existing harness scripts under `plugin-wheel/scripts/harness/` for discoverability. Skill wrapper colocated with other kiln skills at `plugin-kiln/skills/kiln-research/`. Test fixtures colocated under `plugin-kiln/tests/` matching every other plugin-kiln test convention. Seed corpus committed (NOT gitignored) under `plugin-kiln/fixtures/research-first-seed/corpus/` per Assumption A-9.

## Phase 0 — Outline & Research

### Status

- **researcher-baseline teammate** — committed `research.md §baseline` (✅, 2026-04-25, 207 lines).
- **specifier teammate** (this teammate) — owns spec.md (✅), plan.md (✅), contracts/interfaces.md (✅), reconciliation block (✅), tasks.md (next).

### Phase 0 Deliverables

| Deliverable | Owner | Status |
|---|---|---|
| `research.md §baseline` (SC-S-001 wall-clock + NFR-S-001 token-determinism live measurements) | researcher-baseline | ✅ committed 2026-04-25 |
| `spec.md` reconciliation block updates (post-baseline) | specifier | ✅ this PR (RECONCILED 2026-04-25) |
| `research.md §technology-decisions` (this section, immediately below) | specifier | ✅ this PR |

### Technology Decisions (Phase 0 sibling — written here, not in research.md)

The PRD + spec inherit the entire substrate dependency stack from `wheel-test-runner-extraction`. There are no NEEDS CLARIFICATION markers in spec.md. The following decisions are recorded for the auditor:

#### Decision 1: token parser placement (resolves OQ-S-4)

- **Decision**: A standalone helper at `plugin-wheel/scripts/harness/parse-token-usage.sh` consumed by `research-runner.sh` only.
- **Rationale**: Co-located with sibling harness helpers ⇒ same dual-layout discovery surface. Generic API (transcript path → whitespace-delimited token totals on stdout) leaves the door open for `wheel-test-runner.sh` to consume it later without rewrite. NFR-S-002 forbids touching `wheel-test-runner.sh` in this PRD.
- **Alternatives considered**: (a) inlining the parser in `research-runner.sh` — rejected (violates the "single-source token-parsing logic" intent of NFR-S-002); (b) placing the parser under `plugin-kiln/scripts/research/` — rejected (couples the helper to plugin-kiln when it's plugin-agnostic).

#### Decision 2: report renderer separation (new — not in PRD/spec)

- **Decision**: A standalone helper at `plugin-wheel/scripts/harness/render-research-report.sh` consumed by `research-runner.sh` only. Takes a JSON-shaped per-fixture results array on stdin + emits markdown to stdout.
- **Rationale**: Separating "data collection" (runner) from "presentation" (renderer) keeps the runner ≤ 150 LoC and the renderer testable in isolation (the determinism fixture can compare two renderer outputs byte-identically given the same JSON input). Mirrors the `tap-emit.sh` precedent — wheel-test-runner already separates orchestration from rendering.
- **Alternatives considered**: (a) inlining the markdown emit in `research-runner.sh` — rejected (file > 250 LoC, violates Article VI's 500-line ceiling for the orchestrator + makes determinism testing harder); (b) using `jq` to template the markdown — rejected (jq's templating ergonomics for multi-line markdown are worse than POSIX awk + heredoc).

#### Decision 3: per-arm scratch-dir prefix reuse (resolves FR-S-011)

- **Decision**: Both arms reuse the existing `/tmp/kiln-test-<uuid>/` prefix from `scratch-create.sh`. No new prefix.
- **Rationale**: Existing `.gitignore`, post-mortem tooling, and watcher-runner snapshot helpers all depend on this prefix. Introducing `/tmp/kiln-research-<uuid>/` would fork the post-mortem surface for zero gain.
- **Alternatives considered**: (a) `/tmp/kiln-research-<uuid>/baseline/` + `/tmp/kiln-research-<uuid>/candidate/` — rejected (different prefix, different cleanup logic, different gitignore line).

#### Decision 4: corpus discovery — `find` + sort, not `glob`

- **Decision**: Discover fixtures by `find <corpus> -mindepth 1 -maxdepth 1 -type d -print0 | sort -z` (matches `wheel-test-runner.sh` line 143 precedent).
- **Rationale**: Determinism (NFR-S-001) requires stable iteration order across reruns + locales. The existing harness uses this exact pattern.
- **Alternatives considered**: bash globbing — rejected (sort order is locale-dependent + not POSIX-stable).

#### Decision 5: coverage measurement tool

- **Decision**: `bashcov` if available in CI; otherwise the 5-test-fixture suite + 3-fixture seed smoke serves as the de-facto coverage proof.
- **Rationale**: NFR-S-010 anchors 80%. `bashcov` is the standard Bash coverage tool; the precedent from `wheel-test-runner-extraction` plan.md is "fixture suite ≈ coverage proof for shell" when `bashcov` is unavailable.
- **Alternatives considered**: `kcov` — comparable; `bashcov` is more widely deployed in shell projects.

### Phase 0 Output

- `research.md §baseline` — researcher-baseline teammate (BLOCKING).
- This `plan.md §Phase 0` block — ✅ this PR.

## Phase 1 — Design & Contracts

**Prerequisites**: `research.md §baseline` committed by researcher-baseline AND spec.md reconciliation block updated.

### Entities (from spec.md §Key Entities)

| Entity | Storage | Validation |
|---|---|---|
| **Corpus** | filesystem dir | exists; ≥ 1 fixture subdir |
| **Fixture** | `<corpus>/<NNN-slug>/` | `input.json` + `expected.json` exist; `metadata.yaml` ignored |
| **Arm** | bash variable (`baseline` \| `candidate`) | enum |
| **Per-fixture verdict** | bash variable | enum: `pass` \| `regression (accuracy)` \| `regression (tokens)` \| `regression (accuracy + tokens)` \| `inconclusive (<reason>)` |
| **Run-level verdict** | bash variable | enum: `PASS` \| `FAIL` |
| **Comparative report** | `.kiln/logs/research-<uuid>.md` | UUIDv4-suffixed; gitignored; markdown-rendered |

No data-model.md emitted — entity set is too small to warrant a separate file. Entities table above + `contracts/interfaces.md §1 (data shapes)` is canonical.

### Interface Contracts

See `contracts/interfaces.md` (this PR). Contract section anchors:

- **§1 — Per-fixture result JSON shape** (passed from runner → renderer).
- **§2 — `research-runner.sh` CLI contract** (FR-S-001, FR-S-007, FR-S-008).
- **§3 — `parse-token-usage.sh` CLI contract** (FR-S-013).
- **§4 — `render-research-report.sh` CLI contract** (Decision 2).
- **§5 — Corpus directory shape** (FR-S-002).
- **§6 — Performance budgets** (NFR-S-006, NFR-S-001 — bands recalibrated post-baseline).
- **§7 — `kiln:kiln-research` SKILL contract** (FR-S-007 + OQ-S-3).
- **§8 — Report markdown shape** (FR-S-004, NFR-S-005).

### Quickstart

The `README-research-runner.md` (FR-S-010) IS the quickstart. No separate `quickstart.md`. Path: `plugin-wheel/scripts/harness/README-research-runner.md`.

### Agent context update

No update needed. The "Active Technologies" block in CLAUDE.md is auto-trimmed to the last 5 feature branches per the rubric. This PRD's tech stack inherits from existing branches (`wheel-test-runner-extraction`, `wheel-as-runtime`) — no net-new runtime dependency to record. The `update-agent-context.sh` invocation is a no-op for this PRD.

## Phase 2 — Tasks (handled by `/tasks`, NOT this command)

Outline of what `/tasks` will produce (informational — not the actual task list):

### Phase A — Helpers + Contracts (no orchestration yet)

1. Author `parse-token-usage.sh` (≤ 80 LoC) per `contracts/interfaces.md §3`. Test against synthetic transcripts.
2. Author `render-research-report.sh` (≤ 100 LoC) per `contracts/interfaces.md §4`. Test against synthetic per-fixture result JSON.
3. Author `parse-token-usage.sh` test fixture at `plugin-kiln/tests/research-runner-missing-usage/run.sh` (SC-S-007 anchor).

### Phase B — Runner orchestration

4. Author `research-runner.sh` (≤ 150 LoC) per `contracts/interfaces.md §2`. Drive helpers + arms.
5. Author `kiln-research/SKILL.md` (~40 LoC) per `contracts/interfaces.md §7`.
6. Author `research-runner-pass-path/run.sh` test (SC-S-003).
7. Author `research-runner-regression-detect/run.sh` test (SC-S-002).
8. Author `research-runner-determinism/run.sh` test (SC-S-006).

### Phase C — Seed corpus + docs + back-compat audit

9. Author 3 seed-corpus fixtures under `plugin-kiln/fixtures/research-first-seed/corpus/` per FR-S-009.
10. Author `README-research-runner.md` (≤ 200 LoC) per FR-S-010 + NFR-S-009.
11. Author `research-runner-back-compat/run.sh` test (SC-S-004 — invokes `wheel-test-runner.sh` against the 3 named fixtures pre-PRD vs post-PRD; uses snapshot-diff comparator from `wheel-test-runner-extraction §3`).
12. Run end-to-end smoke against seed corpus to verify SC-S-001 wall-clock budget (recalibrated post-baseline). Capture observation in `agent-notes/impl-runner.md`.

### Phase D — Smoke + audit

13. PRD audit — verifies every PRD FR/NFR/SC has a spec FR/NFR/SC + implementation + test (audit-compliance teammate).
14. Smoke audit — runtime invocation of seed corpus + verifies report shape (audit-smoke teammate).

## Tooling Decisions (Bash discipline)

- All shell scripts: `set -euo pipefail` at top, `harness_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)` for sibling resolution. Mirrors `wheel-test-runner.sh` precedent.
- Logging: stderr for diagnostics, stdout reserved for TAP + report-uuid. Never mix.
- Error handling: `bail_out()` helper emits `Bail out! <msg>` + exit 2 (NFR-S-008 anchor for parse errors).
- Tempfile cleanup: `trap 'rm -f $tmpfiles' EXIT` for any tmpfile work.
- JSON shaping: `jq` for parse + emit (no `python3` for stream-json fields — `jq` handles all stream-json shape ops). `python3` reserved for fallback/debug.
- Determinism: `LC_ALL=C` + `sort -z` for any iteration over directories.

## Risk Tracking

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Stream-json `usage` shape change post-PRD | Low | High | NFR-S-008 loud-failure surface; SC-S-007 test fixture is the tripwire. |
| `bashcov` unavailable in CI | Medium | Medium | Fixture-suite-as-coverage-proof precedent (NFR-S-010 fallback). |
| Reconciled SC-S-001 budget > 90s on slow CI runners | Medium | Low | Auditor surfaces as separate optimization PRD; v1 ships with the recalibrated band. |
| 1-fixture corpus accepted (R-S-4) producing meaningless verdict | Medium | Low | Documented in spec Assumption A-2 + README; step 2 owns `min_fixtures`. |
| Concurrent invocations colliding on `/tmp/kiln-test-<uuid>/` | Vanishingly low | Low | UUIDv4 + `mkdir -p` discipline (NFR-S-007). |
| Backward compat regression detected by SC-S-004 | Low | High (ship-blocking) | NFR-S-002 forbids touching wheel-test-runner.sh; SC-S-004 fixture is the gate. |

## Open Questions

- **Recalibrated SC-S-001 budget**: pending `research.md §baseline`. If observation > 90s, escalate as separate optimization PRD vs widening this PRD's scope.
- **Where does `bashcov` live in the CI workflow?**: implementer resolves during Phase A if `bashcov` is added; otherwise NFR-S-010 falls back to fixture-as-proof per Decision 5.

## Complexity Tracking

> No constitutional violations. Section unused.

## Re-evaluate Constitution Check (Post-Design)

Post-Phase-1 design re-check: all 8 articles still pass. NFR-S-002 (no fork) is the most likely violation source; the "Decision 1 + Decision 2" split (token parser + renderer as separate helpers) is justified by the orchestrator's 150-LoC ceiling + Article VI's 500-line file limit. Both helpers are ≤ 100 LoC. Plan stands.
