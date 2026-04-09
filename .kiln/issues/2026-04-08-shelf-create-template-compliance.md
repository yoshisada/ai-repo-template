---
title: "shelf-create not following Obsidian template; add repair function"
type: bug
severity: high
category: skills
source: manual
github_issue: null
status: prd-created
prd: docs/features/2026-04-08-shelf-skills-polish/PRD.md
date: 2026-04-08
---

## Description

`shelf-create` does not consistently follow the Obsidian project template when scaffolding new projects. The generated dashboard and note structure diverges from the expected template format, leading to inconsistent project pages in Obsidian.

Additionally, there is no way to "repair" or re-apply the template to existing projects when the template is updated — you'd have to manually fix each project's Obsidian notes.

## Impact

Projects created with shelf-create may have missing sections, wrong formatting, or inconsistent structure compared to what the template defines. When the template evolves, existing projects fall behind with no automated path to update them.

## Suggested Fix

1. Audit `shelf-create` to ensure it reads and strictly follows the Obsidian template for all note types (dashboard, about, issues, docs)
2. Add a `shelf-repair` or `shelf-update-template` skill that re-applies the current template to an existing project's Obsidian notes, preserving user content while updating structure/formatting
