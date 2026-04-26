---
description: "Task list for research-first-foundation"
---

# Tasks: Research-First Foundation — Fixture Corpus + Baseline-vs-Candidate Runner MVP

**Input**: `specs/research-first-foundation/`
**Prerequisites**: spec.md ✅, plan.md ✅, contracts/interfaces.md ✅, research.md §baseline ✅
**Branch**: `build/research-first-foundation-20260425`

**Tests**: REQUIRED. The constitution mandates ≥80% coverage (Article II) and E2E tests (Article V). Five test fixtures are pre-specified in `contracts/interfaces.md §9` (anchored to SC-S-002..SC-S-007).

**Organization**: Tasks are grouped by user story (US1..US5 from spec.md), preceded by a foundational phase for the helpers + corpus + skill scaffolding.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files, no dependencies on incomplete tasks)
- **[Story]**: maps to spec.md user story (US1=happy path, US2=regression detect, US3=back-compat, US4=PRD frontmatter, US5=docs)
- Every task includes exact file paths

## Path Conventions

Single-project, extending existing CLI substrate. Net-new files only — NFR-S-002 forbids modifying existing harness scripts. Path tree:

- Runner + helpers: `plugin-wheel/scripts/harness/`
- Skill wrapper: `plugin-kiln/skills/kiln-research/`
- Seed corpus: `plugin-kiln/fixtures/research-first-seed/corpus/`
- Test fixtures: `plugin-kiln/tests/research-runner-*/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the directory tree for net-new artifacts. No code yet.

- [X] T001 Create directory `plugin-kiln/skills/kiln-research/` (skill wrapper home)
- [X] T002 [P] Create directory `plugin-kiln/fixtures/research-first-seed/corpus/` (seed corpus home)
- [X] T003 [P] Create directory `plugin-kiln/tests/` subdirs for all 5 test fixtures: `research-runner-pass-path/`, `research-runner-regression-detect/`, `research-runner-determinism/`, `research-runner-missing-usage/`, `research-runner-back-compat/`
- [X] T004 [P] Verify NFR-S-002 invariant on baseline — `git diff main...HEAD --name-only -- plugin-wheel/scripts/harness/ plugin-kiln/skills/kiln-test/SKILL.md` returns empty. Snapshot baseline contents of the 13 files in `contracts/interfaces.md §10` for end-of-PR diff-zero check.

**Checkpoint**: Directory tree ready. Foundational work begins.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Author the helpers + contracts that every user story depends on. NO user-story work begins until this phase is complete.

⚠️ **CRITICAL**: T005..T010 are blockers for US1..US5. Phase 2 commits before Phase 3.

- [X] T005 [P] Implement `plugin-wheel/scripts/harness/parse-token-usage.sh` per `contracts/interfaces.md §3` (FR-S-013, NFR-S-008). Inputs: transcript NDJSON path. Outputs: whitespace-delimited `<input> <output> <cached_creation> <cached_read> <total>` on stdout. Exits 0 on success, 2 with documented `parse error: usage record missing` diagnostic on missing/null `usage`. Use `jq` for envelope parse — find LAST `result`-typed envelope, read `.message.usage` (or equivalent — verified empirically against current Claude Code stream-json shape). Set `set -euo pipefail`.
- [X] T006 [P] Implement `plugin-wheel/scripts/harness/render-research-report.sh` per `contracts/interfaces.md §4` + `§8`. Inputs: `<report-path>` arg + NDJSON stdin. Outputs: markdown file at report-path. Exits 0/2. Layout matches §8 exactly — table columns `Fixture | Baseline Acc | Candidate Acc | Baseline Tokens | Candidate Tokens | Δ Tokens | Verdict`, 5-line aggregate, optional Diagnostics section on FAIL. ≤ 100 LoC. Determinism: byte-identical input → byte-identical output (timestamps treated as modulo per §8 final paragraph).
- [X] T007 [US-foundation] Add `plugin-kiln/tests/research-runner-missing-usage/run.sh` (chmod +x) — synthetic transcript with stripped `usage` envelope, asserts T005 exits 2 + emits documented diagnostic. SC-S-007 anchor. The test does NOT need `claude` CLI — it operates on a static transcript fixture under `plugin-kiln/tests/research-runner-missing-usage/fixtures/`.
- [X] T008 [US-foundation] Add `plugin-kiln/tests/research-runner-missing-usage/fixtures/transcript.ndjson` — minimal valid stream-json transcript with the `result.message.usage` field stripped. T007 consumes this.
- [X] T009 Implement `plugin-wheel/scripts/harness/research-runner.sh` per `contracts/interfaces.md §2`. ≤ 150 LoC. Required flags `--baseline`, `--candidate`, `--corpus`; optional `--report-path`. Discovery via `find … | sort -z` (matches `wheel-test-runner.sh` ln 143 precedent). Per-fixture: shells out twice (baseline arm + candidate arm) using existing `claude-invoke.sh` + `scratch-create.sh` + `watcher-runner.sh` as subprocesses (NEVER source/modify them — NFR-S-002). Computes per-fixture verdict per FR-S-005 strict-gate logic: `regression (accuracy)` if baseline-pass + candidate-fail, `regression (tokens)` if `delta_total > 10` (NFR-S-001 reconciled band tolerance), `regression (accuracy + tokens)` if both, `inconclusive` for missing files / stalled / parse error. Emits TAP v14 stdout (one line per arm per fixture) + per-fixture NDJSON shape per §1 piped into `render-research-report.sh`. Exit codes 0/1/2 per §2.
- [X] T010 Implement `plugin-kiln/skills/kiln-research/SKILL.md` per `contracts/interfaces.md §7`. ≤ 50 LoC. Frontmatter `name: kiln-research` + description. Body: 1-line purpose, invocation forms, dual-layout sibling resolution (matches `kiln:kiln-test` SKILL.md ln 33-40), exit-code legend, README pointer.

**Checkpoint**: helpers + runner + skill landed. Commit Phase 2 before starting US1.

---

## Phase 3: User Story 1 — Happy path: 3-fixture corpus produces PASS verdict (Priority: P1 — HARD GATE) 🎯 MVP

**Goal**: A maintainer constructs a 3-fixture corpus, runs `research-runner.sh --baseline --candidate --corpus`, gets `.kiln/logs/research-<uuid>.md` with `Overall: PASS`, exit 0, runtime ≤ 240 s.

**Independent Test**: SC-S-001 + SC-S-003 — symlink-copied baseline=candidate produces `Overall: PASS` aggregate, 3 per-fixture rows, exit 0, wall-clock ≤ 240 s.

### Implementation for User Story 1

- [X] T011 [P] [US1] Author seed corpus fixture #1 at `plugin-kiln/fixtures/research-first-seed/corpus/001-noop-passthrough/`: `input.json` (single user envelope invoking `kiln:kiln-version` — the lightest-possible probe per research.md §SC-001 anchor 1), `expected.json` (assertion_kind: "exit-code", expected_exit_code: 0), `metadata.yaml` (axes: [accuracy, tokens]; why: "anchors runner plumbing on near-no-op fixture").
- [X] T012 [P] [US1] Author seed corpus fixture #2 at `plugin-kiln/fixtures/research-first-seed/corpus/002-token-floor/`: same shape; verifies token-count parsing on a minimal envelope. Use a low-cost probe (e.g. another version-style skill). `metadata.yaml` why: "verifies token parsing on minimal envelope per FR-S-013".
- [X] T013 [P] [US1] Author seed corpus fixture #3 at `plugin-kiln/fixtures/research-first-seed/corpus/003-assertion-anchor/`: same shape; assertion designed to exercise the assertion-pass path. `metadata.yaml` why: "exercises assertion-pass path so the runner's accuracy-axis logic is reached for all 3 fixtures".
- [X] T014 [US1] Implement `plugin-kiln/tests/research-runner-pass-path/run.sh` (chmod +x). Constructs symlink-copied baseline=candidate plugin-dirs (`baseline -> $PWD/plugin-kiln`, `candidate -> $PWD/plugin-kiln`), invokes `bash plugin-wheel/scripts/harness/research-runner.sh --baseline … --candidate … --corpus plugin-kiln/fixtures/research-first-seed/corpus/`, asserts: (a) exit 0, (b) `.kiln/logs/research-*.md` exists, (c) report contains `Overall: PASS`, (d) report contains 3 per-fixture rows, (e) wall-clock ≤ 240 s. SC-S-001 + SC-S-003 anchor. Final stdout line: `PASS` or `FAIL`.
- [X] T015 [US1] Add `.gitignore` line for `.kiln/logs/research-*.md` (if not already covered by `.kiln/logs/` pattern — verify via `git check-ignore -v .kiln/logs/research-test.md`). NFR-S-004 anchor.

**Checkpoint**: US1 fully testable. Commit Phase 3.

---

## Phase 4: User Story 2 — Regressing candidate produces FAIL verdict naming the slug (Priority: P1 — HARD GATE)

**Goal**: A deliberately-regressing candidate produces `Overall: FAIL`, exit 1, with the regressing fixture's slug named in the per-fixture row.

**Independent Test**: SC-S-002 — engineered token-regressing fixture causes `Overall: FAIL` + exit 1 + slug visible in row.

### Implementation for User Story 2

- [X] T016 [P] [US2] Author `plugin-kiln/tests/research-runner-regression-detect/fixtures/baseline-plugin/` and `…/candidate-plugin/` — two minimal plugin-dirs where the candidate is engineered to produce strictly more output tokens for at least one fixture. The simplest engineering: candidate's skill prose includes a verbose-mode flag that the baseline does not (e.g. an extra `<!-- @include ... -->` directive bumping output by ≥ 11 tokens, comfortably above NFR-S-001's ±10 band). Document the engineering in a `README.md` next to the fixtures.
- [X] T017 [P] [US2] Author `plugin-kiln/tests/research-runner-regression-detect/fixtures/corpus/001-token-regression/` — single-fixture corpus exercising the engineered diff.
- [X] T018 [US2] Implement `plugin-kiln/tests/research-runner-regression-detect/run.sh` (chmod +x). Invokes the runner against the engineered baseline + candidate + corpus from T016/T017. Asserts: (a) exit 1, (b) report contains `Overall: FAIL`, (c) per-fixture row for `001-token-regression` shows verdict `regression (tokens)` and references the slug by name, (d) aggregate summary names the regressing slug. SC-S-002 anchor.

**Checkpoint**: US2 fully testable. Commit Phase 4.

---

## Phase 5: User Story 3 — Backward-compat: existing `/kiln:kiln-test` byte-identical (Priority: P1 — HARD GATE)

**Goal**: Existing `/kiln:kiln-test` invocations produce byte-identical TAP + verdict reports vs main, modulo timestamps/UUIDs/scratch paths.

**Independent Test**: SC-S-004 — diff-zero against the `wheel-test-runner-extraction §3` per-fixture exclusion comparator on three named fixtures.

### Implementation for User Story 3

- [X] T019 [US3] Implement `plugin-kiln/tests/research-runner-back-compat/run.sh` (chmod +x). Captures `bash plugin-wheel/scripts/harness/wheel-test-runner.sh kiln <fixture>` stdout + verdict-report content for three fixtures: `kiln-distill-basic`, `kiln-hygiene-backfill-idempotent`, plus one fast-deterministic plugin-skill fixture (caller picks; e.g. `structured-roadmap-shelf-mirror-paths`). Compares against pre-PRD baseline captured in T020. Uses `plugin-wheel/scripts/harness/snapshot-diff.sh` (NFR-S-002 — invoked, not modified) with the per-fixture exclusion contract from `wheel-test-runner-extraction/contracts/interfaces.md §3`. Asserts diff = 0 lines beyond modulo-list. Final stdout: `PASS` or `FAIL`.
- [X] T020 [US3] Capture pre-PRD baseline outputs for the 3 named fixtures (T019). Either: (a) commit baseline TAP + verdict reports to `plugin-kiln/tests/research-runner-back-compat/baselines/` (preferred — reviewable, deterministic), OR (b) `git stash` net-new files, run the substrate, capture, restore. Method (a) is canonical. Asserts NFR-S-002 file allowlist: `git diff main...HEAD --name-only -- plugin-wheel/scripts/harness/ plugin-kiln/skills/kiln-test/SKILL.md` returns empty.
- [X] T021 [US3] Add a verbatim NFR-S-002 file-allowlist regression assertion to T019: scripted check that the 13 files in `contracts/interfaces.md §10` are byte-untouched by this PR's diff (`git diff main...HEAD --shortstat -- <file>` returns empty for each). Run inline at the top of T019's run.sh.

**Checkpoint**: US3 fully testable. Commit Phase 5.

---

## Phase 6: User Story 4 — PRD frontmatter `fixture_corpus:` convention documented (Priority: P2)

**Goal**: README documents the `fixture_corpus:` PRD-frontmatter convention as forward-compat handle for step 6 wiring.

**Independent Test**: `git grep -nF 'fixture_corpus:' plugin-wheel/scripts/harness/README-research-runner.md` returns ≥ 1 match.

### Implementation for User Story 4

- [X] T022 [US4] In `plugin-wheel/scripts/harness/README-research-runner.md` (created in T024 below), document the `fixture_corpus:` PRD-frontmatter convention in a "Forward-compat" section. Includes example PRD frontmatter snippet + note that v1 runner does NOT consume it (step 6 will). FR-S-006 + FR-S-010 anchors.

**Checkpoint**: US4 documented. Commit Phase 6 with US5.

---

## Phase 7: User Story 5 — One-page README documents the substrate (Priority: P2)

**Goal**: A reviewer who has never used the runner reads the README and successfully constructs a corpus + invokes the runner.

**Independent Test**: SC-S-005 — informal reviewer-walkthrough; README is ≤ 200 lines (NFR-S-009).

### Implementation for User Story 5

- [X] T023 [P] [US5] Author `plugin-wheel/scripts/harness/README-research-runner.md` (≤ 200 LoC) per FR-S-010 + NFR-S-009. Sections: (a) Quick Start (corpus dir shape + runner invocation + report path), (b) Worked example using the FR-S-009 seed corpus, (c) Report shape reference (link to `contracts/interfaces.md §8`), (d) Forward-compat note (T022 — the `fixture_corpus:` PRD frontmatter), (e) Pointer to `kiln:kiln-research` SKILL wrapper, (f) Exit-code legend.
- [X] T024 [P] [US5] Verify README line count is ≤ 200 lines via `wc -l plugin-wheel/scripts/harness/README-research-runner.md`. Add an inline assertion to T014 (research-runner-pass-path/run.sh) that the README exists and ≤ 200 lines, so the gate is testable in CI.

**Checkpoint**: US5 documented. Commit Phase 7.

---

## Phase 8: Determinism gate (cross-cutting — NFR-S-001 + SC-S-006)

**Goal**: Verify per-fixture token observations stay within ±10 tokens absolute per `usage` field across 3 reruns; run-level verdict stable.

**Independent Test**: SC-S-006 — 3 consecutive reruns produce 3 byte-identical reports (modulo §8 timestamp-modulo-list) AND token observations within ±10 per-field band.

### Implementation for Determinism

- [X] T025 [US-cross] Implement `plugin-kiln/tests/research-runner-determinism/run.sh` (chmod +x). Invokes the runner 3× consecutively against the seed corpus with baseline=candidate (symlink-copy). Asserts: (a) all 3 runs exit 0, (b) all 3 reports byte-identical modulo `Started`/`Completed`/`Wall-clock`/`Run UUID`/`Report UUID` per §8 modulo-list, (c) `parse-token-usage.sh`-derived per-field token deltas across runs are ≤ 10 (NFR-S-001 reconciled band — anchor `research.md §NFR-001 token-determinism` directive 2). Final stdout: `PASS` or `FAIL`.

**Checkpoint**: Determinism gate landed. Commit Phase 8.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final tightening + audit prep.

- [X] T026 [P] Re-run all 5 test fixtures (`bash plugin-kiln/tests/research-runner-pass-path/run.sh`, `…regression-detect/`, `…determinism/`, `…missing-usage/`, `…back-compat/`). All 5 MUST exit 0 + emit `PASS` final line. Capture run output in `agent-notes/impl-runner.md`.
- [X] T027 [P] Run end-to-end smoke against the seed corpus: `bash plugin-wheel/scripts/harness/research-runner.sh --baseline plugin-kiln --candidate plugin-kiln --corpus plugin-kiln/fixtures/research-first-seed/corpus/`. Capture exit code, wall-clock, report path. Wall-clock MUST be ≤ 240 s (SC-S-001 reconciled). Capture in `agent-notes/impl-runner.md`.
- [X] T028 [P] Verify NFR-S-002 file allowlist by running `git diff main...HEAD --name-only -- plugin-wheel/scripts/harness/wheel-test-runner.sh plugin-wheel/scripts/harness/claude-invoke.sh plugin-wheel/scripts/harness/config-load.sh plugin-wheel/scripts/harness/dispatch-substrate.sh plugin-wheel/scripts/harness/fixture-seeder.sh plugin-wheel/scripts/harness/scratch-create.sh plugin-wheel/scripts/harness/scratch-snapshot.sh plugin-wheel/scripts/harness/snapshot-diff.sh plugin-wheel/scripts/harness/substrate-plugin-skill.sh plugin-wheel/scripts/harness/tap-emit.sh plugin-wheel/scripts/harness/test-yaml-validate.sh plugin-wheel/scripts/harness/watcher-poll.sh plugin-wheel/scripts/harness/watcher-runner.sh plugin-kiln/skills/kiln-test/SKILL.md`. MUST return empty. Captured in `agent-notes/impl-runner.md`.
- [X] T029 [P] Verify CLAUDE.md `## Active Technologies` block does NOT need a new entry (this PRD inherits the wheel/kiln tech stack — no net-new runtime dependency per plan §Technical Context). If the auto-trim rubric removed an older entry to make room for this branch, the new entry SHOULD be a one-liner pointing at `plugin-wheel/scripts/harness/research-runner.sh` + `parse-token-usage.sh`. Otherwise no change.
- [X] T030 Run PRD audit (audit-compliance teammate territory — informational note here): every PRD FR/NFR/SC has a spec FR/NFR/SC + implementation + test. Cross-reference table:

  | PRD anchor | Spec anchor | Impl task | Test fixture |
  |---|---|---|---|
  | FR-001 (two `--plugin-dir`) | FR-S-001 | T009 | research-runner-pass-path |
  | FR-002 (corpus shape) | FR-S-002 | T011..T013 | (covered by US1 fixtures) |
  | FR-003 (per-arm metrics) | FR-S-003 | T005 (parser) + T009 (runner) | research-runner-determinism |
  | FR-004 (report shape) | FR-S-004 | T006 (renderer) + T009 (runner) | research-runner-pass-path |
  | FR-005 (strict gate) | FR-S-005 | T009 (verdict logic) | research-runner-regression-detect |
  | FR-006 (frontmatter convention) | FR-S-006 | T022 (docs only) | (informational) |
  | FR-007 (standalone CLI) | FR-S-007 | T009 + T010 (SKILL) | research-runner-pass-path |
  | NFR-001 (determinism ±10) | NFR-S-001 (RECONCILED) | T009 + T005 | research-runner-determinism |
  | NFR-002 (no fork) | NFR-S-002 | T020 + T021 + T028 | research-runner-back-compat |
  | NFR-003 (back-compat) | NFR-S-003 | T019 + T020 | research-runner-back-compat |
  | NFR-004 (report locality) | NFR-S-004 | T015 (.gitignore) | research-runner-pass-path (asserts path) |
  | NFR-005 (readability) | NFR-S-005 | T006 (renderer) | research-runner-pass-path (asserts row shape) |
  | SC-001 (≤240 s, RECONCILED) | SC-S-001 | T011..T014 + T027 | research-runner-pass-path |
  | SC-002 (regression detect) | SC-S-002 | T016..T018 | research-runner-regression-detect |
  | SC-003 (pass on no-diff) | SC-S-003 | T011..T014 | research-runner-pass-path |
  | SC-004 (back-compat) | SC-S-004 | T019..T021 | research-runner-back-compat |
  | SC-005 (one-page docs) | SC-S-005 | T023..T024 | (informal review) |

- [X] T031 Run smoke audit (audit-smoke teammate territory — informational note): runtime invocation of `bash plugin-wheel/scripts/harness/research-runner.sh --help` (or equivalent), seed-corpus end-to-end, verifies report shape matches §8 layout exactly.

**Final Checkpoint**: All FR/NFR/SC anchored. PR-ready.

---

## Dependencies

```text
Phase 1 (Setup) → Phase 2 (Foundational) → Phase 3..7 (US1..US5) → Phase 8 (Determinism) → Phase 9 (Polish)
                                          ↘ US3 + US4 + US5 ↗
                                          ↘ US2 ↗
                                          ↘ US1 (MVP) ↗

Within Phase 2: T005..T008 [P], then T009 (runner) blocks T010 (skill).
Within Phase 3 (US1): T011..T013 [P], then T014 + T015.
Within Phase 4 (US2): T016..T017 [P], then T018.
Within Phase 5 (US3): T020 captures baseline first, then T019 + T021.
Within Phase 6+7 (US4+US5): T022 + T023 + T024 [P].
Phase 8 (T025) blocks on Phase 2 + 3.
Phase 9 (T026..T031) blocks on all prior phases.
```

## Parallel Execution Examples

- Phase 1: T001..T004 all parallel (different dirs).
- Phase 2: T005 + T006 + T007 + T008 all parallel; T009 + T010 sequential after T005..T008.
- Phase 3 (US1): T011 + T012 + T013 parallel (different fixture dirs); T014 + T015 sequential.
- Phase 4 (US2): T016 + T017 parallel; T018 after.
- Phase 6+7 (US4+US5): T022 + T023 + T024 parallel.
- Phase 9: T026..T029 all parallel; T030 + T031 last.

## Implementation Strategy

**MVP scope = Phase 1 + Phase 2 + Phase 3 (US1)**. Once US1 passes, the maintainer has a working substrate. US2..US5 + Phase 8 + Phase 9 are incremental hardening — each commits independently.

**Constitutional gates** (Article II + V + VII + VIII):

- Article II (≥80% coverage): satisfied by 5 test fixtures × all net-new code paths. `bashcov` measurement is preferred but optional per plan §Decision 5.
- Article V (E2E required): all 5 test fixtures invoke `bash plugin-wheel/scripts/harness/research-runner.sh` directly with real or synthetic transcripts. None are unit-only.
- Article VII (Interface Contracts): every implementation task references a `contracts/interfaces.md` section.
- Article VIII (Incremental task completion): tasks marked `[X]` immediately after each completes; commits per phase, not batched.

**FR-S-002 reminder**: `metadata.yaml` is OPTIONAL but the seed-corpus fixtures (T011..T013) author it for human reviewer benefit + future-step alignment. The runner ignores it.

**NFR-S-002 reminder**: NEVER edit `wheel-test-runner.sh` or its 12 sibling helpers. T020 + T021 + T028 collectively gate this — if any of those tripwires fire, the implementer reverts the offending change rather than papering over it.

## Coverage gate

Per Article II ≥80% line coverage on net-new code paths. Net-new files:

- `plugin-wheel/scripts/harness/parse-token-usage.sh` (~80 LoC) — covered by T007 (missing-usage) + T009-driven runner invocations across US1..US5.
- `plugin-wheel/scripts/harness/render-research-report.sh` (~100 LoC) — covered by T014 + T018 + T019 + T025 (every test fixture invokes the runner which calls the renderer).
- `plugin-wheel/scripts/harness/research-runner.sh` (~150 LoC) — covered by all 5 test fixtures.
- `plugin-kiln/skills/kiln-research/SKILL.md` — coverage N/A for skill-prose files (precedent: `kiln:kiln-test` SKILL.md is similarly unmeasured).

If `bashcov` is unavailable in CI, the 5-fixture suite serves as the de-facto coverage proof per plan §Decision 5.
