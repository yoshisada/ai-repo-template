---
id: 2026-04-25-team-orchestration-primitive
title: "Extract agent-team orchestration patterns as wheel:team-orchestrate primitive"
kind: feature
date: 2026-04-25
status: open
phase: 90-queued
state: planned
blast_radius: cross-cutting
review_cost: careful
context_cost: "3+ sessions"
addresses:
  - 2026-04-23-wheel-as-plugin-agnostic-infra
depends_on:
  - 2026-04-25-wheel-test-runner-extraction
  - 2026-04-25-friction-note-primitive
---

# Extract agent-team orchestration patterns as wheel primitive

## Summary

The `TaskCreate` + `addBlockedBy` + retrospective + safety-net-gate scaffolding currently lives in `kiln-build-prd` SKILL.md as orchestration prose. Extract it as a wheel teammate-orchestration primitive — `wheel:team-orchestrate` or similar — so any pipeline-style skill could use it without re-implementing the dependency wiring, the spawn ordering, the shutdown protocol, and the retrospective discipline.

## Why this matters

`kiln-build-prd` is the most-used skill in the kiln pipeline and has accumulated significant orchestration logic: spawn ordering, dependency graph (specifier → researcher → implementer → auditor → retrospective), shutdown protocol (READY TO SHUTDOWN gates), Step 4b lifecycle archival, mid-pipeline auditor checkpoint, debugger on-demand spawn. All of it is generic — none of it depends on kiln's PRD/spec semantics.

A future skill — say a hypothetical `clay:clay-build-product` that orchestrates a research-team + designer + scaffolder for a new product — would need the same scaffolding. Today that means duplicating ~600 lines of prose. Extracting to wheel makes orchestration patterns reusable.

## Why last (highest blast)

This is the largest extraction in the parent goal. It touches `kiln-build-prd` SKILL.md (the most-used kiln skill, with deep coupling to spec/plan/tasks/implement/audit/retrospective ceremony) AND introduces a new wheel mechanism that needs to be both flexible enough for non-kiln consumers and faithful enough that build-prd doesn't regress. Build it ONLY after #1, #2, #3 prove the extraction pattern works at smaller scopes. Need the friction-note primitive (#3) in place because friction notes ARE part of the orchestration contract.

## Scope (sketch — full design TBD in spec phase)

- New mechanism: `plugin-wheel/scripts/team-orchestrate/<helpers>.sh` exposing primitives for: spawn ordering with dep graph, READY-TO-SHUTDOWN protocol, retrospective spawn pattern, Step 4b-style lifecycle hooks (parameterized over what counts as "completion").
- Convention spec: `plugin-wheel/docs/team-orchestrate.md`.
- `kiln-build-prd` SKILL.md migrates to consume the wheel primitive. Spec/plan/tasks/implement/audit-specific bits stay in build-prd; team mechanics delegate to wheel.
- Cross-plugin smoke test: a minimal non-kiln consumer (could be a wheel-internal fixture) exercises team-orchestrate end-to-end.

## Acceptance

- `/kiln:kiln-build-prd` produces byte-identical pipeline behavior on a representative PRD pre/post extraction (modulo timestamps + UUIDs in agent IDs).
- A non-kiln consumer can spawn a 3-agent team via the wheel primitive without referencing any kiln-specific symbol.
- Retrospective spawn order, READY-TO-SHUTDOWN protocol, and Step 4b lifecycle archival are all parameterized — kiln-build-prd passes its specifics in, wheel doesn't hardcode them.

## Blast radius rationale

`cross-cutting`: this is the highest-leverage extraction in the parent goal but also the most invasive. Touches the most-used skill in the project. Coupled to the friction-note primitive (#3). Refactoring `kiln-build-prd` requires careful regression-testing across both successful pipeline runs (the happy path) AND failure modes (debugger spawn, retrospective gate, scope-change protocol). Plan a long review window.

## Dependencies

- `#1 (wheel-test-runner-extraction)` — need the substrate to test the orchestration primitive without going through `/kiln:kiln-build-prd` itself.
- `#3 (friction-note-primitive)` — friction notes are part of the orchestration contract; extracting orchestration without them creates an awkward seam.

## Open questions for spec phase

- How does the primitive interact with `kiln-build-prd`'s spec-first ceremony (specifier MUST run `/specify` → `/plan` → `/tasks` back-to-back)? Likely: the primitive doesn't know about kiln commands; it just spawns agents with prompts the caller provides.
- Should `Step 4b` lifecycle archival move to wheel as a generic "post-PR action hook," or stay in kiln (PRD-specific)? Probably stays — `derived_from:` is a PRD frontmatter convention, not a generic mechanism.
- Should the debugger on-demand spawn pattern be part of this primitive or a separate one? Likely separate — debugger is about ad-hoc team augmentation, orchestrate is about pre-planned dep graphs.
