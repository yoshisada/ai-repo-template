---
title: "shelf-sync should update project tech stack tags during sync"
type: improvement
severity: medium
category: skills
source: manual
github_issue: null
status: completedcompleted_date: 2026-04-23
pr: merged-pre-tracking
date: 2026-04-03
---

## Description

The `/shelf-sync` command should re-detect the repo's tech stack (same logic as `/shelf-create` Step 4) and update the Obsidian project dashboard's `tags` frontmatter if they've changed. This keeps the project tags current as dependencies evolve — new frameworks added, old ones removed, etc.

Currently tags are only set during `/shelf-create` and never updated, so they drift over time.

## Expected Behavior

During sync, after issue sync completes:
1. Re-run tech stack detection (scan package.json, tsconfig.json, Cargo.toml, etc.)
2. Compare detected tags with current dashboard `tags` frontmatter
3. If different, update the dashboard with the merged tag set
4. Report in sync summary: "Tags updated: +2 added, -1 removed" or "Tags: unchanged"
prd: docs/features/2026-04-03-shelf-sync-v2/PRD.md
