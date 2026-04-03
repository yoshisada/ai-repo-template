---
title: "Add .shelf-config artifact to track Obsidian vault path for shelf sync"
type: feature-request
severity: high
category: scaffold
source: manual
github_issue: null
status: prd-created
prd: docs/features/2026-04-03-shelf-config-artifact/PRD.md
date: 2026-04-03
---

## Description

The shelf plugin skills (shelf-sync, shelf-update, shelf-status, etc.) need to know which Obsidian directory a project is tracked in. Currently the base path defaults to `projects` and the slug is derived from the git remote, but there's no persistent artifact in the repo that records the actual resolved path.

A `.shelf-config` file should be created by `/shelf-create` and read by all shelf skills, storing:
- The Obsidian base path (e.g., `@second-brain/projects`)
- The project slug (e.g., `plugin-shelf`)
- The full resolved path to the project dashboard

This prevents mismatches when the repo name differs from the Obsidian project slug (as happened with `obsidian-project-tracker` → `plugin-shelf`).
