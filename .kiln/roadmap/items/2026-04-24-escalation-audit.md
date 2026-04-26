---
id: 2026-04-24-escalation-audit
title: "Escalation audit — calibrate context-informed autonomy with evidence"
kind: feature
date: 2026-04-24
status: open
phase: 10-self-optimization
state: in-phase
blast_radius: feature
review_cost: moderate
context_cost: 2 sessions
---

# Escalation audit — calibrate context-informed autonomy with evidence

## What

A periodic review of `.wheel/history/` and skill-level pause points (`awaiting_user_input` events, confirm-never-silent prompts, hook blocks) that asks: when the system paused for a human, was precedent genuinely absent, or did the gate fire when it shouldn't have? Output is a list of pause events tagged "needed" / "shouldn't-have-fired" / "ambiguous" with suggested manifest improvements.

## Why now

Vision win-condition (b): "high-signal escalations, not friction." We ship `precedent-reader` to *use* precedent before pausing, but nothing closes the feedback loop on *whether the pause was right*.

## Open design questions (must resolve before promoting to 90-queued)

- **What counts as a pause event?** wheel `awaiting_user_input` is one signal, but skill-level confirm-never-silent prompts, hook blocks, and even `--quick`-bypass-of-interview are all autonomy decisions. Do we audit all of them, or focus on one substrate first?
- **How do we judge "shouldn't have fired"?** Either a human reviews each event, or we let the system propose its own verdict by re-checking precedent post-hoc. The latter is more autonomous but circular — the system grading its own reasoning.
- **Where does the verdict live?** As a manifest-improvement proposal in `@inbox/open/`? A new `.kiln/escalations/` artifact? Inline annotations on the wheel state files?
- **Cadence.** Real-time after each pause, batched weekly, or on-demand via `/kiln:kiln-escalation-audit`?
- **Relationship to manifest-evolution ledger.** This is upstream of that — pause events should feed the ledger. Need to design them together.

## Hardest part

Avoiding the circular trap where the system grades its own escalation decisions using the same precedent that failed to prevent them.

## Cheaper version

Just dump pause events to a markdown report with no verdict — humans triage the list once a month. Defer the auto-verdict ambition until we have a corpus of human-tagged events to learn from.
