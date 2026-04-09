---
title: "shelf-create should assess project progress holistically"
type: improvement
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

When `shelf-create` scaffolds a new project in Obsidian, it does not look at the project's actual state (e.g., existing specs, implemented features, test coverage, open issues, git history) to determine where the project stands. It creates the dashboard with default/blank progress regardless of how far along the project already is.

## Impact

Projects that are partially or fully built get created in Obsidian with no progress context, requiring manual updates via `shelf-update` to reflect reality. This makes the initial dashboard misleading and adds friction for onboarding existing projects into shelf.

## Suggested Fix

During `shelf-create`, inspect the repo for signals of progress — check for specs/, src/ or equivalent code dirs, test files, CI config, git commit count, open issues, VERSION file, etc. Use these signals to populate initial status, progress notes, and milestone data on the Obsidian dashboard so it reflects the project's actual state from day one.
