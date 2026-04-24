---
id: 2026-04-20-0900-template-ergonomics
title: "Feedback: SKILL.md templates default to too much ceremony for trivial skills"
type: feedback
status: open
date: 2026-04-20T09:00:00Z
severity: medium
area: ergonomics
repo: ai-repo-template
---

# Feedback: SKILL.md templates default to too much ceremony for trivial skills

## What

The starter SKILL.md template bundled with `/kiln:kiln-init` includes a 14-section scaffold (User Input, Step 1 through Step N, Edge Cases, Contracts, etc.). For trivial skills — e.g. a one-liner wrapper around a shell command — 90% of the scaffold is empty boilerplate that the author deletes.

## Why it matters

New authors copy the full scaffold, half-fill it, and ship skills that LOOK complete but have empty Edge Cases / Contracts sections. Those empty sections then get flagged by the hygiene audit later, costing time.

## Preferred direction

Offer a `--minimal` flag on `/kiln:kiln-init` (or a second template shape in the templates dir) that skips the ceremony and ships a 30-line skeleton suitable for one-off wrappers. Keep the full template as the default for multi-step workflows.
