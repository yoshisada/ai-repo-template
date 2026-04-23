---
title: "Add docs sync to shelf-sync — push PRD summaries to Obsidian"
type: feature-request
severity: medium
category: skills
source: manual
github_issue: null
status: completedcompleted_date: 2026-04-23
pr: merged-pre-tracking
date: 2026-04-03
---

## Description

The `/shelf-sync` command should sync docs from the repo to Obsidian, not just issues. During sync:

1. Scan `docs/features/*/PRD.md` for feature PRDs
2. For each PRD, create or update a summary doc note at `{base_path}/{slug}/docs/{feature-slug}.md`
3. Include title, summary, FR/NFR counts, and status in frontmatter
4. Skip unchanged docs (compare file modification time or content hash)
5. Report in sync summary: "Docs: N created, N updated, N skipped"

This keeps the Obsidian project docs section populated automatically as new features are built.
prd: docs/features/2026-04-03-shelf-sync-v2/PRD.md
