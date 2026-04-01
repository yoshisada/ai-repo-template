---
title: "Move completed issues to a completed folder to reduce clutter"
type: improvement
severity: medium
category: workflow
source: manual
github_issue: null
status: open
date: 2026-04-01
---

## Description

As issues are resolved, they remain in `.kiln/issues/` alongside open items, making it harder to scan for actionable work. Completed issues should be moved to `.kiln/issues/completed/` to keep the active backlog clean while preserving history.

## Impact

- The `.kiln/issues/` folder grows unbounded over time, mixing resolved and open items
- `/issue-to-prd` and manual triage have to filter through noise to find actionable issues
- No clear lifecycle for issues — `status: closed` in frontmatter exists but files stay in the same directory

## Suggested Fix

1. When an issue's status is set to `closed` or `done`, move the file to `.kiln/issues/completed/`
2. Update `/report-issue` and `/issue-to-prd` skills to be aware of the `completed/` subdirectory
3. Ensure `/issue-to-prd` only scans top-level `.kiln/issues/` (not `completed/`) for bundling
