# Tasks: Wheel Test Runner Extraction

**Branch**: `build/wheel-test-runner-extraction-20260425`
**Spec**: `specs/wheel-test-runner-extraction/spec.md`
**Plan**: `specs/wheel-test-runner-extraction/plan.md`
**Contracts**: `specs/wheel-test-runner-extraction/contracts/interfaces.md`

Atomic shipment per NFR-R-4 — Phase 1–9 are ONE squash-merge PR. Phase 9 (docs) is in the same PR.

Implementer MUST mark each task `[X]` IMMEDIATELY after completing it (Article VIII). Hooks block raw `plugin-wheel/` / `plugin-kiln/` edits until at least one `[X]` exists.

Implementer MUST author the friction note `agent-notes/implementer.md` per FR-009 and cite verdict-report paths for every test invocation.

---

## Phase 1 — Preflight: grep audit (R-R-1 mitigation)

- [X] **T001** Run the grep audit per `plan.md §Phase 1`:
  ```bash
  git grep -nF 'plugin-kiln/' plugin-kiln/scripts/harness/
  ```
  Document each match in `agent-notes/implementer.md` under "Preflight audit." Classify each as: (a) acceptable (e.g., `plugin-kiln/tests` placeholder pattern in `config-load.sh`), (b) needs migration (literal `plugin-kiln/` path), or (c) anomaly. If any (b) appears, RESOLVE it before Phase 2 by migrating to `${BASH_SOURCE[0]}`-relative, caller-passed arg, or plugin-name parameterization. FRs: R-R-1 mitigation.

- [X] **T002** Capture pre-PRD baselines for the implementer-chosen 3rd fixture (the fast-deterministic plugin-skill fixture per `contracts/interfaces.md §3`). If no suitable existing fixture, author a minimal synthetic one as part of this PRD's deliverables and capture its baseline before Phase 2. Store at `specs/wheel-test-runner-extraction/research/baseline-snapshot/<fixture-name>-pre-prd.md`. (The baselines for fixtures #1 and #2 — `preprocess-substitution.bats`, `kiln-distill-basic` — are already captured by researcher-baseline.) FR: SC-R-1 third fixture.

## Phase 2 — Move runner core (FR-R1)

- [X] **T010** Create the destination directory:
  ```bash
  mkdir -p plugin-wheel/scripts/harness
  ```
  FR: FR-R1-1 prep.

- [X] **T011** Move + rename the entrypoint:
  ```bash
  git mv plugin-kiln/scripts/harness/kiln-test.sh plugin-wheel/scripts/harness/wheel-test-runner.sh
  ```
  FR: FR-R1-1.

- [X] **T012** [P] Move all 11 sibling internal helpers in one batch (each is independent of the others — pure file relocation):
  ```bash
  git mv plugin-kiln/scripts/harness/watcher-runner.sh plugin-wheel/scripts/harness/
  git mv plugin-kiln/scripts/harness/dispatch-substrate.sh plugin-wheel/scripts/harness/
  git mv plugin-kiln/scripts/harness/substrate-plugin-skill.sh plugin-wheel/scripts/harness/
  git mv plugin-kiln/scripts/harness/tap-emit.sh plugin-wheel/scripts/harness/
  git mv plugin-kiln/scripts/harness/test-yaml-validate.sh plugin-wheel/scripts/harness/
  git mv plugin-kiln/scripts/harness/scratch-create.sh plugin-wheel/scripts/harness/
  git mv plugin-kiln/scripts/harness/scratch-snapshot.sh plugin-wheel/scripts/harness/
  git mv plugin-kiln/scripts/harness/fixture-seeder.sh plugin-wheel/scripts/harness/
  git mv plugin-kiln/scripts/harness/claude-invoke.sh plugin-wheel/scripts/harness/
  git mv plugin-kiln/scripts/harness/config-load.sh plugin-wheel/scripts/harness/
  git mv plugin-kiln/scripts/harness/watcher-poll.sh plugin-wheel/scripts/harness/
  ```
  Verify the source dir is empty + remove it:
  ```bash
  test -z "$(ls plugin-kiln/scripts/harness/ 2>/dev/null)" && rmdir plugin-kiln/scripts/harness/ 2>/dev/null || true
  ```
  FR: FR-R1-2.

- [X] **T013** Smoke-check inter-helper resolution:
  ```bash
  bash plugin-wheel/scripts/harness/wheel-test-runner.sh plugin-kiln kiln-distill-basic
  ```
  Expected: starts a real test run (may take time / cost — kill after ~5 sec once you confirm the harness initialization succeeded; we're verifying `harness_dir`-relative sibling resolution, not running the full test). If sibling lookup fails (e.g., "no such file or directory: <some helper>"), bisect which helper has a broken cross-reference. None expected per `contracts/interfaces.md §5`. FR: FR-R1-1, FR-R1-2.

## Phase 3 — Façade update (FR-R2)

- [X] **T020** Edit `plugin-kiln/skills/kiln-test/SKILL.md` line 31 (the bash invocation) per `contracts/interfaces.md §2`:
  - From: `bash "${WORKFLOW_PLUGIN_DIR}/scripts/harness/kiln-test.sh" $ARGUMENTS`
  - To:   `bash "${WORKFLOW_PLUGIN_DIR}/../plugin-wheel/scripts/harness/wheel-test-runner.sh" $ARGUMENTS`
  FR: FR-R2-1.

- [X] **T021** Edit `plugin-kiln/skills/kiln-test/SKILL.md` line 10 (the preamble non-negotiable sentence) per `contracts/interfaces.md §2`. Replace the path inside the backticks; rewrite the rest of the sentence to mention sibling-traversal per OQ-R-1. FR: FR-R2-1.

- [X] **T022** Diff-check the SKILL.md edit is minimal:
  ```bash
  git diff plugin-kiln/skills/kiln-test/SKILL.md | grep -E '^[+-]' | grep -v '^+++\|^---'
  ```
  Expected: ≤ 4 changed lines (2 line-31 changes + 2 line-10 changes). If more lines diff, REVERT and re-do — FR-R2-2 says skill prose UNCHANGED beyond these two. FR: FR-R2-2.

## Phase 4 — Cross-repo grep gate (FR-R2-3 / SC-R-3)

- [X] **T030** Run the grep audit per `plan.md §Phase 4`:
  ```bash
  git grep -nF 'plugin-kiln/scripts/harness/kiln-test' \
    ':(exclude).wheel/history/**' \
    ':(exclude)specs/**/blockers.md' \
    ':(exclude)specs/**/retro.md' \
    ':(exclude)docs/features/**/PRD.md' \
    ':(exclude)CLAUDE.md'
  ```
  Document every remaining match in `agent-notes/implementer.md` under "Cross-repo grep audit." Each match represents a live-code reference that needs migration.

- [X] **T031** For each match found in T030, edit the file to point at `plugin-wheel/scripts/harness/wheel-test-runner.sh` (or the resolution-disciplined variant if inside a SKILL.md / hook / workflow). FR: FR-R2-3.

- [X] **T032** Re-run the grep from T030 — expected output: empty. If non-empty, repeat T031. FR: SC-R-3.

## Phase 5 — Non-kiln consumability fixture (FR-R3)

- [X] **T040** Author `plugin-wheel/tests/wheel-test-runner-direct/run.sh` per `contracts/interfaces.md §6`. Tier-2 run.sh-only pattern. MUST include all 5 required assertions: (1) Form A auto-detect, (2) Form B `<plugin>`, (3) Form C `<plugin> <test>`, (4) `KILN_TEST_REPO_ROOT` honored, (5) `Bail out!` on bad input. FR: FR-R3-1.

- [X] **T041** Verify FR-R3-2 invariant on the new fixture:
  ```bash
  git grep -nF 'plugin-kiln/scripts/' plugin-wheel/tests/wheel-test-runner-direct/run.sh
  ```
  Expected: zero matches (the fixture MAY reference `plugin-kiln/tests/...` as input data per the §6 caveat, but NOT `plugin-kiln/scripts/`). FR: FR-R3-2.

- [X] **T042** Add the mutation-tripwire comment block to `run.sh` per `contracts/interfaces.md §6` "Mutation tripwire." Documents how a deliberate mutation to the runner would surface as a test failure. NFR: NFR-R-2.

- [X] **T043** Invoke the fixture and cite the result in `agent-notes/implementer.md`:
  ```bash
  bash plugin-wheel/tests/wheel-test-runner-direct/run.sh
  ```
  Expected: exit 0, last line `PASS: wheel-test-runner-direct (N/N assertions passed)`. NFR: NFR-R-1.

## Phase 6 — Snapshot-diff comparator (NFR-R-8)

- [X] **T050** Author `plugin-wheel/scripts/harness/snapshot-diff.sh` per `contracts/interfaces.md §3`. Three modes: `bats`, `verdict-report`, `verdict-report-deterministic`. Use the reference implementation outline in §3 as a starting point. NFR: NFR-R-8.

- [X] **T051** Smoke-test the comparator against the captured baselines (sanity check before using it in Phase 7):
  ```bash
  bash plugin-wheel/scripts/harness/snapshot-diff.sh \
    bats \
    specs/wheel-test-runner-extraction/research/baseline-snapshot/preprocess-substitution.bats-pre-prd.md \
    specs/wheel-test-runner-extraction/research/baseline-snapshot/preprocess-substitution.bats-pre-prd.md
  ```
  Expected: exit 0 (file diffed against itself = no diff). NFR: NFR-R-8.

## Phase 7 — Snapshot-diff verification (FR-R4 / SC-R-1)

- [X] **T060** Run `bats plugin-wheel/tests/preprocess-substitution.bats` post-PRD; save TAP output to `/tmp/preprocess-post.md`. Run snapshot-diff:
  ```bash
  bash plugin-wheel/scripts/harness/snapshot-diff.sh \
    bats \
    specs/wheel-test-runner-extraction/research/baseline-snapshot/preprocess-substitution.bats-pre-prd.md \
    /tmp/preprocess-post.md
  ```
  Expected: exit 0. Cite `/tmp/preprocess-post.md` path in `agent-notes/implementer.md`. FR: FR-R4-1, FR-R4-2.

- [X] **T061** Run `bash plugin-wheel/scripts/harness/wheel-test-runner.sh plugin-kiln kiln-distill-basic` post-PRD; locate verdict report:
  ```bash
  ls -t .kiln/logs/kiln-test-*.md | head -1
  ```
  Save its path to a variable. Run snapshot-diff:
  ```bash
  bash plugin-wheel/scripts/harness/snapshot-diff.sh \
    verdict-report \
    specs/wheel-test-runner-extraction/research/baseline-snapshot/kiln-distill-basic-pre-prd.md \
    "<path-from-ls>"
  ```
  Expected: exit 0 (the framing diffs — body excluded section-level). Cite the post-PRD verdict-report path in `agent-notes/implementer.md`. FR: FR-R4-1.

- [X] **T062** Run the implementer-chosen 3rd fixture (per T002) post-PRD; capture verdict report; run snapshot-diff in `verdict-report-deterministic` mode. Expected: exit 0. Cite the post-PRD verdict-report path in `agent-notes/implementer.md`. FR: FR-R4-1, SC-R-1.

## Phase 8 — Live-smoke gate (NFR-R-5 / SC-R-2)

- [X] **T070** Run the canonical live-smoke substrate end-to-end (~3 min wall-clock; consumes ~$0.12 LLM budget):
  ```bash
  bash plugin-kiln/tests/perf-kiln-report-issue/run.sh
  ```
  Capture `/tmp/perf-results.tsv` and `/tmp/perf-medians.json`. Cite both paths in `agent-notes/implementer.md` AND in the PR description verification checklist.

- [X] **T071** Verify post-PRD `after_arm_medians` against tolerance bands per `spec.md §SC-R-2`:
  - `wall_clock_sec` within ±20% of 7.751s (range 6.20s–9.30s)
  - `duration_api_ms` within ±20% of 4364ms (range 3491ms–5237ms)
  - `num_turns` exactly 2
  - `output_tokens` within ±10% of 180 (range 162–198) — advisory
  Document the post-PRD medians + delta-from-baseline in `agent-notes/implementer.md`. NFR: NFR-R-5, SC-R-2.

- [X] **T072** [Informational, not gating] Measure façade overhead per NFR-R-6:
  ```bash
  # Pre-PRD (would need a checkout of the previous commit; skip if not feasible — measure post-PRD only):
  time bash plugin-wheel/scripts/harness/wheel-test-runner.sh plugin-kiln <fast-deterministic-fixture>
  ```
  Document the measured wall-clock + delta-vs-pre-PRD in `agent-notes/implementer.md`. If pre-PRD measurement is not feasible from the current branch, note that and cite ≤50ms as theoretical (script-invocation overhead). NFR: NFR-R-6, SC-R-5.

## Phase 9 — Documentation (in same PR per NFR-R-4)

- [X] **T080** Author `plugin-wheel/docs/test-runner.md` per `plan.md §Phase 9`. Worked example: invoking `wheel-test-runner.sh` from a hypothetical `plugin-foo` consumer; sample test.yaml + assertions.sh + verdict-report excerpt. SC: SC-R-6.

- [X] **T081** Append a "Test Runner" section to `plugin-wheel/README.md` linking to the new doc + a one-paragraph summary. SC: SC-R-6.

- [X] **T082** Update CLAUDE.md "Recent Changes" block — handled by `/kiln:kiln-build-prd` retrospective phase, NOT implementer. (Confirmed: implementer not responsible.)

## Verification gates (auditor-checked, per NFR-R-1 / NFR-R-3 / NFR-R-4 / NFR-R-5)

- [ ] **G1** All 12 `git mv` operations + entrypoint rename present in the squash-merge PR diff (NFR-R-4 atomic shipment).
- [ ] **G2** `plugin-kiln/skills/kiln-test/SKILL.md` updated; diff is exactly the 2 documented edits (≤ 4 changed lines including line-10 and line-31). FR-R2-2.
- [ ] **G3** SC-R-3 grep gate clean: `git grep -nF 'plugin-kiln/scripts/harness/kiln-test'` with documented exclusions returns empty.
- [ ] **G4** SC-R-1 satisfied — snapshot-diff via `snapshot-diff.sh` is exit 0 for all three named fixtures.
- [ ] **G5** SC-R-2 satisfied — live-smoke run's `after_arm_medians` within tolerance bands; medians-JSON path cited in PR description.
- [ ] **G6** SC-R-4 satisfied — `wheel-test-runner-direct/run.sh` exit 0, last-line PASS summary cited in friction note.
- [ ] **G7** Mutation tripwire documented in `wheel-test-runner-direct/run.sh` (NFR-R-2).
- [ ] **G8** Friction note `agent-notes/implementer.md` exists and cites:
  - Preflight grep audit results (T001)
  - Post-PRD verdict-report paths for all 3 SC-R-1 fixtures (T060, T061, T062)
  - `wheel-test-runner-direct/run.sh` PASS summary (T043)
  - `/tmp/perf-medians.json` path + post-PRD medians (T070, T071)
  - Façade overhead measurement (T072)
- [ ] **G9** NFR-R-7 verified — `git grep` shows preserved env-var name `KILN_TEST_REPO_ROOT`, scratch prefix `/tmp/kiln-test-`, log-path prefix `.kiln/logs/kiln-test-`, skill name `/kiln:kiln-test`.
- [ ] **G10** Atomic shipment — Phases 1–9 land in ONE squash-merge PR (NFR-R-4). No half-state allowed.

## Parallelism notes

- **T001 / T002** are independent (preflight reads + baseline capture). Can run in parallel.
- **T011 / T012** are sequential within Phase 2 (T011 must complete before T013's smoke check; T012 is multi-file `git mv` batched as one logical step but each `mv` is atomic).
- **T020 / T021** are sequential edits to the same SKILL.md file but are independent semantically — order doesn't matter; group as one edit.
- **T030 / T031 / T032** are sequential (audit → fix → re-audit).
- **T040 / T041 / T042 / T043** are sequential (author → grep-check → tripwire → invoke).
- **T050 / T051** are sequential (author → smoke-test).
- **T060 / T061 / T062** are independent of each other ([P] across the 3 fixtures) but all depend on Phase 6 (`snapshot-diff.sh`) being complete.
- **T070 / T071** are sequential (run → verify medians).
- **T080 / T081** are independent ([P]) — different files.

## Out of scope (explicitly NOT this PRD)

- `harness-type: shell-test` substrate extension — roadmap item #2.
- Renaming the skill `/kiln:kiln-test` → `/wheel:wheel-test-runner` — explicitly NOT in this PRD per spec NFR-R-7.
- Renaming verdict-report path / scratch-dir prefix / `KILN_TEST_REPO_ROOT` env var — explicitly NOT in this PRD per NFR-R-7.
- Fixing the pre-existing NFR-F-6 resolver-overhead regression — separate follow-on issue per researcher reconciliation directive #4.
- Moving `plugin-kiln/tests/` fixtures — explicitly NOT in this PRD per spec §Non-Goals (fixtures stay; only the engine moves).
