---
title: "Add summary step to shelf-full-sync workflow"
type: improvement
severity: low
category: workflow
source: manual
github_issue: null
status: open
date: 2026-04-08
---

## Description

The `shelf-full-sync` workflow should include a summary as its last step. Currently the workflow runs multiple sync operations (issues, docs, tech tags) but doesn't produce a consolidated summary of what was synced, created, updated, or skipped.

## Impact

Without a summary step, users have no quick way to see what the full sync actually did. They have to check individual output files or scroll through logs.

## Suggested Fix

Add a final `command` or `agent` step to `workflows/shelf-full-sync.json` that reads the outputs from prior steps and produces a short summary (e.g., "Synced 5 issues, 2 docs, updated tech tags. 1 issue closed.").
