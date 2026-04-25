---
derived_from:
  - .kiln/roadmap/items/2026-04-25-wheel-test-runner-extraction.md
  - .kiln/roadmap/items/2026-04-23-wheel-as-plugin-agnostic-infra.md
distilled_date: 2026-04-25
theme: wheel-test-runner-extraction
---
# Feature PRD: Wheel Test Runner Extraction (`kiln-test` → `wheel-test-runner`)

**Date**: 2026-04-25
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)
**Parent goal**: [`.kiln/roadmap/items/2026-04-23-wheel-as-plugin-agnostic-infra.md`](../../../.kiln/roadmap/items/2026-04-23-wheel-as-plugin-agnostic-infra.md)
**Builds on**: PR #166 + PR #168 (typed inputs/outputs + schema locality). Independent of the typed-schema work but uses the same kiln-test substrate as both PRs' audit gates.

## Parent Product

This is the **kiln** Claude Code plugin ecosystem. Wheel is the workflow runtime; kiln is the spec-first development plugin. Today the executable test-harness substrate (`kiln-test.sh`, the thing that spawns `claude --print --plugin-dir <local>` subprocesses against scratch-dir fixtures) lives entirely in kiln. This PRD moves the harness CORE to wheel where any plugin can consume it, and keeps `/kiln:kiln-test` as a thin façade that delegates.

## Feature Overview

This is the lowest-blast extraction in the [`wheel-as-plugin-agnostic-infra`](../../../.kiln/roadmap/items/2026-04-23-wheel-as-plugin-agnostic-infra.md) roadmap goal. Pure refactor with byte-identical user-facing behavior.

**Three changes**:

1. **Move** `plugin-kiln/scripts/harness/kiln-test.sh` core logic to `plugin-wheel/scripts/harness/wheel-test-runner.sh`. Sibling helpers (`watcher-runner.sh` and any other kiln-test-internal scripts) move alongside.
2. **`/kiln:kiln-test` SKILL.md** updates its `bash <path>` invocation to point at the wheel-side script. Skill prose stays in kiln (the skill prose IS kiln-specific — it documents the kiln test fixture conventions). The runner moves.
3. **New wheel-side test** exercises `wheel-test-runner.sh` directly without going through `/kiln:kiln-test` — proves the runner is genuinely consumable by non-kiln callers.

After this PRD ships, any future plugin (clay, trim, hypothetical new ones) can author its own `<plugin>:<test-skill>` that calls `wheel-test-runner.sh` without touching kiln. This unblocks the rest of the parent goal: items #2 (`shell-test-substrate`), #3 (`friction-note-primitive`), #4 (`team-orchestration-primitive`) all extend or compose with the wheel-side runner.

## Problem / Motivation

The kiln-test substrate is plugin-agnostic by construction (claude-subprocess + scratch-dir + watcher classifier — none of which depend on kiln conventions), but it lives in `plugin-kiln/scripts/harness/`. This forces an awkward path for non-kiln consumers: they'd have to either depend on kiln being installed OR fork/duplicate the harness. Today nobody else uses it, but that's because nobody CAN use it cleanly.

The bigger motivation: this PRD is the smallest validation experiment for the parent goal `wheel-as-plugin-agnostic-infra`. If extracting THIS — the most cleanly-separable mechanism in kiln — turns out to be friction-prone, the entire parent goal is suspect. If it lands smoothly, items #2-#4 inherit the validated pattern and ship faster.

Direct lessons baked in:

- **PR #166 + PR #168 audit gates** both used `bash plugin-kiln/tests/perf-kiln-report-issue/run.sh` as the proven live-smoke substrate. That fixture invokes the kiln-test runner under the hood. Moving the runner to wheel doesn't change the fixture — it just relocates the call target. The wheel-test-runner.sh becomes the canonical location for the substrate that other PRDs already depend on.
- **Issue #170** (filed today) is itself evidence that the substrate's contracts (label filter, format) need maintenance discipline. Extracting the runner to wheel doesn't fix #170 directly but creates the surface where #170-class fixes can live next to the substrate they govern.

## Goals

- **Move the harness core to wheel** without changing user-facing behavior. `/kiln:kiln-test plugin-kiln <fixture>` produces byte-identical verdict reports (modulo timestamps + UUIDs) before vs. after the move.
- **Keep `/kiln:kiln-test` as a thin façade.** The skill prose stays in kiln (it documents kiln test fixture conventions, test.yaml schema, harness-type values). The mechanical runner moves.
- **Validate non-kiln consumability.** A wheel-side test invokes `wheel-test-runner.sh` directly with a synthetic fixture — proves the runner works without `/kiln:kiln-test` in the call chain.
- **Preserve all existing fixtures' verdict-report shape.** Every test fixture currently passing under `plugin-kiln/tests/` and `plugin-wheel/tests/` continues to pass with byte-identical output (modulo timestamps + UUIDs).
- **Bound the perf overhead.** The façade adds at most 50ms of indirection per `/kiln:kiln-test` invocation (one extra script invocation + arg passthrough).

## Non-Goals (v1)

- **Not** adding the `harness-type: shell-test` substrate. That's roadmap item #2 (`2026-04-25-shell-test-substrate.md`) — depends on this PRD shipping first. v1 here is pure relocation; harness-type extension is a follow-on.
- **Not** moving any kiln-specific skill prose. `/kiln:kiln-test` SKILL.md stays in kiln (it documents kiln test fixture conventions, allowed `harness-type` values, verdict report format expectations). Only the bash runner moves.
- **Not** renaming the skill. `/kiln:kiln-test` stays as-is. We're not breaking user muscle memory.
- **Not** changing the verdict report format. Output paths (`.kiln/logs/kiln-test-<uuid>.md`), structure, and fields are byte-identical pre/post.
- **Not** introducing a new wheel skill (`/wheel:wheel-test` already exists for a different purpose — running wheel workflow tests). The new runner is callable as a SCRIPT from any caller; no new skill surface.
- **Not** moving `plugin-kiln/tests/` fixtures. Fixtures stay where they are; only the engine that runs them moves.

## Target Users

Inherited from parent product:

- **Plugin authors** (any plugin, not just kiln) — gain a sanctioned path to author tests that the harness can run, without forking or vendoring kiln scripts.
- **Future PRDs in the parent goal** — items #2 (`shell-test-substrate`), #3 (`friction-note-primitive`), #4 (`team-orchestration-primitive`) all reference the wheel-side runner location. This PRD establishes that location.
- **`/kiln:kiln-test` consumers** — see no behavioral change. The skill keeps working exactly as today.

## Core User Stories

- **As a plugin author writing a non-kiln plugin** (e.g., a future `plugin-roles`), I want to invoke the test substrate via `bash <wheel-install>/scripts/harness/wheel-test-runner.sh <plugin> <fixture>` so I don't have to install kiln just to run my own plugin's tests.
- **As an existing kiln-test consumer**, I want my `/kiln:kiln-test plugin-kiln <fixture>` invocations to keep working byte-identically — no migration required, no new fixture format, no new verdict report shape.
- **As a future PRD author building on top** (items #2-#4 of the parent goal), I want the wheel-side runner location to be canonical so my PRD's "extend the runner with X" instructions are unambiguous.

## Functional Requirements

### Theme R1 — Move runner core to wheel

- **FR-R1-1**: `plugin-kiln/scripts/harness/kiln-test.sh` core orchestration logic moves to `plugin-wheel/scripts/harness/wheel-test-runner.sh`. The new file is a complete, self-contained runner — does not source anything from `plugin-kiln/scripts/`.
- **FR-R1-2**: Sibling kiln-test-internal helpers (`watcher-runner.sh`, any other scripts under `plugin-kiln/scripts/harness/` that are runner-internal — NOT consumer-facing) move alongside to `plugin-wheel/scripts/harness/`.
- **FR-R1-3**: The new wheel-side runner accepts the same CLI arguments as the old kiln-test.sh (`<plugin>`, `<plugin> <fixture>`, auto-detect mode). Same exit codes (0/1/2 per existing contract).
- **FR-R1-4**: The new wheel-side runner writes verdict reports to the same path (`.kiln/logs/kiln-test-<uuid>.md`) and the same scratch-dir convention (`/tmp/kiln-test-<uuid>/`). Path naming stays "kiln-test-" for back-compat — no rename.
- **FR-R1-5**: The new wheel-side runner emits TAP v14 on stdout, identical to today's kiln-test.sh.

### Theme R2 — Façade pattern in `/kiln:kiln-test` SKILL.md

- **FR-R2-1**: `plugin-kiln/skills/kiln-test/SKILL.md` updates the `bash <path>` invocation to point at the wheel-side script: `bash "${WORKFLOW_PLUGIN_DIR}/../plugin-wheel/scripts/harness/wheel-test-runner.sh" $ARGUMENTS` (or whichever resolution pattern matches the existing kiln-test SKILL — preserve the resolution discipline, just change the target).
- **FR-R2-2**: The skill prose (test fixture conventions, test.yaml schema documentation, harness-type values, verdict report shape) stays UNCHANGED. Only the bash invocation line changes.
- **FR-R2-3**: All references in other kiln SKILL.md files that mention `kiln-test.sh` or `plugin-kiln/scripts/harness/` paths get updated to point at the new wheel-side location. Grep-then-update pattern: `git grep -nF 'plugin-kiln/scripts/harness/kiln-test'` should return zero matches post-PRD.

### Theme R3 — Non-kiln consumability validation

- **FR-R3-1**: New fixture under `plugin-wheel/tests/<name>/` exercises `wheel-test-runner.sh` directly via `bash run.sh` (independent of `/kiln:kiln-test`). The fixture's `run.sh` invokes the runner with a synthetic minimal scratch-fixture and asserts on exit code + verdict report contents.
- **FR-R3-2**: The fixture proves the runner works WITHOUT any `plugin-kiln/` reference in its call chain. Demonstrates the substrate is genuinely plugin-agnostic.

### Theme R4 — Backward compat (NON-NEGOTIABLE)

- **FR-R4-1**: Every existing `plugin-kiln/tests/<fixture>/` and `plugin-wheel/tests/<fixture>/` invocation produces byte-identical verdict-report contents (modulo timestamps, UUIDs, and absolute paths) before vs. after the move. Verified by snapshot diff.
- **FR-R4-2**: TAP v14 stdout output is byte-identical (modulo timestamps).
- **FR-R4-3**: Exit codes (0/1/2) match today's behavior for the same fixture on the same input.

## Non-Functional Requirements

- **NFR-R-1 (testing — kiln-test substrate as primary evidence)**: The new wheel-side fixture under `plugin-wheel/tests/` exercises the runner end-to-end. Implementer MUST invoke it via `bash plugin-wheel/tests/<fixture>/run.sh` (run.sh-only pattern; no test.yaml needed since this fixture proves the runner works WITHOUT kiln-test as the entry point) AND cite the exit code + last-line PASS summary in the friction note. Per the new substrate-hierarchy rules in `kiln-build-prd` SKILL.md (§Implementer Prompt — Test Substrate Hierarchy), this is "tier 2: pure-shell unit fixture" — appropriate substrate for a no-LLM-needed pure-bash extraction.
- **NFR-R-2 (silent-failure tripwires)**: Each backward-compat invariant has a regression test. If the move silently changes verdict report format, exit codes, or stdout shape, the regression test fails loudly.
- **NFR-R-3 (backward compat — strict / NON-NEGOTIABLE)**: Per FR-R4. Verified by snapshot diff against pre-PRD baseline. Any non-modulo-timestamps difference fails the gate.
- **NFR-R-4 (atomic shipment)**: The move (FR-R1) and the façade update (FR-R2) MUST land in the same commit (or same squash-merged PR per Path B precedent from PRs #166, #168). No half-state where the kiln-side script is gone but `/kiln:kiln-test` SKILL.md still points at it.
- **NFR-R-5 (live-smoke gate — NON-NEGOTIABLE)**: Per the new §Auditor Prompt — Live-Substrate-First Rule from issue #170 fix, the auditor MUST verify the live substrate works post-merge. Run `bash plugin-kiln/tests/perf-kiln-report-issue/run.sh` (the proven harness from PRs #166 + #168) — it MUST pass with the same metrics envelope as before. Any regression in num_turns / wall-clock / api_ms is a blocker.
- **NFR-R-6 (perf budget)**: Façade indirection adds at most 50ms per `/kiln:kiln-test` invocation. Measured by `time` against a known fixture, pre vs. post.
- **NFR-R-7 (no rename in user-facing paths)**: Verdict report paths (`.kiln/logs/kiln-test-*.md`) and scratch-dir prefix (`/tmp/kiln-test-*`) stay identical. Renaming would break every existing fixture's path-based assertions.

## Absolute Musts

These are non-negotiable. Tech stack is always #1.

1. **Bash 5.x + `jq` + POSIX** — no new runtime dependencies. Pure relocation of existing scripts.
2. **Backward compat byte-identical** — every existing fixture continues to produce identical verdict reports (modulo timestamps + UUIDs). NFR-R-3 is the gate.
3. **Atomic shipment** — the move and the façade update land together. No half-state.
4. **Live-smoke gate** — `bash plugin-kiln/tests/perf-kiln-report-issue/run.sh` passes post-merge with no metrics regression. NFR-R-5.
5. **No skill rename** — `/kiln:kiln-test` stays. Verdict report path prefix `kiln-test-*` stays. Scratch dir prefix `/tmp/kiln-test-*` stays. No user-facing path churn.

## Tech Stack

Inherited from parent product:

- Bash 5.x + `jq` + POSIX utilities — relocation only, no new languages or runtimes
- Files moving: `plugin-kiln/scripts/harness/kiln-test.sh` and any other runner-internal scripts under that directory → `plugin-wheel/scripts/harness/`
- Files updating: `plugin-kiln/skills/kiln-test/SKILL.md` (one line), any other SKILL.md / docs that reference `plugin-kiln/scripts/harness/kiln-test.sh` paths

No new dependencies.

## Impact on Existing Features

- **`/kiln:kiln-test`** — no behavioral change. Façade delegates to wheel-side runner.
- **Existing fixtures** under `plugin-kiln/tests/` and `plugin-wheel/tests/` — no change. Same invocation, same output.
- **Audit gates in PRs #166, #168** — `bash plugin-kiln/tests/perf-kiln-report-issue/run.sh` continues to work as the proven live-smoke substrate. The TSV output format is unchanged.
- **`kiln-build-prd` retro discipline** — friction notes can keep citing "verdict report at `.kiln/logs/kiln-test-<uuid>.md`" verbatim.
- **Future roadmap items #2-#4** — gain a canonical wheel-side runner location to extend (#2: add shell-test substrate; #3: friction-note primitive; #4: team-orchestrate primitive).
- **Plugin authors outside kiln** — gain a sanctioned path to invoke the test substrate without depending on kiln being installed.

## Success Metrics

### Headline (HARD GATE — required to ship)

- **SC-R-1**: Snapshot diff of verdict report contents for THREE representative fixtures (one each from `plugin-kiln/tests/perf-kiln-report-issue/`, `plugin-wheel/tests/preprocess-substitution.bats` or similar, `plugin-kiln/tests/kiln-distill-basic/`) is byte-identical pre- vs. post-PRD (modulo timestamps, UUIDs, and absolute scratch paths). Delta = 0 lines, beyond the modulo-list.
- **SC-R-2**: Live-smoke gate (`bash plugin-kiln/tests/perf-kiln-report-issue/run.sh` end-to-end, ~3 min wall-clock) passes post-merge with no metrics regression. num_turns / wall-clock / api_ms all within ±10% of pre-merge medians.
- **SC-R-3**: Grep gate — `git grep -nF 'plugin-kiln/scripts/harness/kiln-test'` returns zero matches post-PRD (other than in archived state files / blockers / docs that intentionally reference the old path historically). All live-code references updated.

### Secondary (informational)

- **SC-R-4**: New `plugin-wheel/tests/<name>/run.sh` fixture exercises the runner directly with a synthetic fixture and passes (exit 0, last-line PASS summary).
- **SC-R-5**: Façade overhead measured via `time` is ≤50ms per invocation (NFR-R-6).
- **SC-R-6**: A wheel-only consumer pattern is documented in `plugin-wheel/docs/test-runner.md` showing how to call the runner from a non-kiln context.

### Process

- **SC-R-7**: NFR-R-5 satisfied — live-smoke gate is part of the PR description's verification checklist, run by the auditor before merge.

## Risks / Unknowns

- **R-R-1 (Hidden coupling between runner and kiln-specific paths)**: The runner might assume `plugin-kiln/scripts/...` paths exist or read from kiln-specific env vars. Mitigation: spec phase scans the runner for any `plugin-kiln/` literals and migrates them to either wheel-relative or args-passed paths.
- **R-R-2 (`/kiln:kiln-test` skill resolution discipline)**: The skill currently uses `${WORKFLOW_PLUGIN_DIR}` to resolve scripts. Pointing at a sibling plugin (`plugin-wheel/`) requires a different resolution pattern. Spec phase confirms the right shape (probably `${WORKFLOW_PLUGIN_DIR}/../plugin-wheel/scripts/harness/wheel-test-runner.sh` or via a wheel-side helper resolver).
- **R-R-3 (Snapshot-diff false positives)**: Verdict reports contain timestamps, UUIDs, and absolute paths that vary per run. The snapshot diff MUST exclude these — if the exclusion list is wrong, the diff fires false-positive and blocks the PR. Mitigation: spec phase pins the exact exclusion regex.
- **R-R-4 (Substrate-gap recurrence — the parent goal's overarching risk)**: This is the FIRST extraction in the wheel-as-plugin-agnostic-infra parent. If it hits unexpected friction, the entire parent goal is suspect. Mitigation: ship this PRD on its own; gather data; only then commit to items #2-#4.

## Assumptions

- The runner's current dependencies (`claude` CLI on PATH, `jq`, `python3`, bash 5.x, POSIX utilities) are all wheel-acceptable. High confidence — wheel already requires these.
- No external consumer outside kiln currently calls `kiln-test.sh` directly. High confidence — `git grep` for that path returns only kiln-internal references.
- The `/kiln:kiln-test` SKILL.md uses a script-resolution pattern that can be retargeted at a sibling plugin without architectural surgery. Spec phase confirms; if not, a thin wheel-side helper resolver is straightforward.
- The 50ms façade-overhead budget (NFR-R-6) is achievable with one extra script-invocation hop. High confidence — script invocation overhead is sub-millisecond.

## Open Questions

- **OQ-R-1 (BLOCKING — must be answered in spec phase)**: What is the exact script-resolution pattern that lets `/kiln:kiln-test` (in plugin-kiln) call into `wheel-test-runner.sh` (in plugin-wheel) reliably across consumer-install scenarios? Three candidates: (a) `${WORKFLOW_PLUGIN_DIR}/../plugin-wheel/scripts/...` (relative to kiln's install dir), (b) wheel-side resolver helper that any plugin can source (`wheel-resolve-runner.sh`), (c) hard-coded find-in-cache fallback. Spec phase picks one and pins the contract.
- **OQ-R-2**: Should the new wheel-side runner be `wheel-test-runner.sh` (descriptive) or just `test-runner.sh` (location implies plugin)? Bikeshed-y but worth pinning. Default: `wheel-test-runner.sh`.
- **OQ-R-3**: The verdict report format reference says "`.kiln/logs/kiln-test-<uuid>.md`" — this lives in the user's repo, not kiln's plugin dir. Stays unchanged regardless of where the runner lives. Confirmed — but worth flagging: the PATH PREFIX `kiln-test-` becomes a back-compat fossil (logs are named after the historic skill, not the new runner location). Acceptable.

## Pipeline guidance

This wants the full `/kiln:kiln-build-prd` pipeline, but the team can be small — single implementer, no QA engineer (no visual surface), one auditor. Same shape as PR #168 but even smaller scope.

- **Specifier** produces spec + plan + interface contracts (script-resolution pattern from OQ-R-1, snapshot-diff exclusion regex from R-R-3, verdict-report path discipline) + tasks. Resolves OQ-R-1 first as a blocking research task.
- **Researcher (lightweight)** captures the pre-PRD baseline for the three representative-fixture snapshot-diff comparison (SC-R-1) AND for the perf-kiln-report-issue live-smoke metrics envelope (SC-R-2). Without this, the headline metrics are unmeasurable. Per the new §1.5 Baseline Checkpoint rule from issue #170 + #167 PI-3 + #169 PI-3 — the specifier MUST reconcile thresholds against observed reality before implementer dispatch.
- **Single implementer** — pure relocation work. Per the new §Implementer Prompt — Test Substrate Hierarchy: this is tier-2 fixture territory (`run.sh`-only pattern, direct `bash run.sh` invocation acceptable per shipped substrate carveout). Implementer cites exit code + PASS summary in friction note.
- **No qa-engineer** (no visual surface).
- **Auditor** verifies (a) snapshot-diff byte-identical for 3 fixtures, (b) live-smoke gate passes, (c) grep gate clean, (d) atomic shipment in one commit/PR, (e) façade overhead ≤50ms. Per the new §Auditor Prompt — Live-Substrate-First Rule: the auditor MUST run `bash plugin-kiln/tests/perf-kiln-report-issue/run.sh` (the proven substrate) — NOT a structural surrogate.
- **Retrospective** analyzes whether the new prompt rules from issue #170 fix (substrate-hierarchy + live-substrate-first + baseline-first) were absorbed cleanly OR whether the next pipeline still has friction in those areas. Cross-references issues #167, #169, #170 for direct comparison.
