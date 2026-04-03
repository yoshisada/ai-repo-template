---
title: "Add /kiln-cleanup command to purge QA artifacts, integrate into /kiln-doctor"
type: feature-request
severity: medium
category: skills
source: manual
github_issue: null
status: prd-created
prd: docs/features/2026-04-01-pipeline-workflow-polish/PRD.md
date: 2026-04-01
---

## Description

Add a `/kiln-cleanup` skill that cleans up the `.kiln/qa/` folder — removing old Playwright reports, video recordings, traces, and screenshots that accumulate across QA runs. This command should also run automatically as part of `/kiln-doctor` (e.g., in fix mode).

Additionally, cleanup should scan `.kiln/issues/` for issues that have been implemented (e.g., `status: prd-created` or `status: completed`) and archive/move them out of the active issues folder so they don't clutter the backlog.

## Impact

- QA artifacts (videos, traces, HTML reports) pile up quickly, especially with `video: 'on'` — eating disk space and cluttering the project
- No automated way to purge stale QA output today; users must manually delete files
- Related to the QA performance issue (`2026-04-01-qa-engineer-performance.md`) — even with `retain-on-failure`, artifacts accumulate over time

## Suggested Fix

1. Create a new `/kiln-cleanup` skill that:
   - Removes `.kiln/qa/` contents (test-results, playwright-report, videos, traces)
   - Supports a `--dry-run` flag to preview what would be deleted
   - Optionally accepts a retention policy (e.g., keep last N runs)
2. Hook it into `/kiln-doctor` fix mode so running `kiln-doctor --fix` also cleans stale QA artifacts
3. Scan `.kiln/issues/` for completed/implemented issues and move them to `.kiln/issues/archive/`
4. See also: `2026-04-01-kiln-doctor-cleanup.md` for the broader cleanup manifest approach
