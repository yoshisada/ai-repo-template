---
title: kiln-roadmap doesn't know about queued or brainstorming states
date: 2026-04-27
status: open
kind: improvement
priority: medium
repo: https://github.com/yoshisada/ai-repo-template
tags:
  - kiln-roadmap
  - state-model
  - triage
  - capture-pipeline
source: kiln-report-issue
---

# kiln-roadmap doesn't know about queued or brainstorming states

## Description

`/kiln:kiln-roadmap` has no awareness of the queue surfaces that already exist in the roadmap state, and no concept of "brainstorming" as a pre-classification stage. When a user asks to "file existing queued items," the skill cannot disambiguate which queue surface is meant — even though three concurrently exist in this very repo.

## Observed today (triage session, 2026-04-27)

When the user said "help me file existing queued items to the roadmap," there were **three distinct queue surfaces** open at once and the skill helped with none of them out of the box:

1. **`phase: 90-queued`** — 20 fully-classified roadmap items deliberately parked as a "later" bucket. These are filed but deferred.
2. **`phase: unsorted`** — 5 migrated items pending reclassification (the documented `--reclassify` target).
3. **53 unpromoted sources** in `.kiln/issues/` and `.kiln/feedback/` — not yet roadmap items at all (the documented `--promote` target).

The skill body in `plugin-kiln/skills/kiln-roadmap/SKILL.md` references `unsorted` (Step 0 seed phase, §R reclassify) and `promote` (§M), but **never mentions `90-queued` or any equivalent "deferred / later" bucket**, even though such items appear in `.kiln/roadmap/items/*.md` with that phase value. There is also no notion of a "brainstorming" stage — pre-classification raw thought that hasn't been adversarially-interviewed yet.

## Why this matters

- The skill's job is to be the single capture/triage surface for roadmap state. If it doesn't model the queues that exist, users (and Claude) end up triaging by hand or asking clarifying questions the skill should be answering.
- `--check` (§C consistency check) walks every item but doesn't surface "X items sit in 90-queued — graduate any?" or "5 items are unsorted — run --reclassify".
- `--reclassify` only handles `phase: unsorted`. There is no equivalent verb for "walk the 90-queued bucket and graduate items to active phases."
- "Brainstorming" — the state of an idea before it's worth committing to a roadmap item file — has no representation. Users either (a) capture too eagerly and pollute the items dir, or (b) keep ideas in scratchpads outside the system.

## Proposed direction (sketch — not a spec)

1. **Make `90-queued` (or rename to a canonical `queued`) a first-class state** in the skill, alongside `unsorted`. Document it in §0 and surface it in `--check` output and the orientation block (§1c).
2. **Add a `--triage-queued` verb** (mirror of `--reclassify`) that walks `phase: queued` items and asks: graduate to active phase / keep queued / archive.
3. **Decide on a `brainstorming` representation** — one of:
    - (a) A new `state: brainstorming` value on items (lightweight, skip-interview, no proof_path enforcement);
    - (b) A separate `.kiln/roadmap/brainstorm/` directory that's outside the items contract until promoted;
    - (c) Keep brainstorming in `.kiln/feedback/` and rely on `--promote` (status quo — but then say so explicitly in the skill so users stop expecting roadmap to model it).
4. **Update the routing prompt (§2)** so when a description sounds like a half-formed thought, the skill can suggest "this looks like brainstorming — keep it in feedback until it's sharper" rather than forcing the user through the adversarial interview.

## Acceptance hints

- `/kiln:kiln-roadmap --check` reports queue-surface counts: `queued: N, unsorted: M, brainstorming: K`.
- `/kiln:kiln-roadmap` (no args) at session start mentions any non-empty queue surfaces in the orientation block (§1c).
- The SKILL.md references `90-queued` (or its successor name) at least once in the contract, not just as an emergent value in the items dir.

## Source

Surfaced during a roadmap triage session on 2026-04-27. The user asked "help me file existing queued items to the roadmap" and the skill couldn't disambiguate which of the three coexisting queues was meant — Claude had to triage by hand and ask back.
