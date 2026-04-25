## Issue Created

**File**: `.kiln/issues/2026-04-25-standardize-git-behavior-across-scope.md`
**Title**: Standardize git behavior across the entire scope
**Date**: 2026-04-25
**Status**: open
**Kind**: improvement
**Priority**: medium
**Repo**: https://github.com/yoshisada/ai-repo-template
**Tags**: git, hygiene, cross-plugin, workflow
**Source**: kiln-report-issue

## Duplicate check

Scanned `.kiln/issues/*.md` for `git behavior`, `git workflow`, `git practices`, `standardize git` — no matches. No duplicate found.

## Description summary

Git behavior is inconsistent across the kiln/wheel/shelf/clay/trim plugin scope and across the pipeline lifecycle. Six concrete inconsistencies documented in the issue (branch naming, auto-commits, version-bump fan-out, merge strategy ambiguity, local-vs-remote divergence after `gh pr merge`, `--no-verify` discipline). Goal: a single `docs/git-conventions.md` pinning the standard, then audit existing hooks/skills/agents for compliance.

## Source context

Captured during PR #163 (cross-plugin-resolver) post-merge cleanup, which surfaced 3 of the 6 inconsistencies in a single session.
