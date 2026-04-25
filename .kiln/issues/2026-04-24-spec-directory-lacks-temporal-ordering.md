---
id: 2026-04-24-spec-directory-lacks-temporal-ordering
title: "specs/ directory has no temporal ordering — hard to see what was built when; inconsistent with docs/features/ which is date-prefixed"
type: improvement
date: 2026-04-24
status: open
severity: medium
area: kiln
category: ergonomics
repo: https://github.com/yoshisada/ai-repo-template
files:
  - specs
  - docs/features
  - plugin-kiln/skills/specify
  - plugin-kiln/bin/init.mjs
---

## Summary

The `specs/` directory contains 46 subdirectories that are **sorted alphabetically only** — there's no temporal ordering, no numbering, no date prefix. Reading `ls specs/` gives no signal about what was built first, what's most recent, or which specs are from which phase. You have to cross-reference git log or the corresponding `docs/features/<date>-<slug>/` directory to answer "what was built when?"

**Making this worse: `docs/features/` IS date-prefixed** (`2026-03-31-continuance-agent`, `2026-04-01-kiln-polish`, …) — same slugs, just with a date. The two canonical "what we built" directories use different conventions for the same slugs. One legacy spec (`specs/001-kiln-polish`) even has a numeric prefix — presumably from before the convention settled — so `specs/` has been inconsistent *with itself* over time.

## Concrete pain

- `ls specs/` can't answer "what's the most recent feature?"
- Running `/kiln:kiln-distill` requires remembering which slugs are current, which are shipped, which are stale.
- Onboarding a teammate or re-orienting after a break requires grepping git log to reconstruct chronology.
- Cross-referencing a spec with its PRD (`docs/features/<date>-<slug>/PRD.md`) requires mentally prepending the date — you're doing the same naming computation twice.

## Why the two canonical directories diverged

Plausible guess (worth confirming): `docs/features/` was introduced after `specs/` and picked up the date-prefix convention from `.kiln/issues/` / `.kiln/roadmap/items/`. `specs/` kept its original convention because renaming 40+ existing directories would break git history linkage and every reference from `.kiln/roadmap/items[].spec:` frontmatter fields.

## Proposed directions

Three options; second likely the right shape:

### (A) Rename all spec directories to match `docs/features/` date-prefix convention

Rename `specs/continuance-agent/` → `specs/2026-03-31-continuance-agent/`, etc. Mirror `docs/features/` exactly. Update every `.kiln/roadmap/items/*.md` frontmatter `spec:` reference and every cross-link in PRDs / plans / tasks. Large-blast-radius operation; has to be atomic to avoid broken references.

### (B) Add an auto-generated `specs/INDEX.md` with chronological ordering

Keep the directory names as-is (no rename, no cross-link breakage). Generate `specs/INDEX.md` periodically (hook-triggered on spec creation, or `/kiln:kiln-doctor` subcheck) listing every spec with: creation date (from git log or spec frontmatter), current status (open / specced / shipped), linked PRD path, one-line description from the spec's `## Summary`. Renders `specs/` into a readable timeline without mass-renaming anything.

Lower blast radius, preserves existing references, and gives a canonical "what was built when" answer that `ls` alone can't provide. Good candidate for the first pass.

### (C) Both — start with (B) for immediate relief; do (A) as a longer-term migration

(B) ships fast and is risk-free; (A) becomes a separate PRD if the INDEX approach proves insufficient (e.g., if tooling still wants the date signal in the path itself).

## Proposed acceptance

- `specs/INDEX.md` exists, is auto-generated (not hand-edited), and shows every spec ordered by creation date with: date, slug, status, PRD link, one-line summary.
- A hook or skill keeps it up to date — either `/kiln:kiln-doctor` regenerates it on demand, or a post-spec-creation hook updates it, or `/kiln:kiln-next` includes "regenerate spec index" as a suggestion when the index is stale.
- Existing `specs/` directory names unchanged (preserves all roadmap-item / PRD / plan / tasks cross-references).
- One-off: document the decision (B-only vs B-then-A) in a note under `.kiln/decisions/` or similar.

## Relation to other captured items

- Similar shape to `2026-04-24-kiln-next-smarter-triage` — both are "there's data on disk that we need a better view over." If we're going to build spec-index generation logic, the same consumption-side primitive could serve `/kiln:kiln-next`.
- Composes with the existing `branch-and-spec-directory-naming-is-inconsistent-causes-agent-co` note (in the Obsidian vault) — different aspect of the same pain surface. If that note exists locally too, worth cross-referencing.

## Pipeline guidance

Medium severity — friction compounds as the spec count grows, but not blocking current work. `/kiln:kiln-fix` appropriate if going straight to option (B). If pursuing (A), full pipeline warranted (cross-references need careful migration).
