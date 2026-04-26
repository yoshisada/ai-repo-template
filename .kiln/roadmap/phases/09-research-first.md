---
name: 09-research-first
status: in-progress
order: 9
started: 2026-04-26
---

<!--
FR-005 / PRD FR-005: phase frontmatter required keys = name, status, order.
FR-006 / PRD FR-006: body = short description + auto-maintained item list.

Do NOT hand-edit the `## Items` section below — it is rewritten by
plugin-kiln/scripts/roadmap/update-phase-status.sh register <item-id>.
The description ABOVE `## Items` is author-owned.
-->

# 09-research-first

Builds the research-first variant of `/kiln:kiln-build-prd` — a declarative empirical-gating path where source artifacts (items / issues / feedback) can declare `needs_research: true` plus the axes they care about (tokens, cost, time, accuracy, output_quality), and the pipeline runs baseline vs candidate against a corpus of examples before merging. Gate policy enforces per-axis direction (no declared axis may regress), with rigor (fixture count, strictness) scaling from `blast_radius`. Success: at least one PRD has been generated and shipped in a test repo exercising the full workflow end-to-end — can be a faked test in a temp dir.

Subsumes `2026-04-24-skill-ab-harness-wheel-workflow.md` — that item's design notes feed into item #1 (`research-first-fixture-format-mvp`); the harness it described becomes internal infrastructure, not a user-facing product.

## Items

- 2026-04-24-research-first-build-prd-wiring
- 2026-04-24-research-first-classifier-inference
- 2026-04-24-research-first-fixture-format-mvp
- 2026-04-24-research-first-fixture-synthesizer
- 2026-04-24-research-first-output-quality-judge
- 2026-04-24-research-first-per-axis-gate-and-rigor
- 2026-04-24-research-first-phase-complete-criterion
- 2026-04-24-research-first-time-and-cost-axes
