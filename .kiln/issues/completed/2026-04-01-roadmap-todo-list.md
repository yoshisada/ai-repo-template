---
title: "Add a lightweight roadmap/todo for tracking future work ideas"
type: feature-request
severity: low
category: workflow
source: manual
github_issue: null
status: prd-created
prd: docs/features/2026-04-01-pipeline-workflow-polish/PRD.md
date: 2026-04-01
---

## Description

Create a non-invasive way to track ideas for future work — things the user wants to do eventually but doesn't know when the right time is. Think of it as a personal roadmap or "someday" list, distinct from actionable issues in `.kiln/issues/`.

Issues are for concrete bugs/improvements ready to be worked on. This is for softer ideas — "I'd like to explore X", "eventually we should do Y" — that aren't ready for a PRD but shouldn't be forgotten. A simple `.kiln/roadmap.md` or `.kiln/todo.md` file with categorized bullet points would suffice.

## Impact

- Users currently have no place to capture "someday" ideas without creating a full issue
- Ideas get lost between sessions because there's no lightweight capture mechanism
- `/next` and `/issue-to-prd` surface actionable work, but there's no equivalent for aspirational/exploratory items

## Suggested Fix

1. Add a `.kiln/roadmap.md` file — a simple markdown list grouped by theme (e.g., "DX improvements", "New capabilities", "Tech debt")
2. Create a `/todo` or `/roadmap` skill that appends items to this file with a one-liner
3. Have `/next` optionally surface roadmap items when there's no urgent work — "Nothing pressing. Here are some ideas from your roadmap..."
4. Keep it intentionally lightweight — no frontmatter, no status tracking, just a list
