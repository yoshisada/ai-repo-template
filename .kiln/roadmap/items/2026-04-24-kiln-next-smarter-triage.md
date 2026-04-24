---
id: 2026-04-24-kiln-next-smarter-triage
title: "kiln-next — smarter about what should come next, backed by an internal triage sub-workflow"
kind: feature
date: 2026-04-24
status: open
phase: 90-queued
state: planned
blast_radius: feature
review_cost: moderate
context_cost: ~1-2 sessions
---

# kiln-next — smarter about what should come next, backed by an internal triage sub-workflow

## Intent

Close the gap between the maturing capture surface (feedback, issues, roadmap items, mistakes all have good ergonomics now) and the under-invested consumption surface (nothing walks what's accumulated and says "here's what's ripe to act on"). Quickest win: make `/kiln:kiln-next` smarter so it already does this, rather than introducing a separate `/kiln:kiln-triage` skill the user has to remember to run.

The triage logic itself is **not** a user-facing skill — it's an internal sub-workflow (or helper) that `/kiln:kiln-next` invokes when deciding what to recommend.

## Hardest part

Ranking. "What should come next?" is an opinion, not a fact. The recommendation has to weigh: recency, phase status, precedent (has the user already declined similar work?), cluster density (are 3 items together a natural PRD?), staleness (is this still relevant given shipped PRs?), and effort (AI-native sizing — `blast_radius`, `review_cost`, `context_cost`). Get the weighting wrong and `/kiln:kiln-next` becomes noise.

## Assumptions

- The shared project-context reader (`plugin-kiln/scripts/context/`) already gives us the raw material (PRDs, roadmap items, phases, vision) without re-implementing parsing.
- The precedent-reader helper (`2026-04-24-precedent-reader-helper`, once built) can suppress recommendations the user has already declined.
- `/kiln:kiln-next` already has a natural "produce a prioritized list" shape — this is an enhancement to its ranking, not a new skill.

## Architecture

- **Internal triage sub-workflow** at `plugin-kiln/scripts/triage/` (or a wheel sub-workflow, if the sub-workflow shape is cleaner for the ranking logic that may need multiple agent judgements):
  - Input: the project-context snapshot + accumulated items (roadmap / issues / feedback / mistakes).
  - Output: a ranked list with reason codes per item (`ready-to-distill`, `ripe-for-closure`, `stale`, `duplicate-of`, `cluster-with`, etc.).
- **`/kiln:kiln-next` consumes this output** and renders a user-facing recommendation: top 3-5 actions with one-line rationale each, plus the commands to run them (`/kiln:kiln-distill --phase X`, close-issue helper, merge-items prompt, etc.).
- The triage sub-workflow is callable directly (for debugging / power-user use) but is not advertised as a first-class user command. It's plumbing.

## Triage signals

At minimum, the sub-workflow should surface:

- **Ready-to-distill clusters** — N ≥ 3 items sharing a theme or `phase`, with enough detail that `/kiln:kiln-distill --phase <name>` would produce a PRD.
- **Ripe-for-closure** — items whose `prd:` or `pr:` references point to shipped/merged artifacts; suggest `state: distilled` or `status: completed`.
- **Stale** — items older than a configurable threshold with no status change, where the shipped surface has drifted (the surface the item describes no longer exists).
- **Duplicate / near-duplicate** — items with high title-similarity; suggest merge.
- **Precedent conflicts** — items that the user has previously declined (via `kind: non-goal` or captured feedback) that have been re-captured; flag for attention so the user knows the loop isn't closing cleanly.

## Dependencies

- **precedent-reader helper** (`2026-04-24-precedent-reader-helper`) — without it, the "precedent conflict" signal isn't possible.
- **Existing project-context reader** — no new parsing infrastructure needed; extend consumption.
- Optional: loosely coupled to the `kiln-docs` skill (if `/kiln:kiln-next` triage surfaces "docs drift" signals as a future extension).

## Failure modes to avoid

- **Noise over signal.** If `/kiln:kiln-next` surfaces 15 "you should look at this" items, the user stops trusting it. Top 3-5, ranked, with clear reason codes.
- **Wrong-ordering staleness recommendations.** Recommending "close stale items" before "distill ready clusters" is backwards — users want the high-value action first.
- **Silent behavioral drift.** If `/kiln:kiln-next` changes its output shape significantly, consumers (or the user's muscle memory) will trip. Keep the output grammar stable; change only the ranking.
- **Sub-workflow bloat.** Resist the urge to make the triage sub-workflow do everything. Scope: ranking + classification of existing items. Not: new item creation, not auto-closure, not auto-merging. Those are user actions the skill presents.

## Success signal

- `/kiln:kiln-next` recommendations move from "here's where you left off on the current branch" (tactical) to "here's what's most valuable to act on across everything you've captured" (strategic).
- Items spend less time in "open-but-forgotten" state — the triage surfaces them before they rot.
- User reports (via `/kiln:kiln-feedback` or behavioral — do they act on the recommendations?) confirm the ranking is useful.
