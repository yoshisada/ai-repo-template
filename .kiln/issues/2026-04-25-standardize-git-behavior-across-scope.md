---
title: Standardize git behavior across the entire scope
date: 2026-04-25
status: open
kind: improvement
priority: medium
repo: https://github.com/yoshisada/ai-repo-template
tags:
  - git
  - hygiene
  - cross-plugin
  - workflow
source: kiln-report-issue
---

# Standardize git behavior across the entire scope

## Description

Git behavior is inconsistent across the kiln/wheel/shelf/clay/trim plugin scope and across the pipeline lifecycle (branching, committing, merging, pushing). Need a single standard so the build-prd pipeline, hooks, and ad-hoc developer flow all behave the same way.

## Observed inconsistencies

- **Branch naming**: legacy `feature/*` and current `build/*` prefixes coexist. `require-feature-branch.sh` accepts both, but the convention is unclear and pipeline scripts assume one or the other inconsistently.
- **Auto-commits**: `kiln-build-prd` auto-commits "working changes before pipeline branch" with a generic message — multiple such commits can stack across pipelines and clutter history (observed today: `38d2d92` orphan + this session's `cd061a3`).
- **Version-bump fan-out**: every Edit/Write triggers `version-increment.sh` bumping VERSION + 5× `package.json` + 5× `plugin.json` — large per-edit churn that gets bundled into unrelated commits (auditor flagged this on PR #163 as out-of-scope drift).
- **Merge strategy**: PR #163's NFR-F-7 atomic-landing assumed squash-merge but the spec was ambiguous. Different PRs are merged with different strategies; no documented default.
- **Local-vs-remote divergence**: `gh pr merge --squash --delete-branch` switched the local checkout to a stale `main`, producing a divergence the user had to manually reconcile.
- **`--no-verify` discipline**: hook bypassing rules aren't consistently documented across plugins.

## Goal

A single `docs/git-conventions.md` (or extension to constitution) that pins:
1. Branch prefix policy (one prefix, document the migration path off legacy `feature/*`)
2. Commit message conventions (subject prefix, when to squash, when to fast-forward)
3. Default merge strategy + when to deviate
4. Version-bump-hook scope (which files, when to skip)
5. Local-vs-remote sync rituals before/after merge
6. `--no-verify` and `--force-push` policy

Then audit existing hooks/skills/agents for compliance and fix the outliers.

## Source

Captured during PR #163 (cross-plugin-resolver) post-merge cleanup. The merge surfaced 3 of the 6 inconsistencies above in a single session.
