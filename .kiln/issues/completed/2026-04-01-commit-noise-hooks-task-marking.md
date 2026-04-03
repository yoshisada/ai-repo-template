---
title: "Excessive commit noise from version hooks and task-marking on small features"
type: friction
severity: low
category: workflow
source: analyze-issues
github_issue: "#25, #20, #19"
status: prd-created
prd: docs/features/2026-04-01-pipeline-workflow-polish/PRD.md
date: 2026-04-01
---

## Description

Three sources of commit noise in pipeline runs:

### 1. Version-increment hook creates separate commits
The version-increment hook modifies files on every edit, which then need to be committed separately as "chore: commit hook-modified files" or "chore: sync version bump from hooks." In #25, 2 of 10 commits were housekeeping for hook-modified files rather than feature work.

### 2. Task-marking creates dedicated commits
Marking tasks `[X]` in tasks.md generates separate commits like "mark T004 complete" and "mark T005/T006 complete." For small features (#20: 6 tasks, 2 files, ~20 lines), this creates commit noise without proportional value.

### 3. Combined effect is extreme for small features
In #19 (a11y fixes — 4 files changed), 66 commits were produced. Many were QA result snapshots, incremental test-result updates, and fix iterations.

## Impact

Low — doesn't block work but makes git history noisy and PR review harder. Proportionally worse for small features.

## Suggested Fix

1. **Fold hook changes into phase commits**: Version bump should be included in the phase commit, not a separate chore commit
2. **Scale task-marking for small features**: For features with <=1 phase of implementation, combine task-marking updates into the implementation commit rather than creating separate commits
3. **Don't commit QA artifacts to the branch**: QA results/snapshots should not inflate the commit count

## Source Retrospectives

- #25: 2/10 commits were hook housekeeping
- #20: Task-marking commits added noise for a 6-task feature
- #19: 66 commits for a 4-file change
