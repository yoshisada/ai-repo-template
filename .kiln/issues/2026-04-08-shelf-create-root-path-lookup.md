---
title: "shelf-create should start at vault root when finding project directory"
type: friction
severity: medium
category: skills
source: manual
github_issue: null
status: prd-created
prd: docs/features/2026-04-08-shelf-skills-polish/PRD.md
date: 2026-04-08
---

## Description

`shelf-create` wastes ~2 MCP queries trying to guess the correct Obsidian directory path for placing project files. It should instead always start at the vault root (`/`) and navigate from there to find or create the projects directory.

## Impact

Each `shelf-create` invocation burns unnecessary tool calls on path guessing, adding latency and token cost. This adds up across multiple project scaffolds.

## Suggested Fix

Update the `shelf-create` skill to always begin its directory lookup from the vault root rather than guessing paths. Use the Obsidian MCP `list_files` at `/` first, then navigate to the known projects directory structure directly.
