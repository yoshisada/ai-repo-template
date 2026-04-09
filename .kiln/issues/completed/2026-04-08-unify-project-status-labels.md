---
title: "Unify project status labels across shelf skills"
type: friction
severity: medium
category: skills
source: manual
github_issue: null
status: completed
prd: docs/features/2026-04-08-shelf-skills-polish/PRD.md
date: 2026-04-08
completed_date: 2026-04-09
pr: "#73"---

## Description

The `shelf-create` skill sometimes marks new projects as "in progress" rather than "active". There is no single canonical list of project status values shared across shelf skills (`shelf-create`, `shelf-update`, `shelf-status`), leading to inconsistent labels in Obsidian dashboards.

## Impact

Users see different status labels for the same logical state across projects, making the Obsidian dashboard unreliable for at-a-glance project tracking. Filtering or querying by status becomes error-prone.

## Suggested Fix

Define a canonical set of project status values (e.g., `idea`, `active`, `paused`, `completed`, `archived`) in a shared location (e.g., shelf config or a constants section in the shelf plugin). Update `shelf-create`, `shelf-update`, and `shelf-status` to reference and validate against this list.
