---
last_updated: 2026-04-25
---

# Product Vision

<!--
Frozen pre-PRD fixture for vision-tooling NFR-005 / SC-009.
This file captures a stable, populated vision.md state that the back-compat test re-uses
to assert the coached-interview path (no new simple-params flags) preserves byte-identity.
-->

## What we are building

A mostly-autonomous build system for a solo builder. _frozen-fixture-bullet_

## What it is not

Not a fully autonomous system that acts without precedent. _frozen-fixture-bullet_

## How we'll know we're winning

- An idea captured via `/clay:clay-idea` reaches a reviewed PR. _frozen-fixture-signal_

## Guiding constraints

- **Context-informed autonomy** — the system deliberates over precedent before acting.
- **Propose constantly, apply never unilaterally** — proposals route through human apply.
- **File-based state** — no services; everything persists in the repo.
- **Spec-first, non-negotiable** — 4-gate hooks enforce spec + plan + tasks + `[X]`.
