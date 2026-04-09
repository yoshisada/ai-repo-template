---
title: "report-issue-and-sync workflow must ship with the kiln plugin"
type: bug
severity: high
category: scaffold
source: manual
github_issue: null
status: prd-created
prd: docs/features/2026-04-09-plugin-polish-and-skill-ux/PRD.md
date: 2026-04-08
---

## Description

The `/report-issue` skill was refactored to delegate to `/wheel-run report-issue-and-sync`, but the `report-issue-and-sync.json` workflow currently lives in the local `workflows/` directory of this repo only. It is not included in the `plugin-kiln` package, so consumer projects that install `@yoshisada/kiln` won't have the workflow available. The skill will fail when it tries to run the workflow.

## Impact

`/report-issue` is broken for all consumer projects — the skill delegates to a workflow that doesn't exist in their project.

## Suggested Fix

Either:
1. Include `report-issue-and-sync.json` in the kiln plugin's `workflows/` directory and declare it in `plugin.json` so wheel can discover it as a plugin workflow
2. Or have `init.mjs` scaffold the workflow into the consumer project's `workflows/` directory during setup
