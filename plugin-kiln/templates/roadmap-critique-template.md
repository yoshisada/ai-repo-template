---
id: <YYYY-MM-DD>-<slug>
title: "<the critique, in the critic's voice>"
kind: critique
date: <YYYY-MM-DD>
status: open         # FR-011: open | partially-disproved | disproved
phase: unsorted
state: planned
blast_radius: cross-cutting   # critiques usually touch the whole product
review_cost: careful
context_cost: ongoing — revisit each release
proof_path: |
  <REQUIRED — FR-011. What would need to ship or be measured to make this critique false?>
# --- Optional (FR-009) ---
# addresses: []            # usually empty for critiques (features reference critiques, not the other way round)
# implementation_hints: |  # optional note on strategy
#   <free text>
---

<!--
FR-011 / PRD FR-011: kind:critique requires non-empty proof_path.
FR-029 / PRD FR-029: seed critiques ship pre-filled; authored critiques follow this same shape.
Contract: specs/structured-roadmap/contracts/interfaces.md §1.3 critique branch.
-->

# <title>

## The fear

_One or two paragraphs. State the critique in the voice of whoever holds it — friend, former colleague, inner sceptic. No softening._

## Who would make this claim

_One paragraph. Who is this critique's natural speaker? What's their context?_

## Kind of critique

_Is this a hard (architectural / foundational) critique or a soft (UX / friction) one?_

## Counter-evidence to watch for

_Bullet the concrete signals that would move the status from `open` → `partially-disproved` → `disproved`._

- …
- …

## Linked items

_Items that, if they ship, argue against this critique. Referenced by adding `addresses: [<this-id>]` on the other item._

- …
