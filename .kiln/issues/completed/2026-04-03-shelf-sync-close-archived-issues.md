---
title: "shelf-sync should close Obsidian notes for archived backlog issues"
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

When backlog issues are moved to `.kiln/issues/completed/`, their corresponding Obsidian issue notes still show `status: open`. The `/shelf-sync` command should detect that a backlog source file no longer exists in `.kiln/issues/` (but does exist in `.kiln/issues/completed/`) and automatically update the Obsidian note to `status: closed`.

Currently this requires manual intervention after running `/kiln-cleanup`.

## Expected Behavior

During sync, for each existing Obsidian note with `source: "backlog:*"`:
1. Check if the source file still exists in `.kiln/issues/`
2. If not, check `.kiln/issues/completed/` — if found there, update the Obsidian note to `status: closed`
3. Track this in the sync summary as "Closed: N notes marked closed"
prd: docs/features/2026-04-03-shelf-sync-v2/PRD.md
