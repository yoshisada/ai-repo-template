---
title: "Branch and spec directory naming is inconsistent — causes agent confusion"
type: friction
severity: medium
category: workflow
source: analyze-issues
github_issue: "#28, #16, #9"
status: prd-created
prd: docs/features/2026-04-01-pipeline-workflow-polish/PRD.md
date: 2026-04-01
---

## Description

Three related naming problems:

### 1. Branch naming convention not enforced
Specs declare `build/<feature>-<date>` but actual branches use various formats: `001-kiln-polish`, `feature/vnc-fixes-dashboard-ux`, `014-tamagui-takeout-starter`. No enforcement exists — the branch creation step doesn't consistently follow any convention.

### 2. Spec directory naming mismatch
In #9, the team lead referenced `specs/takeout-starter/` but the actual path was `specs/013-takeout-starter/`. In #28, the spec declared one branch name but another was created. 4/5 agents in #9 wasted time globbing the filesystem to find files.

### 3. Branches carry commits from prior features
In #16, the feature branch contained commits from 3 prior features, making `git log main..HEAD` noisy (20+ commits) and PR review harder.

## Impact

Medium — agents waste time finding files, retrospective agents reference wrong branches, and PR diffs are polluted with unrelated commits.

## Suggested Fix

1. **Enforce branch naming**: Add explicit instruction to team-lead prompt: "Branch name MUST follow `build/<feature-slug>-<YYYYMMDD>`. Do not use numeric prefixes."
2. **Specifier owns branch creation**: Don't pre-create the feature branch. Let the specifier create it and broadcast the canonical name to all teammates.
3. **Fresh branches per feature**: Each `build-prd` run should create a new branch from `main` rather than reusing an existing feature branch.

## Source Retrospectives

- #28: Branch naming mismatch between spec and actual branch
- #16: Branch carried commits from 3 prior features
- #9: Spec directory naming caused 4/5 agents to waste time
