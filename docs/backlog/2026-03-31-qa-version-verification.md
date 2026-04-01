---
title: "QA engineer must verify latest build before evaluating"
type: friction
severity: high
category: agents
source: manual
github_issue: null
status: prd-created
date: 2026-03-31
---

## Description

The qa-engineer agent in `/build-prd` often evaluates a stale build — it starts testing without confirming the app was rebuilt after the latest code changes. This leads to false findings (bugs already fixed) or missed issues (new code not reflected).

The fix: before any evaluation begins, the qa-engineer should check the version displayed in the bottom-right corner of the page and verify it matches the latest git commit. If it doesn't match, the agent should trigger a rebuild and wait for it to complete before proceeding.

## Impact

QA results are unreliable when testing against stale builds. Implementers waste time investigating findings that don't reproduce because the build was outdated. This has happened repeatedly during pipeline runs.

## Suggested Fix

- Add a pre-flight step to the qa-engineer agent (`plugin/agents/qa-engineer.md`): before any testing, navigate to the app, read the version string from the bottom-right of the page, and compare it against the latest commit hash or VERSION file
- If version mismatch: run the build command (e.g., `npm run build` or restart dev server), wait for completion, then re-check
- If version still doesn't match after rebuild: warn the team lead and proceed with a note in the report
- Also add this check to `/qa-pass` and `/ux-evaluate` pre-flight steps

prd: docs/features/2026-03-31-kiln-rebrand-and-qa/PRD.md
