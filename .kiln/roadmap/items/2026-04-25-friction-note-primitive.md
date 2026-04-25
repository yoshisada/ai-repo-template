---
id: 2026-04-25-friction-note-primitive
title: "Extract FR-009 friction-note convention as a wheel primitive"
kind: feature
date: 2026-04-25
status: open
phase: 90-queued
state: planned
blast_radius: feature
review_cost: moderate
context_cost: "1-2 sessions"
addresses:
  - 2026-04-23-wheel-as-plugin-agnostic-infra
---

# Extract FR-009 friction-note convention as a wheel primitive

## Summary

The FR-009 friction-note convention currently lives in `kiln-build-prd` SKILL.md as prose ("ALL pipeline agents MUST write a friction note to `specs/<feature>/agent-notes/<agent-name>.md` before completing their work"). Extract it as a wheel primitive (helper script + convention spec) so any orchestrating skill can use it — not just build-prd.

## Why this matters

Friction notes proved valuable in PR #166 + PR #168 retrospectives: structured agent feedback, no live-polling required, retrospective agent reads them deterministically. But the convention is locked into one skill's prose. Any future orchestration pattern (e.g., a hypothetical `clay:clay-build-product` running its own multi-agent pipeline) would have to re-implement it from scratch.

Generalizing it to wheel makes friction notes a reusable mechanism — `/kiln:kiln-fix`, `/kiln:kiln-distill`, hypothetical sibling-plugin pipelines all gain the same self-improvement substrate.

## Scope

- New helper: `plugin-wheel/scripts/friction-notes/<helper>.sh`. Spec the directory layout, file naming convention (`<agent-name>.md`), required structure (problem / what-I-tried / what-I-needed / proposed-fix), and the validator.
- Convention doc: `plugin-wheel/docs/friction-notes.md` — the canonical spec, citable from any consumer skill.
- `kiln-build-prd` SKILL.md updates: replace inline FR-009 prose with a one-line reference to the wheel convention. Existing build-prd retrospective consumer reads notes via the same path.
- A test fixture exercises the validator + read primitive.

## Acceptance

- A non-build-prd skill (pick `/kiln:kiln-fix` or write a minimal harness fixture) writes a friction note via the wheel helper and the retrospective consumer reads it correctly.
- Existing `kiln-build-prd` retrospective behavior unchanged (same files written to same paths, same structure).
- The convention doc is the single source of truth — `kiln-build-prd` SKILL.md delegates to it instead of duplicating it.

## Blast radius rationale

`feature`: touches `kiln-build-prd` SKILL.md (the canonical consumer) + introduces a new wheel directory. Multiple files change but no semantics shift for any existing consumer.

## Dependencies

None. Independent of #1/#2 — friction notes are a separate primitive from the test substrate.

## Knock-on win

Once friction notes are first-class wheel primitives, `/kiln:kiln-fix` Step 7's local fix record could share the same write path. `/kiln:kiln-distill` could emit friction notes describing what it found in the bundled backlog. The pattern compounds.
