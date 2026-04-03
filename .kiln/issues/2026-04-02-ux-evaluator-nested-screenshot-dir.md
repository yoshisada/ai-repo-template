---
title: "UX evaluator creates nested .kiln/qa/.kiln/qa/screenshots/ due to relative path"
type: bug
severity: medium
category: agents
source: manual
github_issue: null
status: open
date: 2026-04-02
---

## Description

The UX evaluator QA agent runs `mkdir -p .kiln/qa/screenshots` using a relative path while its working directory is already `.kiln/qa/` (e.g., after `cd .kiln/qa` to run Playwright). This creates `.kiln/qa/.kiln/qa/screenshots/` instead of writing to the intended `.kiln/qa/screenshots/`. The nested directory accumulates stale screenshot artifacts that survive cleanup passes, since `/kiln-cleanup` only purges known artifact subdirectories, not nested `.kiln/` trees.

## Impact

- Stale screenshots accumulate in the wrong directory and are never cleaned up
- Disk space waste compounds across QA runs
- Screenshots may not be found by other tools expecting them at `.kiln/qa/screenshots/`

## Suggested Fix

Use absolute paths (e.g., `${REPO_ROOT}/.kiln/qa/screenshots/`) in the agent's screenshot output directory, or ensure agents always `cd` back to the repo root before creating artifact directories. Also consider updating `/kiln-cleanup` to detect and remove nested `.kiln/` trees as a safety net.
