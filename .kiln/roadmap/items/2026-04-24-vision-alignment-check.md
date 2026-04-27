---
id: 2026-04-24-vision-alignment-check
title: "Vision-alignment check — flag roadmap drift against the stated vision"
kind: feature
date: 2026-04-24
status: open
phase: 10-self-optimization
state: specced
blast_radius: feature
review_cost: moderate
context_cost: 1-2 sessions
prd: docs/features/2026-04-27-vision-tooling/PRD.md
spec: specs/vision-tooling/spec.md
---

# Vision-alignment check — flag roadmap drift against the stated vision

## What

A new mode (likely `/kiln:kiln-roadmap --check-vision-alignment`) that maps every queued/in-flight roadmap item back to one or more vision pillars in `.kiln/vision.md`, and flags items that don't ladder up. Output is a per-item alignment line (item → pillar(s) it serves) and a "drifters" list for review.

## Why now

Vision win-condition (h): "external feedback gets filtered." The current `--check` mode only audits state consistency (in-phase items match an in-progress phase, etc.) — it doesn't audit *purpose alignment*. As the queue grows, off-thesis ideas will accumulate without this gate.

## Open design questions (must resolve before promoting to 90-queued)

- **Mapping mechanism.** LLM-driven semantic match (item description → vision pillar) is the obvious answer, but determinism is a kiln value (idempotent writes, byte-identical output). Does this fit, or do we need explicit `addresses_pillar:` frontmatter on items?
- **Frontmatter vs inferred.** If we add `addresses_pillar:` to the item schema, that's a schema change rippling through every existing item. If we keep it inferred, the check is non-deterministic.
- **Action on drifters.** Just report? Refuse to promote drifters into `--phase start`? Auto-suggest moving to `unsorted`?
- **Vision changes invalidate alignment.** When `.kiln/vision.md` is updated via `--vision`, prior alignment verdicts may be stale. Re-check on every vision change?

## Hardest part

The schema-vs-inference trade-off — both have real costs.

## Cheaper version

Inferred + report-only, no schema changes, no enforcement. User reads the report, decides what to move. If the report turns out to be useful, formalize with `addresses_pillar:` later.
