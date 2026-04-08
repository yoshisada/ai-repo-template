---
title: "Backlog issues should backlink to GitHub repos or file locations"
type: improvement
severity: medium
category: skills
source: manual
github_issue: null
status: open
date: 2026-04-08
---

## Description

Backlog issues in `.kiln/issues/` should include backlinks to the relevant GitHub repository and/or specific file locations in the codebase. Currently, issue files describe the problem but don't link back to the source code or repo context that the issue relates to.

This would make it easier to navigate from an issue directly to the relevant code, and would improve traceability between reported problems and their location in the codebase.

Potential additions to issue frontmatter:
- `repo: <github-repo-url>` — link to the GitHub repo
- `files: [<path1>, <path2>]` — list of relevant file paths
- `related_code: <file:line>` — specific code location

## Impact

Without backlinks, a reader must manually search the codebase to find the code related to an issue. This adds friction when triaging or fixing issues, especially in multi-repo setups or when issues reference specific plugin files.

## Suggested Fix

1. Update the issue template in the `report-issue` workflow to include optional `repo` and `files` fields in frontmatter
2. When the `create-issue` agent step runs, auto-detect the current repo URL via `gh repo view --json url` and populate the `repo` field
3. If the user's description references specific files or paths, extract them into the `files` field
4. Update the issue template in `plugin-kiln/templates/` if one exists
