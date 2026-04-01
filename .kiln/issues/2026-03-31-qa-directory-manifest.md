---
title: "Create manifest and folder structure for QA directory"
type: improvement
severity: medium
category: scaffold
source: manual
github_issue: null
status: prd-created
date: 2026-03-31
---

## Description

The QA directory (`.kiln/qa/`) needs a defined manifest and folder structure. Currently there is no standardized layout for QA artifacts, test infrastructure, or configuration within the `.kiln/qa/` directory.

## Impact

Without a defined structure, QA-related files (Playwright config, test matrices, `.env.test`, test results, screenshots/videos) have no canonical location. This makes it harder for QA agents (`qa-engineer`, `qa-setup`, `qa-pass`) to consistently find and produce artifacts, and for users to understand where QA outputs live.

## Suggested Fix

Define a manifest (e.g., `.kiln/qa/manifest.json` or section in the plugin manifest) that specifies the expected folder structure, and update `/qa-setup` and the scaffold to create it. Expected subdirectories might include `tests/`, `results/`, `screenshots/`, `videos/`, and config files.

prd: docs/features/2026-04-01-kiln-polish/PRD.md
