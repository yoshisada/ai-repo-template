---
id: 2026-04-24-prd-requires-roadmap-item-source
title: No items should be added to a PRD before being captured as a roadmap item — distill must require roadmap-item sources, not accept raw issues/feedback directly
type: improvement
date: 2026-04-24
status: prd-created
prd: docs/features/2026-04-24-workflow-governance/PRD.md
severity: medium
area: kiln
category: governance
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-kiln/skills/kiln-distill
  - plugin-kiln/skills/kiln-report-issue
  - plugin-kiln/skills/kiln-feedback
  - plugin-kiln/skills/kiln-roadmap
  - .kiln/roadmap/items
  - .kiln/issues
  - .kiln/feedback
---

## Summary

Every PRD created via `/kiln:kiln-distill` must trace back to a roadmap item. Today the skill bundles items from THREE sources — `.kiln/feedback/`, `.kiln/roadmap/items/`, and `.kiln/issues/` — which lets raw tactical issues or strategic feedback become PRD content without first being captured, sized (blast_radius / review_cost / context_cost), kinded (feature / goal / research / etc.), and interviewed through the adversarial layer.

The governance claim: **the roadmap is the canonical intake for PRD creation**. Issues and feedback are *sources for promotion* to roadmap items — not direct PRD inputs.

## Why this matters

- Today a raw issue with zero sizing or kind classification can end up as the justification for a PRD. That means `/kiln:kiln-distill`'s narrative-shaping step is working with un-interrogated material.
- Skipping the adversarial interview (FR-015 of `structured-roadmap`) means PRDs can ship with thin assumptions — the interview exists specifically to surface those.
- Without roadmap-first promotion, precedent tracking gets degraded: an issue might be a duplicate of a declined `kind: non-goal` item, but the distill skill has no hook to check because issues don't go through the same classification pipeline.
- The vision's "context-informed autonomy" principle depends on accumulated decisions having a consistent shape. Roadmap items have that shape (typed frontmatter, sizing, interview history); issues and feedback don't.

## Proposed behavior

- `/kiln:kiln-distill` bundles ONLY roadmap items. Issues and feedback are NOT direct PRD sources.
- When a user runs `/kiln:kiln-distill` and the skill would benefit from a raw issue or feedback note that hasn't been promoted yet, the skill routes through the promotion path — either silently captures it as a roadmap item via the same confirm-never-silent pattern, or explicitly says "issue X and feedback Y look relevant; want me to promote them to roadmap items before distilling?" and waits for approval.
- Promotion itself may need a dedicated path — e.g., `/kiln:kiln-roadmap --promote <issue-id>` or `--promote <feedback-path>` that runs the adversarial interview on the source material, writes a proper roadmap item (with `kind`, sizing, phase assignment), back-references the source issue/feedback, and closes the source with a "promoted to roadmap item X" status change.
- `/kiln:kiln-report-issue` and `/kiln:kiln-feedback` unchanged — they still capture tactical/strategic inputs — but with updated narrative: "these feed the roadmap, which feeds PRDs."

## Proposed acceptance

- `/kiln:kiln-distill` refuses to bundle raw issues/feedback that haven't been promoted (or offers to promote them as a mid-skill hand-off).
- A `/kiln:kiln-roadmap --promote` path (or equivalent) exists to move an issue or feedback note into a properly-classified roadmap item, including the adversarial interview, sizing, and kind assignment.
- Back-references preserved: the roadmap item's frontmatter includes `promoted_from: <issue-id>` or `promoted_from: <feedback-path>`; the source's frontmatter is updated to `status: promoted` with a `roadmap_item:` back-link.
- `/kiln:kiln-distill` documentation + skill narrative updated to reflect "roadmap items are the canonical input."
- Existing distilled PRDs that were built from raw issues/feedback do not need retroactive fixing — the change is forward-looking.

## Relation to other captured items

- Complements `2026-04-24-precedent-reader-helper` — precedent-reader queries accumulated decisions; enforcing "roadmap-first intake" ensures those decisions have consistent shape.
- Reinforces `2026-04-24-kiln-next-smarter-triage` — the triage sub-workflow would naturally surface "ready-to-promote" issues/feedback as part of its output.

## Pipeline guidance

Medium severity — a governance shift that changes the mental model for how capture surfaces feed PRDs. Not blocking any current work, but worth addressing before the backlog of raw issues grows larger and the temptation to pipe them directly into PRDs cements as habit. Modest implementation cost (distill gate + promotion path), disproportionate clarity benefit.
