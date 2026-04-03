---
title: "Auto-mark prd-created issues as completed after build-prd finishes"
type: improvement
severity: medium
category: workflow
source: manual
github_issue: null
status: prd-created
prd: docs/features/2026-04-01-pipeline-workflow-polish/PRD.md
date: 2026-04-01
---

## Description

Issues in `.kiln/issues/` with `status: prd-created` are not automatically updated after the `/build-prd` pipeline completes successfully. They should be marked as `status: completed` (or similar) once the pipeline finishes and the PR is created.

Currently, issues transition from `open` → `prd-created` (via `/issue-to-prd`) but then stall — there's no lifecycle hook at the end of `/build-prd` to close them out.

## Impact

- Stale `prd-created` issues accumulate in the backlog, creating noise
- Users must manually update issue status after a successful pipeline run
- `/issue-to-prd` and `/analyze-issues` may re-surface issues that are already addressed

## Suggested Fix

1. At the end of the `/build-prd` pipeline (after PR creation), scan `.kiln/issues/` for entries with `status: prd-created` whose `prd:` field matches the PRD that was just built
2. Update their status to `completed` and add a `completed_date` and `pr` field linking to the created PR
3. Alternatively, integrate this into the retrospective step that already runs at the end of `/build-prd`
