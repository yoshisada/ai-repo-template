---
id: 2026-04-24-retro-quality-auditor
title: "Retro-quality auditor — enforce the senior-engineer-merge bar at retro layer"
kind: feature
date: 2026-04-24
status: open
phase: 89-brainstorming
state: planned
blast_radius: feature
review_cost: moderate
context_cost: 2 sessions
---

# Retro-quality auditor — enforce the senior-engineer-merge bar at retro layer

## What

An auditor (likely an agent spawned at the end of `/kiln:kiln-build-prd`, or a standalone `/kiln:kiln-retro-audit` skill) that scores retro outputs for substance — does the retro contain a real insight, or is it filler ("everything went smoothly, no issues")? Flags low-substance retros for rework or supplemental human input.

## Why now

Vision says explicitly: "retros with actual insight" is part of the senior-engineer-merge bar. Right now nothing distinguishes a meaningful retro from a templated one — the build-prd retrospective agent produces them but no second pass evaluates quality.

## Open design questions (must resolve before promoting to 90-queued)

- **System-design dependency.** Like manifest-evolution-ledger and escalation-audit, this is part of the broader observability/quality-gate layer. Building it standalone risks duplicate plumbing.
- **What is "real insight"?** Concrete: a non-obvious cause-and-effect claim, a calibration update ("we estimated X, took 3X — here's why"), a process change proposal. Vague: "good collaboration." The auditor needs a rubric, not vibes.
- **Action on low-substance.** Re-spawn the retrospective agent with a "be more specific" prompt? Surface to human with a request for supplemental input? Just tag the retro and let it ship?
- **Where does the rubric live?** Hardcoded in the agent prompt? In a manifest type (`@manifest/types/retro.md`) so it can evolve via shelf proposals?
- **Volume.** If we run audits inside every build-prd, we add latency and tokens. Worth it?

## Hardest part

Defining "insight" in a way that's mechanizable without becoming pedantic — bad retros that pass and good retros that fail are both worse than no auditor.

## Cheaper version

Skip auditing inline; have the agent produce a retro AND a self-rated insight score (1-5 with justification) at write-time. Humans review low scores. No second pass, no separate skill. If self-rating turns out to be unreliable (likely), upgrade to a separate auditor.

## Dependencies

- Should be designed alongside `manifest-evolution-ledger` and `escalation-audit` — all three are observability features and want shared infrastructure.
