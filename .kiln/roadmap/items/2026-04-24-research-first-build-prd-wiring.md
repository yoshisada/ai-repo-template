---
id: 2026-04-24-research-first-build-prd-wiring
title: "Research-first step 6 — wire into kiln-build-prd via needs_research source-artifact field"
kind: feature
date: 2026-04-24
status: open
phase: 09-research-first
state: shipped
prd: docs/features/2026-04-26-research-first-completion/PRD.md
blast_radius: cross-cutting
review_cost: expert
context_cost: 4 sessions
depends_on:
  - 2026-04-24-research-first-fixture-format-mvp
  - 2026-04-24-research-first-per-axis-gate-and-rigor
  - 2026-04-24-research-first-time-and-cost-axes
implementation_hints: |
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
---

# Research-first step 6 — wire into kiln-build-prd via needs_research source-artifact field

## What

Add `needs_research:`, `empirical_quality:`, `fixture_corpus:`, and related fields to the roadmap-item / issue / feedback / PRD frontmatter schemas. `/kiln:kiln-distill` propagates the research block from source into PRD. `/kiln:kiln-build-prd` detects `needs_research: true` in PRD frontmatter and auto-routes to the research-first pipeline variant — no new command, no user flag.

## Why now

Steps 1-3 build the runner infrastructure and the gate; step 6 is where the maintainer actually interacts with it. Without this step, the whole phase exists as plumbing no one invokes. User preference is explicitly PRD-driven routing (2026-04-24 conversation, Q1 answer (c)) — "it should actually be more intelligent... add a field to items/issues/feedback that marks as needs research and the empirical quality we are looking for."

## Assumptions

- Frontmatter schema extensions don't break any existing items/issues/feedback — all new keys are optional and default-off. Validator changes are additive.
- Distill can resolve conflicting axis declarations across sources by surfacing an ambiguity prompt, matching the existing confirm-never-silent pattern in roadmap / distill skills.

## Hardest part

Distill multi-source axis merging. If feedback A says `direction: lower, metric: tokens` and feedback B says `direction: equal_or_better, metric: tokens` for the same PRD, there's no mechanically-correct merge. Must ask the human. Designing that prompt so it's clear and not annoying is the load-bearing UX work.

## Cheaper version

Skip distill propagation; require the maintainer to hand-add the research block to the PRD frontmatter after distill runs. Simpler to implement but defeats the "PRD-driven, intelligent, auto-routed" intent. Not worth shipping — the whole point of this step is the ergonomic integration.

## Dependencies

Depends on: step 1 (fixture-format-mvp), step 2 (per-axis gate), step 3 (time + cost axes). Optional on steps 4 (synthesizer — only if `fixture_corpus: synthesized` is used) and 5 (output-quality judge — only if that axis is declared).
