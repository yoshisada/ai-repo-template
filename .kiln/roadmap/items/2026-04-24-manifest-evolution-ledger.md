---
id: 2026-04-24-manifest-evolution-ledger
title: "Manifest-evolution ledger — close the self-improvement loop"
kind: feature
date: 2026-04-24
status: open
phase: 89-brainstorming
state: planned
blast_radius: cross-cutting
review_cost: careful
context_cost: 3+ sessions
---

# Manifest-evolution ledger — close the self-improvement loop

## What

A tracking layer that follows each `.kiln/mistakes/` capture and `@inbox/open/` proposal through its lifecycle: proposed → applied / rejected → did the same mistake recur after the edit landed? Without this, vision win-condition (d) — "the self-improvement loop closes" — is unfalsifiable.

## Why now

`/kiln:kiln-mistake` capture and shelf's manifest-improvement proposals are both shipped. The data exists; nothing reads it longitudinally.

## Open design questions (must resolve before promoting to 90-queued)

- **System-design dependency.** This is one of three features (this, escalation audit, retro-quality auditor) that all want to read across `.kiln/` artifacts and report on system health. Need to design the *whole observability layer* before building any of them — otherwise we ship three skills with overlapping data plumbing.
- **Recurrence detection.** "Did the same mistake recur" requires fingerprinting mistakes — not literal text match, but semantic class. Is that an LLM call per mistake, a tag scheme on the mistake file, or something else?
- **Closed-loop vs reported-only.** Does the ledger just report ("proposal X landed, mistake class Y still recurring 3x/month"), or does it auto-generate new proposals when recurrence persists? The latter is the autonomous promise; the former is the safer shipping point.
- **Storage.** New artifact under `.kiln/ledger/` vs derived view computed at read-time from existing artifacts? File-based-state principle pulls toward derived; performance pulls toward stored.
- **Shelf coupling.** The proposal lifecycle lives in Obsidian (`@inbox/open/` → `@inbox/applied/` or similar). Ledger needs to read shelf state — does it depend on shelf, or on a kiln-side mirror?

## Hardest part

Mistake fingerprinting — and the broader question of whether this is one feature or part of a larger "kiln observability" workstream.

## Cheaper version

Just a `/kiln:kiln-ledger` skill that lists all mistakes + all proposals + all manifest edits in chronological order, no recurrence detection, no auto-proposals. Pure history view. Even that would tell us whether the loop is closing.

## Dependencies

- Should be designed alongside `escalation-audit` and `retro-quality-auditor` — all three are observability features and want shared infrastructure.
