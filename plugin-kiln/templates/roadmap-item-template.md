---
id: <YYYY-MM-DD>-<slug>
title: "<one-line title>"
kind: feature        # FR-010: feature | goal | research | constraint | non-goal | milestone | critique
date: <YYYY-MM-DD>
status: open         # FR-010 kind-specific; see contracts/interfaces.md §1.4
phase: unsorted      # phase name — matches a file in .kiln/roadmap/phases/
state: planned       # FR-021: planned | in-phase | distilled | specced | shipped
# --- AI-native sizing (FR-008 / PRD FR-008): these three are REQUIRED.
#     Human-time / T-shirt sizing is forbidden by schema.
blast_radius: feature        # isolated | feature | cross-cutting | infra
review_cost: moderate        # trivial | moderate | careful | expert
context_cost: 1 session      # free-text rough estimate (e.g., "1 session", "3 sessions", "one-shot")
# --- Optional (FR-009) ---
# depends_on: []              # list of item-ids this blocks on
# addresses: []               # list of critique-ids this item argues against
# implementation_hints: |     # flows into PRD Implementation Hints on distill (FR-027)
#   <free text>
# prd: docs/features/.../PRD.md      # written by /kiln:kiln-distill on promotion (FR-026)
# spec: specs/.../spec.md            # written by /specify on state: specced (FR-034)
---

<!--
FR-007 / PRD FR-007: item frontmatter required keys.
FR-008 / PRD FR-008: AI-native sizing only — human-time / T-shirt fields are REJECTED by validator.
Contract: specs/structured-roadmap/contracts/interfaces.md §1.3–§1.5.
-->

# <title>

## What

_One or two paragraphs. What is this item? Why does it matter right now?_

## Why now

_What's changed that makes this the right moment to do it?_

## Assumptions

_Bullet the things you're assuming will be true when work starts — that's where the surprise lives._

- Assumption 1
- Assumption 2

## Hardest part

_One paragraph. What's the part that, if it goes wrong, kills the whole thing?_

## Cheaper version

_One paragraph. Is there a 20%-effort / 80%-value version? (If not, say so explicitly — the adversarial interview asks.)_

## Dependencies

_Which items (`<item-id>`) or external things does this depend on?_

- Depends on: …
