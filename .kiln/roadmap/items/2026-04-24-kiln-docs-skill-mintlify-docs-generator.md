---
id: 2026-04-24-kiln-docs-skill-mintlify-docs-generator
title: "kiln-docs skill — generate and maintain user-facing product documentation (Mintlify + wiki)"
kind: feature
date: 2026-04-24
status: open
phase: 90-queued
state: planned
blast_radius: feature
review_cost: moderate
context_cost: ~2 sessions
---

# kiln-docs skill — generate and maintain user-facing product documentation (Mintlify + wiki)

## Intent

A new `/kiln:kiln-docs` skill that generates and maintains user-facing product documentation — including the correct order in which `/kiln:*` commands should be invoked — for developers and users adopting the product. Primary output is a Mintlify site; secondary is a docs wiki export.

## Hardest part

Keeping docs in sync as skills are added or renamed. Real concern, but expected to be manageable given existing discipline around skill metadata and the shared project-context reader.

## Assumptions

Sufficient skill and product metadata will exist via `vision.md`, PRDs, per-skill frontmatter, and the shared project-context reader to derive documentation programmatically — minimal hand-curation needed.

## Audience & surface

- **Audience**: a developer or user looking to use the product — someone adopting kiln, not already fluent
- **Primary surface**: Mintlify (docs-as-code site)
- **Secondary surface**: docs wiki

## Done for v1

- `/kiln:kiln-docs` scaffolds a Mintlify site from skill/plugin metadata + `vision.md` + PRDs
- Regenerates sections derivable from source (command reference, ordered walkthroughs grouped by workflow — onboarding / new-feature / bugfix / QA, plugin inventory) while leaving hand-written narrative pages untouched
- Wiki export deferred to v1.1

## Failure mode to avoid

Stale docs that lie. Every auto-regenerated section must be idempotent and diff-clean on unchanged inputs (same discipline as `/kiln:kiln-distill`'s byte-identical emission), so drift is visible in git and we never ship docs that silently describe an old command surface.

## Dependencies

- Shared project-context reader at `plugin-kiln/scripts/context/read-project-context.sh` (and sibling `read-prds.sh` / `read-plugins.sh`) — canonical source for skill/plugin/PRD metadata
- Mintlify conventions (`mint.json`, MDX page structure)
- May require additive per-skill frontmatter fields (e.g., `category`, `ordering_hint`, `prereq_skills`) if current metadata is insufficient for ordering derivation
