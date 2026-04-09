---
title: "/next should only recommend high-level commands, not low-level pipeline steps"
type: improvement
severity: medium
category: skills
source: manual
github_issue: null
status: completed
prd: docs/features/2026-04-09-plugin-polish-and-skill-ux/PRD.md
completed_date: 2026-04-09
pr: "#82"
date: 2026-04-08
---

## Description

The `/next` command currently suggests low-level pipeline steps like `/specify`, `/plan`, `/tasks`, and `/implement` as next actions. These are internal steps of the `/build-prd` pipeline and should not be recommended directly to users.

`/next` should only recommend high-level entry-point commands such as:
- `/build-prd` — full pipeline
- `/fix` — bug fixes
- `/qa-pass` — standalone QA
- `/create-prd` — new PRD creation
- `/create-repo` — new repo setup
- `/init` — project initialization
- `/analyze-issues` — issue triage
- `/report-issue` — log a bug/improvement
- `/ux-evaluate` — standalone UX review
- `/issue-to-prd` — bundle issues into PRD

Low-level commands like `/specify`, `/plan`, `/tasks`, `/implement`, `/audit`, `/debug-diagnose`, `/debug-fix` are meant to be orchestrated by higher-level commands and should not appear in `/next` output.

## Impact

Users get confused by seeing low-level workflow steps as suggestions, especially when they should be running `/build-prd` instead of manually stepping through the pipeline.

## Suggested Fix

Update the continuance agent (used by `/next`) to filter its command recommendations to only include high-level user-facing commands. Maintain a whitelist of recommended commands or a blacklist of internal-only commands.
