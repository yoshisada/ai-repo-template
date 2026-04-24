---
id: 2026-04-24-live-chat-debugging-for-self-optimizing
title: "Live chat debugging for self-optimizing plugin design"
kind: research
date: 2026-04-24
status: open
phase: unsorted
state: planned
blast_radius: isolated
review_cost: moderate
context_cost: 2 sessions
depends_on:
  - 2026-04-24-skill-ab-harness-wheel-workflow
  - 2026-04-24-wheel-per-step-model-selection
---

# Live chat debugging for self-optimizing plugin design

need to add a way to optimize plugin design by debugging each chat even an agent team and feed it back in as live feedback looking for token improvement or mistakes. expensive but critically worth it.

## Decision this unblocks

What's the right shape for an opt-in chat recorder + retrospective auditor — a skill the user invokes to start recording a session (main chat + sub-agent traces), then later queries for efficiency wins, mistakes, and misunderstandings that should feed back into skill / context improvement?

This is **not** always-on auto-instrumentation. The user invokes a recorder, drives a session, then queries the recording afterward for retrospective audit.

## Time-box

2 sessions to produce a working retrospective-audit prototype. Output is a prototype, not a written cost-shape comparison.

## What "done" looks like

A working prototype (one-off script under `plugin-kiln/scripts/chat-audit/`) that takes one recorded chat transcript as input and emits a structured improvement-proposal markdown at `.kiln/audits/<session-id>.md` containing:

- per-skill token usage
- identified misunderstandings between user and agent
- suggested skill-prompt edits

**Fork condition.** If the prototype catches genuinely actionable signal, the research closes by spawning a follow-up `kind: feature` for the real `/kiln:kiln-audit-chat` skill. If it does not, close with a written negative-result note explaining why the signal was insufficient.

## Audience

The maintainer (yoshisada). The audit output feeds a follow-up `kind: feature` PRD that wraps the prototype into a real `/kiln:kiln-audit-chat` skill.

## Cheapest directional answer first

Manually replay 3-5 recent kiln-build-prd transcripts from `.kiln/logs/` through a one-off Claude prompt asking *"where did this session waste tokens or misunderstand the user?"* — note that `.kiln/logs/` won't contain full chat transcripts, so this is a depth-gauging probe, not a full test. If the partial signal is already actionable, the full-transcript version will be more so. If even the partial signal is too noisy, that itself is a finding (suggests the auditor needs richer input than a log file).

## Why this matters in roadmap context

Completes a trio with two sibling items captured the same day:

- `2026-04-24-skill-ab-harness-wheel-workflow` — the deterministic test bed for proposed plugin changes.
- `2026-04-24-wheel-per-step-model-selection` — the lever (right-size the model per step).
- This item — the signal source telling the maintainer *which* changes to make and *which* levers to pull.

Picks up where phase `07-feedback-loop` (completed 2026-04-24) left off: that phase shipped passive observability (`.kiln/logs/`, retrospectives); this is the active loop that turns observations into proposed plugin edits.
