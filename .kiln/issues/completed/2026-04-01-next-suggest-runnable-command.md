---
title: "/next and /resume should suggest a specific command to run next"
type: friction
severity: medium
category: skills
source: manual
github_issue: null
status: prd-created
date: 2026-04-01
---

## Description

When running `/next` (or the deprecated `/resume`), the output lists recommendations with commands but doesn't clearly call out a single "run this next" suggestion. The user has to scan the full list and decide which item to act on first. The skill should end with a clear, prominent suggestion of the single highest-priority command to run, making it easy to just copy-paste and go.

## Impact

Adds friction at session start — the user runs `/next` to figure out what to do, but still has to parse the output and decide. A clear "suggested next action" line at the bottom would reduce cognitive load and speed up session pickup.

## Suggested Fix

- At the end of the `/next` terminal output, add a prominent line like:
  ```
  Suggested next: `/implement` — 3 incomplete tasks in specs/auth/tasks.md
  ```
- Pick the highest-priority, most actionable item from the recommendations list
- Format it so it's visually distinct (e.g., bold, separated by a line)

prd: docs/features/2026-04-01-kiln-polish/PRD.md
