---
id: 2026-04-24-research-first-fixture-synthesizer
title: "Research-first step 4 — fixture-synthesizer agent at plan-time with human review gate"
kind: feature
date: 2026-04-24
status: open
phase: 09-research-first
state: planned
blast_radius: feature
review_cost: careful
context_cost: 3 sessions
depends_on:
  - 2026-04-24-research-first-fixture-format-mvp
implementation_hints: |
  A new agent type (`fixture-synthesizer`) spawned during `/plan` when the PRD declares
  `fixture_corpus: synthesized` (or `fixture_corpus: promoted` and the existing promoted pool
  has fewer fixtures than the blast_radius minimum). Takes as input:

    - The skill being A/B'd (from PRD)
    - The PRD's `empirical_quality[]` declarations (to bias toward fixtures that exercise
      the axes being gated)
    - A schema describing the skill's expected input shape (lives alongside the skill at
      `plugin-<name>/skills/<skill>/fixture-schema.md`, human-written)
    - The minimum fixture count for the PRD's blast_radius

  Output: N proposed fixtures written to `.kiln/research/<prd-slug>/corpus/proposed/` (NOT the
  committed corpus path). `/plan` then surfaces them to the human:

    - "Synthesized N fixtures. Here's a 3-line summary of each. Accept each one, reject, or
      edit before committing. Type `accept-all` to skip review."

  Only after human review do fixtures move to `plugin-<name>/fixtures/<skill>/corpus/`.

  Promoted vs one-off: the PRD can declare `promote_synthesized: true` to keep accepted fixtures
  in the persistent corpus after the PRD ships (growing the long-term suite). Default is `false`
  — fixtures are one-off for this PRD only, kept in `.kiln/research/<prd-slug>/corpus/` and not
  promoted to the shared location. This respects "no persistent hand-curated corpus" as the
  default stance, while letting maintainers opt-in to growing one.

  Hardest calibration: making synthesized fixtures representative rather than trivial. A dumb
  synthesizer produces "all fixtures look like the skill's first example in the README" — zero
  diversity, no edge cases, passing the gate means nothing. Counter this with:
    - Explicit diversity prompt ("generate fixtures that exercise edge cases: empty inputs,
      maximum-size inputs, typical inputs, adversarial inputs")
    - Reject-then-regenerate loop during human review (reject one, ask for a replacement that
      exercises a different axis)
---

# Research-first step 4 — fixture-synthesizer agent at plan-time with human review gate

## What

A new agent (`fixture-synthesizer`) spawned during `/plan` when the PRD's research block declares `fixture_corpus: synthesized`. Generates N diverse fixtures (count scaled by `blast_radius`), surfaces them to the human for accept/reject/edit review, then commits accepted fixtures to the corpus. Optional promotion to a persistent shared corpus via `promote_synthesized: true`.

## Why now

Hand-curating fixtures for every skill × every comparative change is where the research-first pipeline dies in practice — maintainer burnout kills the whole initiative. Synthesis at plan-time + human review is the middle path: the agent does the work of enumerating diverse inputs; the human retains veto and editing rights.

## Assumptions

- LLM-synthesized fixtures can be meaningfully diverse when given an explicit diversity prompt. If they cluster toward a single pattern, the synthesizer needs a richer schema input. Not yet tested in practice.
- Human review of 10 fixtures takes under 5 minutes with good 3-line summaries. If it balloons to 30+ minutes, synthesis is a net-negative ergonomic. Worth measuring after first 3-5 real uses.

## Hardest part

Representative fixtures, not trivial ones. A synthesizer that produces 20 fixtures all resembling "the first example from the README" is worse than no fixtures at all — the gate passes with misleading confidence. Mitigations are explicit diversity prompts + a reject-then-regenerate loop; neither is airtight.

## Cheaper version

Skip synthesis entirely; ship with declared-corpus only (what step 1 produces). Burdens maintainers but eliminates the synthesizer-drift risk. Ship this step as `kind: research` first (spike to measure whether synthesis is representative) before committing to the full feature.

## Dependencies

Depends on: step 1 (fixture-format-mvp). Independent of steps 2, 3, 5.
