---
title: "Enable kiln-doctor to clean up .kiln subfolders based on templates/manifests"
type: feature-request
severity: medium
category: skills
source: manual
github_issue: null
status: open
date: 2026-04-01
---

## Description

Extend `/kiln-doctor` with a cleanup mode that prunes stale or unnecessary files from `.kiln/` subfolders. The doctor already validates structure against a manifest (see `2026-03-31-kiln-doctor-manifest.md`), but it doesn't actively clean up accumulated artifacts — orphaned logs, old QA runs, completed issues still in the active folder, etc.

The cleanup should be template/manifest-driven: define retention rules per subfolder (e.g., keep last N log runs, archive completed issues, remove stale lock files) and let `kiln-doctor --cleanup` apply them.

## Impact

- `.kiln/logs/`, `.kiln/qa/`, and `.kiln/issues/` accumulate files over time with no automated cleanup
- Users must manually identify and remove stale artifacts
- Large `.kiln/` directories slow down glob/grep operations and add noise to file explorers

## Suggested Fix

1. Add retention/cleanup rules to the kiln manifest (e.g., `logs: keep_last: 10`, `issues: archive_completed: true`)
2. Add a `--cleanup` flag to `/kiln-doctor` that applies these rules
3. Support dry-run mode (`--cleanup --dry-run`) so users can preview what would be removed
4. Integrate with the completed-issues archival flow (see `2026-04-01-archive-completed-issues.md`)
