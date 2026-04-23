---
title: "Rename speckit-harness to kiln"
type: improvement
severity: medium
category: other
source: manual
github_issue: null
status: completedcompleted_date: 2026-04-23
pr: merged-pre-tracking
date: 2026-03-31
---

## Description

Rename the project from "speckit-harness" to "kiln" across all references — plugin name, npm package, skill prefixes, documentation, CLAUDE.md, and any user-facing strings.

## Impact

Affects the entire plugin identity: npm package name (`@yoshisada/speckit-harness`), plugin.json name, skill namespace (`speckit-harness:*`), all documentation references, and the repo template branding.

## Suggested Fix

- Rename npm package to `@yoshisada/kiln` (or similar)
- Update `plugin.json` name field
- Rename skill prefixes from `speckit-harness:` to `kiln:` (or drop the prefix)
- Update all references in CLAUDE.md, README, scaffold templates
- Decide whether internal skill names like `speckit-specify`, `speckit-plan`, etc. also change (e.g., `kiln-specify` or just `specify`)

prd: docs/features/2026-03-31-kiln-rebrand-and-qa/PRD.md
