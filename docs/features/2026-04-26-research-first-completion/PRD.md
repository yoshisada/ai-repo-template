---
derived_from:
  - .kiln/roadmap/items/2026-04-24-research-first-build-prd-wiring.md
  - .kiln/roadmap/items/2026-04-24-research-first-classifier-inference.md
  - .kiln/roadmap/items/2026-04-24-research-first-phase-complete-criterion.md
distilled_date: 2026-04-26
theme: research-first-completion
---
# Feature PRD: Research-first completion — PRD-driven routing + classifier inference + E2E gate

**Date**: 2026-04-26
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)

## Background

The `09-research-first` phase is now five items deep. The runner infrastructure, per-axis direction gate, time + cost axes, fixture-synthesizer agent, and output-quality judge agent have all shipped (PRs #176, #178, #182). What's left is the integration layer that makes the whole thing visible to the maintainer in their normal workflow. Without this PRD, the phase remains plumbing nobody invokes.

Recently the roadmap surfaced these items in the **09-research-first** phase: `2026-04-24-research-first-build-prd-wiring` (feature), `2026-04-24-research-first-classifier-inference` (feature), `2026-04-24-research-first-phase-complete-criterion` (goal). The first defines the user-facing integration: schema extensions to `needs_research:` / `empirical_quality:` / `fixture_corpus:` across the four intake surfaces, `/kiln:kiln-distill` propagation of the research block from source into PRD, and `/kiln:kiln-build-prd` auto-routing to the research-first pipeline variant when it detects `needs_research: true` in PRD frontmatter. The second extends the coached-capture classifiers to detect comparative-improvement signal words and propose the research block at capture time so maintainers don't have to remember to declare it. The third — the lone `kind: goal` item in the phase — defines what "phase complete" actually means: at least one PRD has shipped end-to-end through the research-first pipeline including a deliberate regression scenario that the gate caught.

These three items are tightly coupled. Step 7 depends on step 6 (the inferred field is meaningless without the pipeline wiring that reads it). The goal validates both 6 and 7 end-to-end. Bundling them in one PRD keeps the integration coherent — schema, propagation, routing, classifier, and the E2E proof land together or not at all.

### Source Issues

| # | Source Entry | Source | Type | GitHub Issue | Severity / Area |
|---|--------------|--------|------|--------------|------------------|
| 1 | [Research-first step 6 — wire into kiln-build-prd via needs_research source-artifact field](../../../.kiln/roadmap/items/2026-04-24-research-first-build-prd-wiring.md) | .kiln/roadmap/ | item | — | feature / phase:09-research-first |
| 2 | [Research-first step 7 — classifier infers needs_research from capture description](../../../.kiln/roadmap/items/2026-04-24-research-first-classifier-inference.md) | .kiln/roadmap/ | item | — | feature / phase:09-research-first |
| 3 | [Research-first phase complete — full workflow exercised end-to-end in a test repo](../../../.kiln/roadmap/items/2026-04-24-research-first-phase-complete-criterion.md) | .kiln/roadmap/ | item | — | goal / phase:09-research-first |

## Implementation Hints

Schema additions across three intake surfaces:

  .kiln/roadmap/items/*.md       (item frontmatter)
  .kiln/issues/*.md              (issue frontmatter)
  .kiln/feedback/*.md            (feedback frontmatter)
  docs/features/<slug>/PRD.md    (PRD frontmatter — propagated from source)

New optional fields (all source schemas + PRD schema):

  needs_research: true | false           # presence alone does not enable; requires true
  empirical_quality:
    - metric: tokens | cost | time | accuracy | output_quality
      direction: lower | higher | equal_or_better
      priority: primary | secondary
  fixture_corpus: synthesized | declared | promoted
  fixture_corpus_path: <path>            # required when fixture_corpus=declared or promoted
  promote_synthesized: true | false      # default false; see step 4
  excluded_fixtures:                     # optional escape hatch per step 2
    - path: <fixture-path>
      reason: <string>

Validator updates: add to `validate-item-frontmatter.sh`, the issue validator (if it exists —
check plugin-kiln/scripts/issues/), the feedback validator (similar), and ensure distill
propagates all research keys verbatim into the generated PRD frontmatter.

`/kiln:kiln-distill` changes:
  - If ANY source declares needs_research=true, the generated PRD inherits needs_research=true
    and merges empirical_quality[] axes across sources. Conflicting direction on the same axis
    → surface as a distill ambiguity, prompt human to resolve (confirm-never-silent).

`/kiln:kiln-build-prd` changes:
  - Read PRD frontmatter. If needs_research=true, activate the research-first variant pipeline
    phase between /tasks and /implement:

      specify → plan (fixture synthesis if declared)
            → tasks → establish-baseline (run baseline plugin-dir against corpus)
            → implement-in-worktree
            → measure-candidate (run candidate against same corpus)
            → gate (per-axis direction enforcement, step 2)
            → [fail → halt, surface report | pass → continue]
            → audit → PR

  - Research report attached to PR description automatically.

This is the user-facing step. Everything before it is infrastructure; this is the item that
makes the feature *show up* in the maintainer's workflow.

*(from: `2026-04-24-research-first-build-prd-wiring`)*

Extend `plugin-kiln/scripts/roadmap/classify-description.sh` (and the sibling classifiers for
issue + feedback) to detect comparative-improvement signals and propose `needs_research: true`
plus a best-guess axis set in the coached-capture interview:

  Signal words: "faster", "slower", "cheaper", "more expensive", "reduce", "increase",
                "optimize", "efficient", "compare to", "versus", "vs ", "better than",
                "regression", "improve", "degradation"
  Axis inference from signal:
    - "faster" / "slower" / "latency" → time
    - "cheaper" / "tokens" / "cost" / "expensive" → cost + tokens
    - "smaller" / "concise" / "verbose" → tokens (usually output)
    - "accurate" / "wrong" / "regression" → accuracy (already implicit; still worth surfacing)
    - "clearer" / "better-structured" / "more actionable" → output_quality (flag warning about
                judge-drift risk from step 5; don't default-enable)

Coached-capture affordance: render the proposed fields with rationale, user accepts/tweaks/rejects:

  Q: Does this need research?
     Proposed: needs_research: true
               empirical_quality:
                 - metric: tokens
                   direction: lower
                   priority: primary
     Why: description says "reduce token usage" — matches tokens-axis signal
     [accept / tweak <value> / reject / skip / accept-all]
     >

False-negatives (we miss a research-needing change) are recoverable — maintainer can hand-add
the frontmatter later. False-positives (we incorrectly propose research for a non-comparative
change) are also recoverable — maintainer rejects the proposal. Low-stakes inference; this is
ergonomics polish.

*(from: `2026-04-24-research-first-classifier-inference`)*

## Problem Statement

Five items in `09-research-first` have shipped, but a maintainer running `/kiln:kiln-build-prd` against any PRD today gets the same pipeline they always have — no research routing, no baseline measurement, no per-axis gate. The infrastructure exists; it has no entry point. Worse, even if a maintainer manually authored a research block in PRD frontmatter, distill wouldn't propagate it from the source artifact, and build-prd wouldn't read it. The integration is the missing layer.

Beneath that integration sit two specific gaps: **discoverability** (maintainers won't remember to declare `needs_research: true` when they capture a comparative-improvement idea), and **provability** (the phase can claim "complete" only when the entire workflow has been exercised end-to-end at least once, including the negative case where the gate catches a regressing candidate). The classifier-inference handles the discoverability gap by detecting signal words at capture time and proposing the research block via the existing coached-capture affordance. The phase-complete goal handles the provability gap by gating phase status on a faked-test E2E walkthrough that exercises both happy and regression scenarios.

## Goals

- **Schema extensions land cleanly** — all four intake surfaces (item / issue / feedback / PRD frontmatter) accept the new optional fields without breaking any existing artifact. Validators are additive.
- **`/kiln:kiln-distill` propagates the research block** from any source that declares it into the generated PRD frontmatter. Conflicting axis declarations across sources surface a confirm-never-silent ambiguity prompt.
- **`/kiln:kiln-build-prd` auto-routes** to the research-first pipeline variant when it detects `needs_research: true` in PRD frontmatter. No new command, no user flag.
- **Capture-time inference** — the coached-capture interview proposes `needs_research: true` + a best-guess axis set when the description contains comparative-improvement signal words. Maintainer accepts / tweaks / rejects; no imposition.
- **Phase complete** — at least one PRD has shipped end-to-end through the research-first variant in a faked test repo, including a regression scenario that the gate catches.

## Non-Goals

- **Real consumer-project E2E test** — a faked test in a temp dir suffices per the phase-complete-criterion item. Real-world adoption is post-phase work.
- **ML-classifier inference** — signal-word matching with maintainer veto is sufficient. An ML classifier is overkill at proposal-grade confidence.
- **Backward-incompatible schema changes** — all new fields are optional, default-off. Existing items / issues / feedback / PRDs continue to work unchanged.
- **Auto-merging the research block at distill time** — conflicting axis declarations across sources REQUIRE a human prompt. We do not silently pick one.
- **Routing on flags** — `/kiln:kiln-build-prd --research` (or similar) is explicitly NOT added. Routing is PRD-frontmatter-driven only.
- **Replacing the existing pipeline** — the research-first variant is opt-in per PRD via `needs_research: true`. PRDs that don't declare it run the unchanged pipeline.

## Requirements

### Functional Requirements

#### Theme: schema extensions + distill propagation (FR-001 — FR-008)

**FR-001 (from: `.kiln/roadmap/items/2026-04-24-research-first-build-prd-wiring.md`)**: Extend the item frontmatter schema (validated by `plugin-kiln/scripts/roadmap/validate-item-frontmatter.sh`) to accept optional fields `needs_research: bool`, `empirical_quality: [{metric, direction, priority}]`, `fixture_corpus: enum(synthesized|declared|promoted)`, `fixture_corpus_path: string`, `promote_synthesized: bool`, `excluded_fixtures: [{path, reason}]`. All fields default-off — absence preserves existing behavior.

**FR-002 (from: `.kiln/roadmap/items/2026-04-24-research-first-build-prd-wiring.md`)**: Extend the issue and feedback frontmatter validators with the same optional fields. If no issue/feedback validator currently exists, create one and add it to the existing validation flow (or document the absence as a known gap if neither is in scope this PR).

**FR-003 (from: `.kiln/roadmap/items/2026-04-24-research-first-build-prd-wiring.md`)**: Validation rules: `empirical_quality[]` requires `metric` and `direction` per entry; `priority` defaults to `secondary`. `fixture_corpus_path` is REQUIRED when `fixture_corpus: declared` or `fixture_corpus: promoted`; absent otherwise. `excluded_fixtures[]` requires `path` and `reason` per entry.

**FR-004 (from: `.kiln/roadmap/items/2026-04-24-research-first-build-prd-wiring.md`)**: Extend the PRD frontmatter contract (`prd-derived-from-frontmatter` spec) to permit the same set of optional research-block keys AFTER the existing three keys (`derived_from`, `distilled_date`, `theme`). Key order: `derived_from`, `distilled_date`, `theme`, `needs_research`, `empirical_quality`, `fixture_corpus`, `fixture_corpus_path`, `promote_synthesized`, `excluded_fixtures`. Backward compatible: PRDs without the research block still parse cleanly.

**FR-005 (from: `.kiln/roadmap/items/2026-04-24-research-first-build-prd-wiring.md`)**: `/kiln:kiln-distill` propagation — when ANY selected source (feedback / item / issue) declares `needs_research: true`, the generated PRD inherits `needs_research: true`. The PRD's `empirical_quality[]` is the union of axes declared across all selected sources, deduplicated by `metric`.

**FR-006 (from: `.kiln/roadmap/items/2026-04-24-research-first-build-prd-wiring.md`)**: Conflict resolution — if two or more selected sources declare the SAME `metric` with DIFFERENT `direction` values, distill MUST surface a confirm-never-silent ambiguity prompt naming both source paths and the conflicting axes. The user picks one direction or specifies a third. Distill MUST NOT silently merge.

**FR-007 (from: `.kiln/roadmap/items/2026-04-24-research-first-build-prd-wiring.md`)**: `/kiln:kiln-distill` propagates `fixture_corpus`, `fixture_corpus_path`, `promote_synthesized`, and `excluded_fixtures[]` from the union of source artifacts into the PRD frontmatter VERBATIM (no synthesis, no inference).

**FR-008 (from: `.kiln/roadmap/items/2026-04-24-research-first-build-prd-wiring.md`)**: When NO selected source declares `needs_research: true`, distill emits the PRD frontmatter unchanged from current behavior (three keys: `derived_from`, `distilled_date`, `theme`). Byte-identical to pre-research-first distill output (NFR-005).

#### Theme: build-prd routing (FR-009 — FR-012)

**FR-009 (from: `.kiln/roadmap/items/2026-04-24-research-first-build-prd-wiring.md`)**: `/kiln:kiln-build-prd` reads the PRD frontmatter on entry. If `needs_research: true`, route to the research-first variant pipeline. Otherwise, route to the existing standard pipeline.

**FR-010 (from: `.kiln/roadmap/items/2026-04-24-research-first-build-prd-wiring.md`)**: The research-first variant pipeline executes these steps in order between `/tasks` and `/implement` (per item-source spec): `establish-baseline` (run baseline plugin-dir against corpus, capture metrics), `implement-in-worktree` (the candidate), `measure-candidate` (same corpus, candidate plugin-dir), `gate` (per-axis direction enforcement from `2026-04-24-research-first-per-axis-gate-and-rigor`), then continue to `audit → PR` only if every axis passes.

**FR-011 (from: `.kiln/roadmap/items/2026-04-24-research-first-build-prd-wiring.md`)**: On gate fail, the research-first variant halts the pipeline and surfaces the per-axis report verbatim — fixture-by-fixture, axis-by-axis. The PR is NOT created. The maintainer sees what regressed and can revise the candidate.

**FR-012 (from: `.kiln/roadmap/items/2026-04-24-research-first-build-prd-wiring.md`)**: On gate pass, the auditor includes the research report path (`.kiln/logs/research-<uuid>.md`) in the PR body. Per-axis pass status is rendered in a table beneath a `## Research Results` heading in the PR description.

#### Theme: classifier inference (FR-013 — FR-016)

**FR-013 (from: `.kiln/roadmap/items/2026-04-24-research-first-classifier-inference.md`)**: Extend `plugin-kiln/scripts/roadmap/classify-description.sh` (and sibling classifiers for issue + feedback if they exist) with a comparative-improvement signal-word detector. Word list: `faster, slower, cheaper, "more expensive", reduce, increase, optimize, efficient, "compare to", versus, "vs ", "better than", regression, improve, degradation`. Match is case-insensitive whole-word.

**FR-014 (from: `.kiln/roadmap/items/2026-04-24-research-first-classifier-inference.md`)**: When a signal word matches, the classifier emits a research-block proposal with axes inferred from the signal:
- `faster | slower | latency` → `metric: time, direction: lower`
- `cheaper | tokens | cost | expensive` → `metric: cost, direction: lower` AND `metric: tokens, direction: lower`
- `smaller | concise | verbose` → `metric: tokens, direction: lower`
- `accurate | wrong | regression` → `metric: accuracy, direction: equal_or_better`
- `clearer | "better-structured" | "more actionable"` → `metric: output_quality, direction: equal_or_better` (with judge-drift warning per FR-016)

**FR-015 (from: `.kiln/roadmap/items/2026-04-24-research-first-classifier-inference.md`)**: The coached-capture interview renders the inferred research block as a single accept/tweak/reject question following the existing coached-capture template (matches `coach-driven-capture-ergonomics` FR-004 §5.0 contract). The proposed answer is the inferred block; the rationale cites the matched signal word verbatim. User input is parsed per the existing §5.0a response parser.

**FR-016 (from: `.kiln/roadmap/items/2026-04-24-research-first-classifier-inference.md`)**: When the inferred axis set includes `output_quality`, the rationale line MUST include a one-line warning: "(`output_quality` enables the judge-agent — see `2026-04-24-research-first-output-quality-judge.md` for drift-risk caveats)". Maintainer can still accept; the warning is informational.

#### Theme: phase-complete E2E test (FR-017 — FR-020)

**FR-017 (from: `.kiln/roadmap/items/2026-04-24-research-first-phase-complete-criterion.md`)**: A faked-test fixture under `plugin-kiln/tests/research-first-e2e/` exercises the full research-first workflow end-to-end. The fixture: (a) scaffolds a temp-dir test repo with mocked `kiln-init`, (b) creates a roadmap item declaring `needs_research: true` with at least one `empirical_quality[]` axis, (c) runs `/kiln:kiln-distill` and asserts the PRD frontmatter inherits the research block, (d) runs `/kiln:kiln-build-prd` and asserts the research-first variant is invoked.

**FR-018 (from: `.kiln/roadmap/items/2026-04-24-research-first-phase-complete-criterion.md`)**: The E2E fixture MUST exercise BOTH paths:
- **Happy path**: a candidate that holds-the-line on every declared axis. Assertion: pipeline proceeds to PR creation, research report attached.
- **Regression path**: a candidate deliberately worse on at least one axis. Assertion: pipeline halts BEFORE PR creation, gate-fail report surfaced naming the regressing axis + fixture.

Without both, the phase has only proven the happy path. The regression case is the load-bearing assertion.

**FR-019 (from: `.kiln/roadmap/items/2026-04-24-research-first-phase-complete-criterion.md`)**: The E2E fixture is wired into the `/kiln:kiln-test` harness (or runs via direct `bash plugin-kiln/tests/research-first-e2e/run.sh` with PASS-cite fallback per the substrate-hierarchy rule from issue #181 PI-2). The fixture's exit code + last-line PASS summary serve as the canonical evidence for SC-005.

**FR-020 (from: `.kiln/roadmap/items/2026-04-24-research-first-phase-complete-criterion.md`)**: Phase-complete declaration — only after BOTH paths in the E2E fixture pass AND a follow-up commit flips the phase 09-research-first item-statuses to `shipped` (per the auto-flip-on-merge gap captured in `.kiln/issues/2026-04-25-build-prd-no-auto-flip-item-state-on-merge.md`), the maintainer may run `/kiln:kiln-roadmap --phase complete 09-research-first`.

### Non-Functional Requirements

**NFR-001 (Backward compatibility)**: Every existing artifact (item, issue, feedback, PRD) without the new research-block fields MUST continue to validate and propagate cleanly. Validators are additive; missing-field tolerance is the default. NO existing PRD under `docs/features/` requires editing for this PRD to ship.

**NFR-002 (Routing default-safety)**: PRDs without `needs_research: true` route through the existing `/kiln:kiln-build-prd` pipeline byte-identically. Add this as a smoke-test fixture: pre-research-first PRD shipped before this PR + post-merge re-run produces the same pipeline structure.

**NFR-003 (Distill determinism)**: When ANY source declares `needs_research: true`, the propagated PRD frontmatter is deterministic — re-running distill on unchanged inputs produces byte-identical research-block content. Axis ordering is stable: `metric` ASC alphabetical, ties break on `direction` ASC.

**NFR-004 (Conflict-prompt clarity)**: The FR-006 conflict prompt MUST name both source paths AND the conflicting `(metric, direction)` pairs. Bad shape: "axes conflict, please resolve." Good shape: "feedback `2026-04-15-foo.md` declares `metric: tokens, direction: lower` but item `2026-04-20-bar.md` declares `metric: tokens, direction: equal_or_better`. Pick one direction or specify a third."

**NFR-005 (Pre-research-first byte-compat)**: Distill of a backlog where NO source declares `needs_research: true` produces frontmatter byte-identical to pre-research-first distill output. The FR-008 fallback is the determinism hook.

**NFR-006 (Classifier false-positive recovery)**: A maintainer rejecting the inferred research-block proposal MUST result in the captured artifact having NO research-block frontmatter (not "research block with all fields empty"). False-positive recovery is "the field doesn't exist," not "the field exists but is null."

### Source Roadmap Items

| Item ID | Kind | Notes |
|---------|------|-------|
| `2026-04-24-research-first-build-prd-wiring` | feature | FR-001..FR-012 — schema + distill propagation + build-prd routing |
| `2026-04-24-research-first-classifier-inference` | feature | FR-013..FR-016 — capture-time signal-word detection + coached proposal |
| `2026-04-24-research-first-phase-complete-criterion` | goal | FR-017..FR-020 — E2E fixture + phase-complete declaration |

## User Stories

- **As a maintainer capturing a comparative-improvement idea**, I run `/kiln:kiln-roadmap "make claude-md-audit cheaper"`. The classifier detects "cheaper", proposes `needs_research: true, empirical_quality: [{metric: tokens, direction: lower, priority: primary}, {metric: cost, direction: lower, priority: primary}]`, cites "matched signal word: cheaper". I accept. The roadmap item lands with the research block in frontmatter.

- **As a maintainer running `/kiln:kiln-distill`**, I bundle the above item into a PRD. Distill propagates the research block into the PRD frontmatter verbatim. I review the PRD, decide it's right, and run `/kiln:kiln-build-prd`. Auto-routes to the research-first variant. Baseline measured, candidate implemented + measured, gate evaluates each axis. Tokens dropped 22%, cost dropped 18% — both axes pass, no regression on accuracy. PR created with the research report attached.

- **As a maintainer with a regressing candidate**, the same flow runs but the gate detects tokens went UP 5% on 2 of 12 fixtures. Pipeline halts before PR creation. I see the per-fixture report, revise the implementation, re-run. This time tokens dropped 22% on all fixtures. Pipeline proceeds.

- **As a maintainer closing the phase**, I run the E2E fixture (both happy + regression paths) on a faked test repo. Both pass. I commit the phase-complete declaration. `/kiln:kiln-roadmap --phase complete 09-research-first`.

## Success Criteria

- **SC-001**: A backlog item or issue captured via `/kiln:kiln-roadmap` or `/kiln:kiln-report-issue` containing the word "cheaper" or "faster" produces a coached-capture proposal with `needs_research: true` and at least one matching axis. Verified by classifier-trigger fixture under `plugin-kiln/tests/classifier-research-inference/`.

- **SC-002**: `/kiln:kiln-distill` against a backlog where one item declares `needs_research: true` produces a PRD whose frontmatter contains the propagated research block (matches the union semantics of FR-005 + FR-007). Verified by distill-propagation fixture.

- **SC-003**: `/kiln:kiln-build-prd` on a PRD with `needs_research: true` invokes the research-first variant pipeline (baseline → implement → measure → gate). Verified by build-prd-routing fixture.

- **SC-004**: `/kiln:kiln-build-prd` on a PRD without `needs_research: true` invokes the standard pipeline byte-identically to pre-research-first behavior (NFR-002). Verified by build-prd-default-routing regression fixture.

- **SC-005**: The E2E fixture at `plugin-kiln/tests/research-first-e2e/` exercises both happy and regression paths and exits 0. Direct evidence: `bash plugin-kiln/tests/research-first-e2e/run.sh` last line includes `PASS` and exit 0; the regression sub-path produces `gate fail` text in the test log.

- **SC-006 (FR-006 enforcement)**: The conflict prompt MUST fire when two sources declare conflicting `direction` for the same `metric` — verified by a distill-conflict fixture that asserts the prompt text contains both source paths AND both `direction` values, AND that distill exits non-zero without writing the PRD.

- **SC-007**: Re-distill against the same conflict-free backlog produces byte-identical PRD frontmatter (NFR-003 determinism — `LC_ALL=C sort` on axis ordering).

## Tech Stack

Inherited from parent kiln plugin — no new dependencies:
- **Bash 5.x + `jq` + `awk` + `python3`** — frontmatter parsers, validators, classifier signal-word detection
- **YAML frontmatter** — schema extension surface
- **Claude Code agent runtime** — for `/kiln:kiln-build-prd` orchestration (existing)
- **`/kiln:kiln-test` harness** — for FR-019 fixture wiring (or `run.sh`-only fallback per the substrate-hierarchy rule)

No new runtime deps.

## Risks & Open Questions

- **Distill conflict prompt usability** — if 4 sources each declare a different direction for the same axis, the prompt becomes a soup. The FR-006 contract names "two or more" but doesn't cap. **Mitigation**: render conflicts grouped by `metric`, one block per metric, all conflicting `(source, direction)` pairs visible. If the soup gets bad in practice, add an "accept-all-as-equal_or_better" escape hatch in a follow-on PR.

- **Classifier false positives** — a maintainer mentioning "this should be cheaper to ship" gets a runtime-cost research-block proposal. They reject; recovery is fine (NFR-006). But the friction of one extra prompt per false positive accumulates. **Mitigation**: ship the broader signal set behind a config flag (`.kiln/classifier-config.yaml::research_inference: high-signal-only` defaults to broad; can flip to narrow). Re-evaluate after first 10 real captures.

- **E2E fixture brittleness** — the fixture mocks `kiln-init` and scripts the full pipeline. As the pipeline evolves (e.g., new auditor rules land), the mock can drift. **Mitigation**: the fixture's PASS criterion is functional ("pipeline halts on regression candidate"), not structural ("output exactly matches X"). Rebuild the mock if structure shifts; the assertion stays stable.

- **Open question** — should the classifier learn from rejected proposals? E.g., maintainer rejects 5 "cheaper" proposals → reduce the weight of "cheaper" as a signal. Defer; signal-word matching is stateless by design. ML feedback loops are post-phase work.

- **Open question** — does `fixture_corpus: declared` require absolute or repo-relative paths? Repo-relative is more portable; absolute is unambiguous. **Default**: repo-relative; validator rejects absolute paths in `fixture_corpus_path:`. Document this in the FR-001 schema.

- **Open question** — should the research-first variant emit a research-failure GitHub issue automatically when the gate halts the pipeline? It would help maintainers track regressions across runs. Defer; the per-axis report on stdout + halted PR creation is sufficient for V1. Add issue-emission in a follow-on if maintainers ask for it.
