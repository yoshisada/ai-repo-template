---
id: 2026-04-24-research-first-output-quality-judge
title: "Research-first step 5 — output-quality judge-agent with PRD-derived rubric (riskiest axis)"
kind: feature
date: 2026-04-24
status: shipped
phase: 09-research-first
state: shipped
pr: 182
prd: docs/features/2026-04-25-research-first-plan-time-agents/PRD.md
blast_radius: feature
review_cost: expert
context_cost: 3 sessions
depends_on:
  - 2026-04-24-research-first-fixture-format-mvp
implementation_hints: |
  The `output_quality` axis is the fuzzy one — mechanical axes (accuracy / tokens / time / cost)
  can be tested by diffing numbers; output quality needs a judge.

  Design:

    - PRD declares `empirical_quality: [..., {metric: output_quality, direction: equal_or_better,
      rubric: "..."}, ...]`. The `rubric:` field is a free-text string written by the PRD author
      describing the intended improvement axis ("more concise without losing accuracy",
      "clearer step-ordering", "more actionable error messages").
    - Judge-agent receives per fixture: the baseline output, the candidate output, and the VERBATIM
      rubric string (NEVER summarize the rubric — per `2026-04-24-skill-ab-harness-wheel-workflow`
      "The rubric has to be derived from the PR intent (commit message, user-supplied `--intent`)
      and passed to the judge verbatim, not summarized"). Emits: candidate_better | equal | baseline_better
      + one-sentence rationale.
    - Gate: for every fixture, judge verdict MUST NOT be `baseline_better` (direction: equal_or_better).

  Anti-drift measures (the hardest-part problem):
    - Pinned judge model: use a specific model ID (not "whatever is newest") so judge behavior
      is reproducible across the research run. Document the pinned model in the PRD blockers
      if it diverges from the primary model.
    - Blind-to-version: judge does NOT know which output came from baseline vs candidate (randomize
      the A/B label per fixture; record mapping in the report). This is the single most important
      anti-drift measure.
    - Pairwise sanity check: occasionally run judge with baseline=candidate=same-output. Expected
      verdict: `equal` (within noise). If judge says `candidate_better` when inputs are identical,
      the judge is drifting — fail the research run with a clear error.

  Defer default-on: this axis ships opt-in per PRD. Most PRDs will use accuracy/tokens/cost/time
  only. Only opt into `output_quality` when the improvement is genuinely qualitative and can't
  be captured mechanically.
---

# Research-first step 5 — output-quality judge-agent with PRD-derived rubric (riskiest axis)

## What

A judge-agent evaluates baseline vs candidate outputs against a verbatim PRD-author-written rubric, emitting `candidate_better | equal | baseline_better` per fixture. Ships with anti-drift measures: pinned model, blind-to-version ordering, and identical-input sanity checks.

## Why now

Some improvements are genuinely qualitative ("clearer error messages", "better-structured PRDs", "more actionable suggestions") and mechanical axes miss them. Without this axis, the research-first pipeline can only gate on numeric metrics — limiting the space of changes it's useful for. With this axis, we extend gating to quality — but at the cost of introducing a judge whose reliability is the main thing to worry about.

## Assumptions

- LLM-as-judge with a verbatim rubric + blind-to-version ordering produces a signal stable enough to gate on. This is the main unproved assumption and the reason this item is flagged as the riskiest axis.
- Identical-input sanity checks (A=B should give `equal`) catch the worst drift cases — judges that reliably prefer "version A" regardless of content, or judges that always return "candidate_better" because of positional bias.

## Hardest part

**Judge reliability.** A judge that is 70% correct turns the research gate into a coin-flip with extra steps. A judge that is 99% correct is useful. Measuring judge reliability requires a corpus of known-outcome comparisons — and building that corpus is a whole research project in itself. Mitigation: ship this axis with a loud warning banner on every run for the first N PRDs, attach the judge's full chain-of-reasoning to every verdict, and invite manual override. Graduate to "trusted gate" only after N successful research runs where a human reviewer agreed with the judge.

## Cheaper version

**Skip this step entirely for the initial phase.** The mechanical axes (accuracy + tokens + time + cost) cover the majority of comparative changes people actually want to make. Ship the phase without output_quality, and add it later if and only if a real PRD requests it. This matches the existing `2026-04-24-skill-ab-harness-wheel-workflow` item's position that the cheaper variant is "accuracy + tokens only, defer the judge."

## Dependencies

Depends on: step 1 (fixture-format-mvp). Independent of all other steps.
