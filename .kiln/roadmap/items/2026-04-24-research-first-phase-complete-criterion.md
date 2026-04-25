---
id: 2026-04-24-research-first-phase-complete-criterion
title: "Research-first phase complete — full workflow exercised end-to-end in a test repo"
kind: goal
date: 2026-04-24
status: open
phase: 09-research-first
state: planned
blast_radius: infra
review_cost: expert
context_cost: 6 sessions
---

# Research-first phase complete — full workflow exercised end-to-end in a test repo

## Target

At least **one PRD** has been generated and shipped (merged PR) in a test repo utilizing the full research-first workflow, including:

1. A source artifact (item / issue / feedback) declared `needs_research: true` with at least one `empirical_quality[]` axis.
2. `/kiln:kiln-distill` propagated the research block into the PRD frontmatter.
3. `/kiln:kiln-build-prd` auto-routed to the research-first variant based on the PRD frontmatter.
4. Baseline metrics were established against a corpus (declared or synthesized).
5. Candidate was implemented in a worktree and measured against the same corpus.
6. The per-axis gate evaluated every declared axis; the workflow proceeded to merge only because no declared axis regressed on any fixture.
7. Audit + PR steps ran as normal, with the research report (`.kiln/logs/research-<uuid>.md`) attached to the PR description.

## How it's measured

- A **faked test in a temp dir** counts (per user — 2026-04-24). The test repo does not need to be a real consumer project; a mocked kiln-init + scripted PRD walking the full pipeline is acceptable for phase completion.
- The test MUST exercise at least one regression scenario — run the pipeline with a deliberately-regressing candidate and confirm the gate fails and blocks merge. Without that negative case, we've only proven the happy path.

## Stopping condition (status: dropped)

Drop this goal if during implementation we discover the judge-agent (item #5) drifts so badly that the output_quality axis is unusable, AND the mechanical axes (tokens / cost / time / accuracy) alone don't catch a meaningful class of regressions worth gating on. In that case the phase devolves into "A/B metrics reporting without a hard gate" and we should re-scope.

## Dependencies

Depends on all 7 feature items in this phase shipping:

- 2026-04-24-research-first-fixture-format-mvp
- 2026-04-24-research-first-per-axis-gate-and-rigor
- 2026-04-24-research-first-time-and-cost-axes
- 2026-04-24-research-first-fixture-synthesizer
- 2026-04-24-research-first-output-quality-judge
- 2026-04-24-research-first-build-prd-wiring
- 2026-04-24-research-first-classifier-inference
