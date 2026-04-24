---
id: 2026-04-24-kiln-roadmap-first-run-backfill-prompt
title: "kiln-roadmap first-run backfill prompt"
kind: feature
date: 2026-04-24
status: open
phase: unsorted
state: planned
blast_radius: feature
review_cost: moderate
context_cost: 1 session
implementation_hints: |
  On skill entry, after Step 0 bootstrap, detect the state:
    - `.kiln/roadmap/items/` is empty (or only contains seed critiques)
    - AND `.kiln/roadmap.legacy.md` exists (written by H_MIGRATE)
  When both are true AND session is interactive AND not --quick:
    Prompt: "Found N legacy items from `.kiln/roadmap.md`. Backfill them through a shorter interview now, or start fresh?"
    - (a) backfill N items — loop through each legacy bullet with a trimmed interview (kind + phase + sizing only; skip most adversarial questions)
    - (b) start fresh — proceed to capture pipeline with the user's actual description
    - (c) later — print a hint pointing at `--reclassify` and exit
  Reuses the existing --reclassify machinery for the per-item loop, just entered via a different prompt.
  Cheapest version (if full backfill path is too much): skip the new prompt entirely and just print a hint after migration pointing users at `--reclassify`.
---

# kiln-roadmap first-run backfill prompt

## What

After the first-run migration moves `.kiln/roadmap.md` → `.kiln/roadmap.legacy.md`, `/kiln:kiln-roadmap` should detect that combination (empty items dir + legacy file present) on skill entry and prompt the user to backfill the legacy one-liners through a shorter interview path — same skill, different entry prompt. The shortened interview skips most adversarial questions and asks only what's needed to promote each one-liner out of `phase: unsorted`: kind, phase, sizing.

## Why now

The structured roadmap system already ships the migration that moves legacy content aside and seeds items into `phase: unsorted`. But there's no affordance to actually enrich those items — a user has to know `--reclassify` exists and run it themselves. Without a prompt, migrated items sit in `unsorted` indefinitely, which defeats the purpose of the structured system.

## Assumptions

- Users with a legacy `.kiln/roadmap.md` will opt in to a walk-through rather than ignore the prompt, because the friction of migration has already put them in "roadmap mindset."
- The existing `H_MIGRATE` reliably produces `phase: unsorted` items that `--reclassify` can walk.
- A shorter interview (kind + phase + sizing) is enough signal to make migrated items useful — full adversarial pushback isn't needed for items the user wrote as one-liners (they're pre-framed as thin).

## Hardest part

Designing the trimmed interview so it doesn't rubber-stamp the one-liners but also doesn't stall a user trying to move on. The question set needs to be short enough to feel like batch cleanup, not five individual deep dives.

## Cheaper version

Skip the new entry-prompt path entirely — just print a hint at the end of migration output: "Run `/kiln:kiln-roadmap --reclassify` to enrich these into structured items." Reuses everything that already exists and captures ~80% of the value (discoverability of `--reclassify`). Only upgrade to the full backfill prompt if users report that the hint isn't enough.

## Dependencies

- Depends on: `plugin-kiln/scripts/roadmap/migrate-legacy-roadmap.sh` (H_MIGRATE) continuing to produce `phase: unsorted` items.
- Depends on: `--reclassify` flow (§R in SKILL.md) remaining the canonical enrichment path.
