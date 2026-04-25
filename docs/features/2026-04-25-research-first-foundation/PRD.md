---
derived_from:
  - .kiln/roadmap/items/2026-04-24-research-first-fixture-format-mvp.md
distilled_date: 2026-04-25
theme: research-first-foundation
---
# Feature PRD: Research-First Foundation — Fixture Corpus + Baseline-vs-Candidate Runner MVP

**Date**: 2026-04-25
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)

## Background

Recently the roadmap surfaced these items in the **09-research-first** phase: `2026-04-24-research-first-fixture-format-mvp` (feature). This is step 1 of a seven-step phase that introduces empirical, fixture-driven feasibility gating for changes whose value lives in measurable comparison (token reduction, latency, accuracy regressions, output quality). The phase exists because the kiln workflow has had no way to reject a "ship it" verdict when the candidate change is *worse* than baseline on the dimension the change was supposed to improve — every other gate (spec, plan, audit, smoke test) is a structural correctness check, not a comparative one.

The foundation step is the substrate every later step builds on. Steps 2 and 3 (per-axis direction gate + time/cost axes) extend its metric collection. Step 4 (fixture synthesizer) generates inputs for it. Step 5 (output-quality judge) plugs in as another axis. Steps 6 and 7 wire the whole thing into `/kiln:kiln-build-prd` and propose `needs_research: true` from capture descriptions. None of those can land before this one ships.

The substrate already exists: `kiln-test` runs `claude --print --verbose --input-format=stream-json ... --plugin-dir <dir>` against fixture inputs and asserts pass/fail. This PRD extends that substrate to accept TWO `--plugin-dir` paths per run (baseline + candidate), captures per-fixture metrics from each run, and emits a comparative report. v1 ships only the two cheapest axes — accuracy (reuse `kiln-test`'s existing pass/fail verdict) and tokens (input + output + cached, parsed from stream-json). Everything richer (per-axis direction, time, cost, judge-driven output quality, fixture synthesis, build-prd wiring) is explicitly deferred to later steps in this phase.

### Source Issues

| # | Source Entry | Source | Type | GitHub Issue | Severity / Area |
|---|--------------|--------|------|--------------|------------------|
| 1 | [Research-first step 1 — fixture corpus format + baseline-vs-candidate runner MVP](../../../.kiln/roadmap/items/2026-04-24-research-first-fixture-format-mvp.md) | .kiln/roadmap/ | item | — | feature / phase:09-research-first |

## Implementation Hints

Extend kiln-test's headless substrate (`claude --print --verbose --input-format=stream-json ... --plugin-dir`)
to accept TWO plugin-dir paths per run: baseline and candidate. Run the same fixture against both and
capture per-run metrics (input tokens, output tokens, cached tokens, assertion pass/fail verdict).

Fixture corpus directory convention:

  plugin-<name>/fixtures/<skill>/corpus/
    ├── 001-<slug>/
    │   ├── input.json        # stream-json input replayed to the subprocess
    │   ├── expected.json     # assertion config (accuracy verdict reuses kiln-test logic)
    │   └── metadata.yaml     # axes covered, notes on why this fixture exists
    ├── 002-<slug>/
    ...

v1 ships TWO axes only: accuracy (reuse kiln-test's pass/fail verdict) and tokens
(input + output + cached, per fixture). Hardcoded strict gate: ANY fixture regressing on
accuracy OR tokens fails the run. No per-axis `direction:` logic yet (that's step 2).
No time / cost / output_quality yet (steps 3 and 5). No synthesizer (step 4).
Declared-corpus only — the PRD declares `fixture_corpus:` pointing at a directory.

Output: `.kiln/logs/research-<uuid>.md` with:
  - per-fixture row: baseline accuracy, candidate accuracy, baseline tokens, candidate tokens, delta, verdict
  - aggregate summary: N fixtures, M regressions, overall verdict

Inherits design notes from `.kiln/roadmap/items/2026-04-24-skill-ab-harness-wheel-workflow.md`
— that item is the origin idea; this step is its concrete MVP.

*(from: `2026-04-24-research-first-fixture-format-mvp`)*

## Problem Statement

Today, a change that "should reduce tokens" or "should be faster" ships if it passes structural gates — there is no automated check that the change actually moved the metric the right direction on representative inputs. Reviewers either eyeball the diff and trust the description, or they run a one-off ad-hoc comparison that vanishes after the PR merges. Two failure modes follow: (1) the candidate ships *worse* than baseline on its claimed axis and nobody notices until a downstream report flags it, and (2) genuine improvements ship without evidence, making future regressions invisible because there's no committed baseline to compare against. The research-first phase fixes both, but every later step in the phase is unbuildable without a substrate that can run the same input against two plugin-dirs and report comparative metrics. That substrate is this PRD.

## Goals

- Extend the existing `kiln-test` headless substrate to accept two `--plugin-dir` paths per fixture run (baseline + candidate) without forking the runner.
- Define a committed-on-disk fixture-corpus directory convention (`plugin-<name>/fixtures/<skill>/corpus/<NNN-slug>/{input.json,expected.json,metadata.yaml}`) so corpora are reviewable, diffable, and survive PR merges.
- Capture per-fixture metrics from both runs: assertion pass/fail (accuracy) + input/output/cached tokens parsed from stream-json. Emit a comparative report at `.kiln/logs/research-<uuid>.md`.
- Ship a strict gate (ANY regression on accuracy OR tokens fails the run) so the very first PRD that opts into research-first gets a meaningful verdict, even before per-axis direction logic lands in step 2.
- Keep the v1 surface intentionally narrow — declared-corpus only, no synthesizer, no time/cost axes, no judge — so this PRD is shippable in one feature-sized pipeline pass.

## Non-Goals

- **No per-axis `direction:` logic** — step 2 (`research-first-per-axis-gate-and-rigor`) replaces the strict gate with declarative direction enforcement.
- **No time or cost axes** — step 3 (`research-first-time-and-cost-axes`) adds those.
- **No synthesized fixtures** — step 4 (`research-first-fixture-synthesizer`) introduces the agent-at-plan-time pattern.
- **No output-quality judge** — step 5 (`research-first-output-quality-judge`) introduces the rubric-driven judge agent.
- **No `/kiln:kiln-build-prd` wiring** — step 6 (`research-first-build-prd-wiring`) reads `needs_research:` from PRD frontmatter and activates the research-first variant pipeline. v1 of this substrate is callable manually; the user-facing surface comes later.
- **No classifier inference of `needs_research:`** — step 7 (`research-first-classifier-inference`) adds that ergonomics polish.
- **No promoted-fixture pool** — `promote_synthesized:` flag is meaningless without a synthesizer; defer to step 4.

## Requirements

### Functional Requirements

- **FR-001** *(from: `2026-04-24-research-first-fixture-format-mvp`)* — The kiln-test runner MUST accept two `--plugin-dir` arguments per invocation (baseline and candidate). When two are passed, the same fixture input is replayed against each plugin-dir as separate subprocess invocations, and metrics are captured per-run. When only one `--plugin-dir` is passed, behavior is unchanged from current kiln-test.
- **FR-002** *(from: `2026-04-24-research-first-fixture-format-mvp`)* — Fixture corpora MUST live at the convention path `plugin-<name>/fixtures/<skill>/corpus/<NNN-slug>/` with three files per fixture: `input.json` (stream-json payload replayed verbatim), `expected.json` (assertion config consumed by the existing kiln-test verdict logic), and `metadata.yaml` (axes covered + why-this-fixture-exists prose).
- **FR-003** *(from: `2026-04-24-research-first-fixture-format-mvp`)* — The runner MUST capture, per fixture per plugin-dir: input tokens, output tokens, cached input tokens (parsed from the stream-json output), and the assertion pass/fail verdict from the existing kiln-test verdict logic.
- **FR-004** *(from: `2026-04-24-research-first-fixture-format-mvp`)* — The runner MUST emit a comparative report at `.kiln/logs/research-<uuid>.md` containing (a) one row per fixture with baseline+candidate accuracy, baseline+candidate tokens, delta, and per-fixture verdict; (b) an aggregate summary section with total fixtures, regression count, and overall run verdict.
- **FR-005** *(from: `2026-04-24-research-first-fixture-format-mvp`)* — The v1 gate MUST be a hardcoded strict gate: a fixture's per-fixture verdict is "regression" if candidate accuracy < baseline accuracy OR candidate total tokens > baseline total tokens; the run-level verdict is "fail" if any fixture is "regression". No tolerance tuning, no per-axis configuration in v1.
- **FR-006** *(from: `2026-04-24-research-first-fixture-format-mvp`)* — A PRD that wants to opt into research-first MUST declare `fixture_corpus: <path-to-corpus-dir>` in its frontmatter (declared-corpus only — no synthesizer, no promotion in v1). The runner reads this field to locate the fixture set.
- **FR-007** — The runner MUST be invokable as a standalone subcommand of the existing kiln-test CLI surface (e.g. `bash plugin-kiln/scripts/kiln-test/run.sh --baseline <dir> --candidate <dir> --corpus <dir>`); v1 does NOT require integration with `/kiln:kiln-build-prd`. This keeps the substrate independently testable before step 6 wires it into the pipeline.

### Non-Functional Requirements

- **NFR-001 — Determinism**: re-running the runner with identical baseline + candidate + corpus inputs MUST produce a per-fixture verdict that is identical except for token-count noise within ±2 tokens (acknowledging stream-json non-determinism). The report's overall verdict (pass/fail) MUST be stable across reruns.
- **NFR-002 — No fork of kiln-test**: the baseline-vs-candidate path MUST be implemented as an extension of the existing kiln-test runner, not a sibling fork. Shared verdict logic, stream-json parsing, and fixture-loading code paths stay single-sourced.
- **NFR-003 — Backward compatibility**: existing single-`--plugin-dir` kiln-test invocations (used by `/kiln:kiln-test`) MUST continue to work unchanged. Two-`--plugin-dir` mode is purely additive.
- **NFR-004 — Report locality**: the report MUST live under `.kiln/logs/` (gitignored by repo convention) so research runs don't pollute the working tree. Maintainers can copy the report into a PR description manually if they want it persisted.
- **NFR-005 — Readability**: the comparative report MUST be human-scannable in a terminal — markdown tables for per-fixture rows, a 5-line aggregate summary at the bottom, no JSON dumps in the body.

## User Stories

- **As a kiln maintainer planning a "reduce token usage" change**, I want to define a small fixture corpus once, then run baseline (main branch) vs. candidate (my branch) against it, so I get a verdict that tells me whether my change actually reduced tokens on representative inputs — instead of trusting the diff or running a one-off shell loop.
- **As a kiln maintainer reviewing a PR that claims "this is faster"**, I want to point the reviewer at a research report committed by the author, so I can see per-fixture deltas instead of asking the author to re-prove it.
- **As an early adopter of research-first**, I want to opt in by declaring `fixture_corpus:` in the PRD frontmatter and running the substrate manually, so I can use the gate before step 6 wires it into `/kiln:kiln-build-prd`.

## Success Criteria

- **SC-001** — A maintainer can construct a 3-fixture corpus under `plugin-<name>/fixtures/<skill>/corpus/`, invoke the runner with `--baseline`+`--candidate`+`--corpus`, and receive a `.kiln/logs/research-<uuid>.md` report in under 60s on the seed example (token-only axis, no live judge).
- **SC-002** — A deliberately-regressing candidate plugin-dir (one fixture's input crafted to produce more output tokens) MUST produce a "fail" overall verdict and identify the regressing fixture by name in the per-fixture row.
- **SC-003** — A non-regressing candidate plugin-dir (no diff vs baseline OR a strict improvement) MUST produce a "pass" overall verdict.
- **SC-004** — Existing `/kiln:kiln-test` invocations (single-`--plugin-dir`) continue to pass their existing test fixtures without modification (NFR-003 backward-compat anchor).
- **SC-005** — The substrate is documented in `plugin-kiln/scripts/kiln-test/README.md` (or equivalent) with a one-page how-to that a maintainer can follow without reading the runner source.

## Tech Stack

Inherited from kiln-test substrate: Bash 5.x for the runner shim, `jq` + `python3` (stdlib `json`) for stream-json parsing, the existing kiln-test verdict-extraction logic. No new runtime dependency. Subprocess invocations use the same `claude --print --verbose --input-format=stream-json ... --plugin-dir` shape kiln-test already drives.

## Risks & Open Questions

- **Stream-json token-field stability**: per-run input/output/cached token counts come from the stream-json envelope's usage record. If Anthropic changes the field shape, both kiln-test and this substrate break together — but the failure surface is loud (jq query returns null), not silent. Acceptable risk; flagged for the auditor's stale-pricing-style mtime check in step 3.
- **Cached-token bookkeeping**: tokens charged to cached input vs. fresh input differ in cost (step 3's concern), but in v1 we just sum them as "total tokens". A change that moves load between fresh and cached without changing the sum would not register as a regression in v1. Step 3 splits these axes; v1 is intentionally coarse.
- **Single-fixture concurrency**: v1 runs fixtures serially. A 50-fixture corpus on Opus may take minutes per axis. Parallelization is deferred — if maintainers complain, it's a follow-on item, not v1 scope.
- **No corpus-curation guidance**: a 1-fixture corpus passes-or-fails on a single example. We do not enforce a minimum count in v1 (step 2's `min_fixtures` rigor scaling does that). Maintainers can ship a 1-fixture corpus and get a verdict that means very little — that's fine for the substrate's role; quality enforcement lives one step down.
- **Report-uuid collision under concurrent invocations**: `research-<uuid>.md` uses a UUIDv4; collisions are vanishingly improbable but not zero. Acceptable for a logs-dir artifact.
- **Open question — fixture metadata enforcement**: should `metadata.yaml` be required or optional? v1 leans optional (the runner ignores it; it's for human reviewers). If step 4's synthesizer needs it as a corpus-level invariant, this becomes a step-4 concern.
