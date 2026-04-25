# Feature Specification: Wheel Test Runner Extraction (`kiln-test` → `wheel-test-runner`)

**Feature Branch**: `build/wheel-test-runner-extraction-20260425`
**Created**: 2026-04-25
**Status**: Draft
**Input**: `docs/features/2026-04-25-wheel-test-runner-extraction/PRD.md`
**Parent goal**: `.kiln/roadmap/items/2026-04-23-wheel-as-plugin-agnostic-infra.md`
**Builds on**: PR #166 + PR #168 (typed inputs/outputs + schema locality) — independent of those changes but uses the same `perf-kiln-report-issue` substrate as their audit gates.
**Baseline research**: `specs/wheel-test-runner-extraction/research.md` (read first; thresholds in §Success Criteria are reconciled against it per §1.5 Baseline Checkpoint).

## Overview

The kiln test-harness substrate (`claude --print --plugin-dir <local>` subprocess + scratch-dir fixture + watcher classifier) is plugin-agnostic by construction but lives at `plugin-kiln/scripts/harness/kiln-test.sh`. This PRD relocates the runner core to `plugin-wheel/scripts/harness/wheel-test-runner.sh` and rewires `/kiln:kiln-test` SKILL.md as a thin façade. No user-facing behavior change. No new substrate types (the `harness-type: shell-test` extension is the next roadmap item, not this one).

Three changes in one squash-merge PR:

1. **Move** `kiln-test.sh` + sibling internal helpers (`watcher-runner.sh`, `dispatch-substrate.sh`, `substrate-plugin-skill.sh`, `tap-emit.sh`, `test-yaml-validate.sh`, `scratch-create.sh`, `scratch-snapshot.sh`, `fixture-seeder.sh`, `claude-invoke.sh`, `config-load.sh`, `watcher-poll.sh`) from `plugin-kiln/scripts/harness/` → `plugin-wheel/scripts/harness/`. The runner becomes self-contained — sources nothing from `plugin-kiln/`.
2. **Update** `/kiln:kiln-test` SKILL.md's `bash <path>` invocation to point at the wheel-side runner via `${WORKFLOW_PLUGIN_DIR}/../plugin-wheel/scripts/harness/wheel-test-runner.sh`. Skill prose stays in kiln verbatim.
3. **Add** a wheel-side fixture (`plugin-wheel/tests/wheel-test-runner-direct/run.sh`) that exercises `wheel-test-runner.sh` directly — proves non-kiln consumability.

## Resolution of PRD Open Questions

The PRD left three Open Questions for the spec phase. Resolved as follows; rationale in the corresponding theme.

- **OQ-R-1 (BLOCKING — script-resolution pattern)**: RESOLVED — option **(a) `${WORKFLOW_PLUGIN_DIR}/../plugin-wheel/scripts/harness/wheel-test-runner.sh`** (kiln-relative sibling path). Rationale: option (a) requires zero new wheel infrastructure, works in both source-repo and consumer-install layouts (Claude Code installs sibling plugins as siblings under `~/.claude/plugins/cache/<org>-<mp>/`), and matches the existing kiln-side resolution discipline. Options (b) and (c) introduce coupling — (b) requires every kiln-test consumer to `source` a wheel helper before invoking, (c) embeds find-in-cache fallbacks that fail loudly on layout drift. Validated by the consumer-install smoke pattern at `plugin-wheel/tests/workflow-plugin-dir-bg/run.sh` (PR #168) — the `${WORKFLOW_PLUGIN_DIR}/../<sibling>` shape already resolves correctly under `~/.claude/plugins/cache/<org>-<mp>/<plugin>/<version>/` install layouts. Encoded in **FR-R2-1**.
- **OQ-R-2 (filename — `wheel-test-runner.sh` vs `test-runner.sh`)**: RESOLVED — `wheel-test-runner.sh`. Rationale: descriptive prefix is unambiguous when grep-walking from any plugin's call sites, and aligns with the name convention used in roadmap items #2-#4 (e.g., `2026-04-25-shell-test-substrate.md` references `wheel-test-runner.sh` literally). Bare `test-runner.sh` invites collision when sibling plugins author their own runners. Encoded in **FR-R1-1**.
- **OQ-R-3 (verdict report path stays `.kiln/logs/kiln-test-*.md`)**: ACKNOWLEDGED. The `kiln-test-` prefix becomes a back-compat fossil — log paths are named after the historic skill, not the new runner location. Renaming would break every existing fixture's path-based assertions and the `git grep -nF '.kiln/logs/kiln-test-'` discipline used by friction notes / retros. Encoded in **NFR-R-7**.

## Reconciliation Against Researcher-Baseline (§1.5 Baseline Checkpoint)

The researcher-baseline captured three pre-PRD baselines and emitted four reconciliation directives (`research.md §reconciliation directive`). Each is acknowledged below; thresholds in §Success Criteria are recalibrated to match observed reality, NOT the PRD prose verbatim.

1. **SC-R-2 ±10% relaxed to ±20%** (matches precedent NFR-F-4 from PR #168). Live perf samples have run-to-run noise of ±9.5% on `wall_clock_sec` in the captured 5-sample run (raw 7.401s–8.877s around 7.751s median). ±10% sits AT the noise floor; ±20% is the comfortable band. `num_turns` MUST be exact (deterministic — protocol shape, not perf). `output_tokens` advisory ±10% (token count is more stable than wall-clock). `cost_usd` derived from tokens — informational only.
2. **SC-R-1 byte-identity refined to per-fixture comparator**. The three named fixtures have heterogeneous artifact shapes:
   - `preprocess-substitution.bats` — bats TAP output, fully deterministic, true byte-identity achievable post-PRD (modulo timestamps if any).
   - `kiln-distill-basic` — watcher verdict report `.md` + `verdict.json`. The `## Last 50 transcript envelopes` section body is LLM-stochastic and MUST be excluded **section-level** (skip the entire section body, not regex-match its content). Headers, framing, framing-only fields (Classification, Scratch UUID, Stall window, Poll interval) ARE byte-stable post-modulo.
   - `perf-kiln-report-issue` — does NOT route through `kiln-test.sh` (its `harness-type: static` is dead metadata; runs via its own `run.sh` directly). NOT a `wheel-test-runner.sh` fixture. Its TSV column shape + medians-JSON shape are the back-compat invariants for this fixture, NOT verdict-report contents.
   The exclusion contract is pinned in `contracts/interfaces.md §3 (snapshot-diff comparator)`.
3. **`harness-type: static` is dead metadata**. `dispatch-substrate.sh` only implements `plugin-skill`; `static` falls through to `Substrate '<X>' not implemented in v1` (exit 2). Backward compat (NFR-R-3) only requires the `plugin-skill` substrate path covered by `wheel-test-runner.sh`. The harness-type extension is roadmap item #2 (`shell-test-substrate`), out of scope here.
4. **NFR-F-6 (resolver overhead 387ms vs 200ms threshold) is pre-existing on main, NOT caused by this PRD**. Surfaced in the perf-baseline run; the auditor MUST NOT blame this PRD for the regression. Track separately as a follow-on issue.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Existing `/kiln:kiln-test` consumers see no behavioral change (Priority: P1 — HARD GATE)

As an existing kiln-test consumer (any developer running `/kiln:kiln-test plugin-kiln <fixture>` today), my invocation continues to work byte-identically post-PRD. Verdict report paths, scratch-dir prefixes, TAP v14 stdout, and exit codes all match pre-PRD behavior. No migration, no new fixture format, no churn.

**Why this priority**: P1 hard gate because the entire PRD value rests on byte-identical user-facing behavior. NFR-R-3 says "any non-modulo-timestamps difference fails the gate." If this story regresses, the PR cannot ship.

**Independent Test**: Run a representative subset of three fixtures (one each: `preprocess-substitution.bats`, `kiln-distill-basic`, plus a fast-deterministic plugin-skill fixture) pre-PRD and post-PRD. Snapshot-diff the verdict reports / TAP output via the `contracts/interfaces.md §3` exclusion comparator. Delta = 0 lines beyond the modulo-list. Mutate the runner to emit a stray space character in the TAP header and assert the diff fires (mutation tripwire).

**Acceptance Scenarios**:

1. **Given** the PRD shipped on this branch, **When** I run `/kiln:kiln-test plugin-kiln <existing-fixture>`, **Then** the verdict report at `.kiln/logs/kiln-test-<uuid>.md` is byte-identical to the pre-PRD baseline (modulo timestamps, UUIDs, and absolute scratch paths) per the `contracts/interfaces.md §3` per-fixture exclusion contract.
2. **Given** the same fixture, **When** I inspect TAP v14 stdout, **Then** the line-by-line content matches pre-PRD (modulo timestamps in YAML diagnostic blocks).
3. **Given** the same fixture, **When** the run completes, **Then** the exit code (0 = pass, 1 = fail, 2 = skip) matches pre-PRD for the same input.
4. **Given** an existing fixture passing pre-PRD with output `ok 1 - <name>`, **When** I run it post-PRD, **Then** it passes with the same TAP line.

---

### User Story 2 — A non-kiln plugin author can invoke the runner without depending on kiln (Priority: P1)

As an author of a future non-kiln plugin (e.g., `plugin-roles`, or a hypothetical `plugin-foo`), I can invoke `wheel-test-runner.sh` directly via `bash <wheel-install>/scripts/harness/wheel-test-runner.sh <plugin> <fixture>` to run my own plugin's tests, without `plugin-kiln/` appearing anywhere in my call chain.

**Why this priority**: P1 because non-kiln consumability is the entire motivation for the move. If this can't be demonstrated post-PRD, the parent goal `wheel-as-plugin-agnostic-infra` is suspect.

**Independent Test**: Author `plugin-wheel/tests/wheel-test-runner-direct/run.sh` with a synthetic minimal scratch-fixture (no real LLM call needed — the fixture validates the runner's argument parsing, plugin-resolution, scratch-dir creation, and exit-code aggregation paths). The fixture does NOT invoke `/kiln:kiln-test` or reference `plugin-kiln/`. Assert: exit 0, last-line PASS summary in run.sh stdout, expected verdict-report path written.

**Acceptance Scenarios**:

1. **Given** the PRD shipped, **When** I run `bash plugin-wheel/tests/wheel-test-runner-direct/run.sh`, **Then** the runner is invoked directly (no kiln-side detour), the scratch dir is created at `/tmp/kiln-test-<uuid>/`, and the verdict report is written to `.kiln/logs/kiln-test-<uuid>.md` (the `kiln-test-` prefix is a back-compat fossil per OQ-R-3).
2. **Given** the fixture's `run.sh`, **When** I `git grep -nF 'plugin-kiln/' plugin-wheel/tests/wheel-test-runner-direct/run.sh`, **Then** zero matches are returned — proves the fixture is plugin-kiln-independent.
3. **Given** a malformed input (e.g., `wheel-test-runner.sh nonexistent-plugin`), **When** the runner runs, **Then** it bails out with a TAP `Bail out!` line and exit 2 — same diagnostic shape as pre-PRD `kiln-test.sh`.

---

### User Story 3 — Live-smoke gate (`perf-kiln-report-issue`) passes within ±20% perf envelope (Priority: P1 — HARD GATE)

As the auditor, when I run the proven live-smoke substrate `bash plugin-kiln/tests/perf-kiln-report-issue/run.sh` post-merge, the `after`-arm medians for `wall_clock_sec` and `duration_api_ms` are within ±20% of the researcher-baseline pre-PRD medians, `num_turns` matches exactly, and the run completes successfully.

**Why this priority**: P1 hard gate per NFR-R-5 (Live-Substrate-First Rule from issue #170 fix). Structural surrogates (a fixture exists, a snapshot diff is clean) are NOT sufficient evidence; the live substrate must demonstrably work.

**Independent Test**: Run `bash plugin-kiln/tests/perf-kiln-report-issue/run.sh` post-merge (~3 min wall-clock). Compare the resulting `/tmp/perf-medians.json` against `specs/wheel-test-runner-extraction/research/perf-baseline-medians.json` per the §Success Criteria SC-R-2 envelope. Cite the run log + medians path in the PR description's verification checklist.

**Acceptance Scenarios**:

1. **Given** the PRD shipped, **When** I run `bash plugin-kiln/tests/perf-kiln-report-issue/run.sh`, **Then** post-run `after_arm_medians.elapsed_sec` is within ±20% of the pre-PRD baseline (7.751s → range 6.20s–9.30s).
2. **Given** the same run, **When** I check `after_arm_medians.duration_api_ms`, **Then** it is within ±20% of the pre-PRD baseline (4364ms → range 3491ms–5237ms).
3. **Given** the same run, **When** I check `after_arm_medians.num_turns`, **Then** it equals exactly 2 (deterministic protocol shape).
4. **Given** the same run, **When** I check `after_arm_medians.output_tokens`, **Then** it is within ±10% of the pre-PRD baseline (180 → range 162–198) — advisory band.
5. **Given** the run completes, **When** the run.sh exits, **Then** exit code = 0 AND the last line of stdout includes a PASS summary.

---

### User Story 4 — Grep gate post-PRD shows zero live references to old path (Priority: P2)

As a maintainer, when I grep for the old runner path post-PRD, I find zero live-code matches. Archived state files, blockers, retros, and historical docs MAY reference the old path; live skills, agents, hooks, scripts, and workflows MUST NOT.

**Why this priority**: P2 (verification, not feature). Hard gate for the auditor.

**Independent Test**: Run `git grep -nF 'plugin-kiln/scripts/harness/kiln-test'` post-PRD. Filter out: `.wheel/history/**`, `specs/**/blockers.md`, `specs/**/retro.md`, `docs/features/**/PRD.md` (frozen), `CLAUDE.md` Recent Changes block (historical). The remaining match list MUST be empty.

**Acceptance Scenarios**:

1. **Given** the PRD shipped, **When** I run the grep above with the documented exclusions, **Then** the result is empty.
2. **Given** the SKILL.md update, **When** I read `plugin-kiln/skills/kiln-test/SKILL.md`, **Then** the `bash <path>` line points at `${WORKFLOW_PLUGIN_DIR}/../plugin-wheel/scripts/harness/wheel-test-runner.sh`.

---

### User Story 5 — Façade overhead ≤50ms per invocation (Priority: P3)

As a `/kiln:kiln-test` user, the new façade adds at most 50ms of indirection per invocation (one extra script-invocation hop + arg passthrough). This is sub-perceptible and well within bash subprocess overhead.

**Why this priority**: P3 informational. Measured, not gated.

**Independent Test**: `time` a fast-deterministic fixture pre-PRD vs post-PRD. Difference ≤50ms.

**Acceptance Scenarios**:

1. **Given** the same fixture pre vs post, **When** I `time` both, **Then** the post-PRD wall-clock exceeds pre-PRD by ≤50ms.

---

## Functional Requirements

### Theme R1 — Move runner core to wheel

- **FR-R1-1**: `plugin-kiln/scripts/harness/kiln-test.sh` core orchestration logic moves to `plugin-wheel/scripts/harness/wheel-test-runner.sh`. Filename `wheel-test-runner.sh` per OQ-R-2 resolution. The new file is self-contained — does not source anything from `plugin-kiln/scripts/`.
- **FR-R1-2**: ALL runner-internal helpers under `plugin-kiln/scripts/harness/` move alongside to `plugin-wheel/scripts/harness/` — exhaustive list: `watcher-runner.sh`, `dispatch-substrate.sh`, `substrate-plugin-skill.sh`, `tap-emit.sh`, `test-yaml-validate.sh`, `scratch-create.sh`, `scratch-snapshot.sh`, `fixture-seeder.sh`, `claude-invoke.sh`, `config-load.sh`, `watcher-poll.sh`. Internal cross-references between these scripts use `${BASH_SOURCE[0]}`-relative paths (already the established pattern in `kiln-test.sh:30`); no edits required to internal-cross-reference logic during the move.
- **FR-R1-3**: `wheel-test-runner.sh` accepts the same CLI arguments as the old `kiln-test.sh` (zero args = auto-detect plugin, one arg = `<plugin>`, two args = `<plugin> <test>`). Same exit codes (0 / 1 / 2 per existing contract).
- **FR-R1-4**: `wheel-test-runner.sh` writes verdict reports to the same path (`.kiln/logs/kiln-test-<uuid>.md`) and uses the same scratch-dir convention (`/tmp/kiln-test-<uuid>/`). Path-naming `kiln-test-` prefix STAYS per OQ-R-3 (back-compat fossil).
- **FR-R1-5**: `wheel-test-runner.sh` emits TAP v14 on stdout, byte-identical to today's `kiln-test.sh` shape (modulo timestamps).
- **FR-R1-6**: `wheel-test-runner.sh` honors `KILN_TEST_REPO_ROOT` env var as today's runner does (line 88 of `kiln-test.sh`). Variable name `KILN_TEST_REPO_ROOT` is preserved as a back-compat fossil; renaming would break consumers' existing env overrides.

### Theme R2 — Façade pattern in `/kiln:kiln-test` SKILL.md

- **FR-R2-1**: `plugin-kiln/skills/kiln-test/SKILL.md` updates the `bash <path>` invocation from `bash "${WORKFLOW_PLUGIN_DIR}/scripts/harness/kiln-test.sh" $ARGUMENTS` to `bash "${WORKFLOW_PLUGIN_DIR}/../plugin-wheel/scripts/harness/wheel-test-runner.sh" $ARGUMENTS`. Resolution pattern per OQ-R-1 resolution.
- **FR-R2-2**: The skill prose (test fixture conventions, `test.yaml` schema documentation, allowed `harness-type` values, verdict-report shape, `inputs/`/`fixtures/`/`assertions.sh` layout, env vars `KILN_HARNESS=1` / `KILN_TEST_SCRATCH_DIR` / `KILN_TEST_NAME` / `KILN_TEST_VERDICT_JSON`, `.kiln/test.config` overrides documentation) stays UNCHANGED. ONLY the bash invocation line + the line `${WORKFLOW_PLUGIN_DIR}/scripts/harness/kiln-test.sh` non-negotiable in the prose's preamble change.
- **FR-R2-3**: Audit all kiln SKILL.md / agent / hook files for live references to `plugin-kiln/scripts/harness/kiln-test` or `kiln-test.sh`. Update each to point at the wheel-side location. `git grep -nF 'plugin-kiln/scripts/harness/kiln-test'` post-PRD returns zero matches in live code per User Story 4 acceptance.

### Theme R3 — Non-kiln consumability validation

- **FR-R3-1**: A new fixture at `plugin-wheel/tests/wheel-test-runner-direct/run.sh` invokes `wheel-test-runner.sh` directly (independent of `/kiln:kiln-test`). The fixture's `run.sh` exercises a synthetic minimal substrate (e.g., a scratch test fixture under the same dir's `tests/` subdir, exercised via the runner's own `<plugin> <fixture>` invocation form). Asserts on exit code + verdict-report contents per User Story 2.
- **FR-R3-2**: `git grep -nF 'plugin-kiln/' plugin-wheel/tests/wheel-test-runner-direct/run.sh` post-PRD returns zero matches.

### Theme R4 — Backward compat (NON-NEGOTIABLE)

- **FR-R4-1**: For each of the three representative fixtures (`preprocess-substitution.bats`, `kiln-distill-basic`, plus one fast-deterministic plugin-skill fixture), the verdict-report contents (or TAP output for bats) post-PRD are byte-identical to pre-PRD per the `contracts/interfaces.md §3` per-fixture exclusion comparator. Verified by snapshot-diff against `specs/wheel-test-runner-extraction/research/baseline-snapshot/`.
- **FR-R4-2**: TAP v14 stdout output is byte-identical (modulo timestamps in YAML diagnostic blocks).
- **FR-R4-3**: Exit codes (0 / 1 / 2) match today's behavior for the same fixture on the same input.
- **FR-R4-4**: ALL `plugin-kiln/tests/<fixture>/` and `plugin-wheel/tests/<fixture>/` invocations that pass pre-PRD continue to pass post-PRD with no changes to fixture files (only the runner moves; fixtures stay where they are per PRD §Non-Goals).

## Non-Functional Requirements

- **NFR-R-1 (testing — kiln-test substrate as primary evidence)**: Per the substrate-hierarchy carve-out for tier-2 pure-shell unit fixtures, the new `plugin-wheel/tests/wheel-test-runner-direct/run.sh` is invoked via `bash run.sh` (run.sh-only pattern; no `test.yaml` needed since this fixture proves the runner works WITHOUT `/kiln:kiln-test` as the entry point). Implementer cites exit code + last-line PASS summary in `agent-notes/implementer.md`.
- **NFR-R-2 (silent-failure tripwires)**: Each backward-compat invariant (FR-R4-1 / FR-R4-2 / FR-R4-3) has at least one mutation-tripwire test. If the move silently changes verdict-report format, exit codes, or stdout shape, the regression test fails loudly.
- **NFR-R-3 (backward compat — strict / NON-NEGOTIABLE)**: Per FR-R4. Verified by snapshot-diff via `contracts/interfaces.md §3 (snapshot-diff comparator)` against `specs/wheel-test-runner-extraction/research/baseline-snapshot/`. Any non-modulo-list difference fails the gate. Scope: ONLY the `plugin-skill` substrate path matters for backward compat (per researcher reconciliation directive #3 — `harness-type: static` is dead metadata in `dispatch-substrate.sh`; the harness-type extension is roadmap item #2, out of scope here).
- **NFR-R-4 (atomic shipment)**: The move (FR-R1) and the façade update (FR-R2) MUST land in the same squash-merge PR per Path B precedent (PRs #166, #168). No half-state where the kiln-side script is gone but `/kiln:kiln-test` SKILL.md still points at it.
- **NFR-R-5 (live-smoke gate — NON-NEGOTIABLE)**: Per the §Auditor Prompt — Live-Substrate-First Rule. The auditor MUST run `bash plugin-kiln/tests/perf-kiln-report-issue/run.sh` post-merge — its `after`-arm medians MUST satisfy User Story 3's tolerance bands. Audit fixture-existence-only is a blocker per the issue #170 fix.
- **NFR-R-6 (perf budget)**: Façade indirection adds at most 50ms per `/kiln:kiln-test` invocation. Measured by `time` against a known fixture, pre vs post.
- **NFR-R-7 (no rename in user-facing paths)**: Verdict-report path prefix `.kiln/logs/kiln-test-*.md`, scratch-dir prefix `/tmp/kiln-test-*`, env-var name `KILN_TEST_REPO_ROOT`, and skill name `/kiln:kiln-test` STAY identical. Renaming any would break existing fixtures' path-based assertions.
- **NFR-R-8 (snapshot-diff comparator pinned)**: The per-fixture exclusion list is pinned in `contracts/interfaces.md §3`. Implementer MUST author a snapshot-diff helper (`plugin-wheel/scripts/harness/snapshot-diff.sh` or inline in the fixture's `run.sh`) that applies the per-fixture exclusion contract — NOT a one-off ad-hoc regex. R-R-3 mitigation.

## Success Criteria

### Headline (HARD GATE — required to ship)

- **SC-R-1**: For each of the three representative fixtures (`plugin-wheel/tests/preprocess-substitution.bats`, `plugin-kiln/tests/kiln-distill-basic/`, plus one fast-deterministic plugin-skill fixture chosen by the implementer), snapshot-diff vs `specs/wheel-test-runner-extraction/research/baseline-snapshot/` is byte-identical per the `contracts/interfaces.md §3` exclusion comparator. Delta = 0 lines beyond the per-fixture exclusion list.
- **SC-R-2**: Live-smoke gate `bash plugin-kiln/tests/perf-kiln-report-issue/run.sh` end-to-end (~3 min wall-clock) passes post-merge with `after_arm_medians` within these tolerances vs `specs/wheel-test-runner-extraction/research/perf-baseline-medians.json`:
  - `wall_clock_sec` (median 7.751s pre-PRD): post-PRD median within **±20%** (range 6.20s–9.30s). Reconciled from PRD's ±10% per researcher directive #1 — ±10% sits at noise floor (raw spread ±9.5%).
  - `duration_api_ms` (median 4364ms pre-PRD): post-PRD median within **±20%** (range 3491ms–5237ms).
  - `num_turns` (pre-PRD = 2): post-PRD MUST equal exactly 2 (deterministic protocol shape).
  - `output_tokens` (pre-PRD = 180): post-PRD median within **±10%** (range 162–198) — advisory band.
  - `total_cost_usd`: derived from tokens — informational only, NOT gated.
- **SC-R-3**: Grep gate — `git grep -nF 'plugin-kiln/scripts/harness/kiln-test'` post-PRD returns zero matches in live code, with documented exclusions: `.wheel/history/**`, `specs/**/blockers.md`, `specs/**/retro.md`, `docs/features/**/PRD.md`, `CLAUDE.md` Recent Changes block.

### Secondary (informational)

- **SC-R-4**: New `plugin-wheel/tests/wheel-test-runner-direct/run.sh` fixture exercises the runner directly with a synthetic fixture and passes (exit 0, last-line PASS summary).
- **SC-R-5**: Façade overhead measured via `time` is ≤50ms per invocation (NFR-R-6).
- **SC-R-6**: A wheel-only consumer pattern is documented in `plugin-wheel/docs/test-runner.md` (or appended to `plugin-wheel/README.md`) showing how a non-kiln plugin invokes the runner.

### Process

- **SC-R-7**: NFR-R-5 satisfied — live-smoke gate run by the auditor and its medians-JSON path cited in the PR description's verification checklist.
- **SC-R-8**: Friction note `agent-notes/implementer.md` exists, cites kiln-test verdict report paths for every authored fixture, and documents the live-smoke run's medians-JSON path. Required by FR-009 of process-governance.

## Edge Cases

- **EC-1 (consumer-install layout)**: When `/kiln:kiln-test` runs in a consumer project (not this source repo), `${WORKFLOW_PLUGIN_DIR}` resolves to `~/.claude/plugins/cache/<org>-<mp>/plugin-kiln/<version>/`. The OQ-R-1 resolution pattern `${WORKFLOW_PLUGIN_DIR}/../plugin-wheel/scripts/harness/wheel-test-runner.sh` thus resolves to `~/.claude/plugins/cache/<org>-<mp>/plugin-wheel/<version>/scripts/harness/wheel-test-runner.sh` — sibling-plugin layout. Validated by the consumer-install smoke pattern at `plugin-wheel/tests/workflow-plugin-dir-bg/run.sh` (PR #168 invariant).
- **EC-2 (runner sourced from outside `plugin-wheel/`)**: A non-kiln plugin (or an ad-hoc script) invokes `wheel-test-runner.sh` directly via absolute path. The runner's `${BASH_SOURCE[0]}`-relative `harness_dir` resolution still works correctly (it doesn't require any specific CWD).
- **EC-3 (`KILN_TEST_REPO_ROOT` override)**: A caller exports `KILN_TEST_REPO_ROOT=/some/other/path` to redirect plugin-discovery. The wheel-side runner honors this verbatim per FR-R1-6.
- **EC-4 (claude CLI not on PATH)**: The runner emits `Bail out! claude CLI not on PATH; install Claude Code (...)` and exits 2. Behavior preserved verbatim.
- **EC-5 (scratch UUID collision)**: Already handled by `scratch-create.sh` via `uuidgen`. No change.
- **EC-6 (snapshot-diff false positive on framing change)**: Mitigated by `contracts/interfaces.md §3` per-fixture exclusion contract pinning the section-level boundaries (NOT regex-level body matches) for `kiln-distill-basic`. R-R-3 mitigation.

## Open Questions

All PRD Open Questions resolved in §Resolution of PRD Open Questions above. No new open questions emerged from baseline reconciliation that block implementation.

**One process flag** (informational, not blocking):
- The pre-existing NFR-F-6 regression (resolver overhead 387ms vs 200ms threshold on main) is visible in `specs/wheel-test-runner-extraction/research/perf-baseline-runlog.txt`. NOT caused by this PRD; track as a separate follow-on issue. Auditor MUST NOT block this PRD on it.

## Risks Carried Forward from PRD

- **R-R-1 (Hidden coupling between runner and kiln-specific paths)**: Mitigated in plan phase — Phase 1 includes a grep audit of all 12 harness scripts for `plugin-kiln/` literals. None expected (`harness_dir` resolution uses `${BASH_SOURCE[0]}`), but verify before declaring the move complete.
- **R-R-2 (`/kiln:kiln-test` skill resolution discipline)**: RESOLVED via OQ-R-1 → option (a). Consumer-install layout validated by `workflow-plugin-dir-bg` smoke pattern.
- **R-R-3 (Snapshot-diff false positives)**: Mitigated by `contracts/interfaces.md §3` per-fixture exclusion contract. Implementer authors a comparator helper, NOT a one-off ad-hoc regex.
- **R-R-4 (Substrate-gap recurrence)**: Out of scope here — this PRD ships on its own; data feeds back into items #2-#4 decisions.

## Dependencies & Assumptions

- The runner's current dependencies (`claude` CLI on PATH, `jq`, `python3`, bash 5.x, POSIX utilities) are all wheel-acceptable. Confirmed — wheel already requires these.
- No external consumer outside kiln currently calls `kiln-test.sh` directly. Confirmed via `git grep` (only kiln-internal references; archived state files / blockers / retros excluded).
- The 50ms façade-overhead budget (NFR-R-6) is achievable. High confidence — script-invocation overhead is sub-millisecond on modern hardware; bash subprocess startup is the dominant cost (~5-10ms).
