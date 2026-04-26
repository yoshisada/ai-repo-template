---
id: 2026-04-24-research-first-classifier-inference
title: "Research-first step 7 — classifier infers needs_research from capture description"
kind: feature
date: 2026-04-24
status: open
phase: 09-research-first
state: shipped
prd: docs/features/2026-04-26-research-first-completion/PRD.md
blast_radius: isolated
review_cost: moderate
context_cost: 1 session
depends_on:
  - 2026-04-24-research-first-build-prd-wiring
implementation_hints: |
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
---

# Research-first step 7 — classifier infers needs_research from capture description

## What

Extend the roadmap / issue / feedback classifiers to detect comparative-improvement signal words in the description and propose `needs_research: true` plus a best-guess axis list in the coached-capture interview. Maintainer accepts / tweaks / rejects the proposal — this is a suggestion, not an imposition.

## Why now

Step 6 ships the PRD-driven routing, but every maintainer still has to remember to set `needs_research: true` when they capture a comparative-improvement idea. Classifier inference with a coached-capture prompt makes the system remind them at capture time — matching the existing coached-capture pattern (`accept / tweak / reject`) that maintainers already know.

## Assumptions

- Signal-word matching is good enough for proposal-grade inference (maintainer veto on every match). An ML classifier is overkill for this.
- False-positives are not annoying because the capture interview already includes accept/reject affordance — one extra prompt with an obvious-to-reject suggestion adds little friction.

## Hardest part

Knowing when NOT to propose. A feature that mentions "cheaper" in its description ("this should be cheaper to ship") is not a comparative-improvement ask — the capture ergonomics should recognize that "cheaper to ship" means "lower implementation cost", not "lower runtime cost/tokens." Distinguishing the two cleanly needs light context-awareness (nearby words), not just keyword matching.

## Cheaper version

Ship with only the most high-signal words first — "compare to", "versus", "regression" — and no axis inference (just propose `needs_research: true` and ask the user to declare axes manually). Narrower coverage but zero false-positive risk. Revise to the broader signal set once we see real usage.

## Dependencies

Depends on: step 6 (build-prd-wiring) — the inferred field is meaningless without the pipeline wiring that reads it.
