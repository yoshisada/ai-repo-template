---
id: 2026-04-24-win-condition-scorecard
title: "Win-condition scorecard — make the vision falsifiable"
kind: feature
date: 2026-04-24
status: open
phase: 89-brainstorming
state: planned
blast_radius: feature
review_cost: careful
context_cost: 2-3 sessions
---

# Win-condition scorecard — make the vision falsifiable

## What

A skill that walks `.kiln/`, `.wheel/history/`, and git log to produce a periodic scorecard against the eight six-month signals in `.kiln/vision.md` (a)–(h). Turns the vision from aspirational prose into something testable.

## Why now

Vision is articulated; nothing measures it. Without measurement we can't tell if context-informed autonomy, the capture-loop closing, or external-feedback filtering are actually happening — or just believed.

## Open design questions (must resolve before promoting to 90-queued)

- **Per-repo high-score variability.** What counts as "winning" differs by project — solo plugin repo vs consumer product vs research repo all weight the eight signals differently. Does the scorecard ship with weights, or does each repo configure its own? Where do those configs live?
- **Internal-vs-shippable boundary.** If this is a kiln skill it must work in consumer repos, not just here. The eight signals in our vision are *our* signals — consumer projects have their own. Does the skill ship a generic scorecard against a configurable rubric, or is "scorecard" the wrong abstraction and what ships is a *rubric framework* that any repo can populate?
- **Workflow integration.** When does it run? Standalone (`/kiln:kiln-metrics`)? Inside `/kiln:kiln-next`? Cron'd? PR-time? Each fit changes the design.
- **Signal extraction substrate.** How much of the data is reliably parseable across repos (git log is universal; `.wheel/history/` is kiln-specific)? Does the skill degrade gracefully when half the signals can't be measured?

## Hardest part

Defining a rubric framework that's both meaningful and portable. If we ship our specific eight signals, it's useless to consumers. If we ship "configure your own," we ship an empty box.

## Cheaper version

Start internal-only as `/kiln:kiln-metrics` against our specific eight signals. Use what we learn about which signals are extractable to inform a generalized v2.
