---
title: "Add kiln doctor — manifest-based state validation and migration"
type: feature-request
severity: medium
category: skills
source: manual
github_issue: null
status: open
date: 2026-03-31
---

## Description

Build a `kiln doctor` system that defines the ideal `.kiln/` directory structure as a manifest, compares current project state against it, and reports/fixes discrepancies. Three capabilities:

1. **Manifest** — a declarative definition of the expected `.kiln/` structure (directories, naming conventions, required files per context). Acts as the single source of truth for what "perfect state" looks like.

2. **Doctor (diagnose)** — diffs the current project state against the manifest. Reports what's missing, misplaced, stale, or incorrectly named. Covers migration of legacy paths (e.g., `docs/backlog/` → `.kiln/issues/`, `qa-results/` → `.kiln/qa/`) and ongoing hygiene (orphaned runs, stale artifacts from deleted branches).

3. **Fix (prompt to resolve)** — for each issue found, prompts the user with a suggested fix (move file, create directory, archive stale run, etc.) and applies it on confirmation. Idempotent — safe to run repeatedly.

## Impact

Enables clean migration for existing consumer projects upgrading to `.kiln/`. Also provides ongoing hygiene so the `.kiln/` directory doesn't accumulate stale artifacts over time. Depends on the `.kiln/` directory feature being implemented first.

## Suggested Fix

- Define manifest format (JSON or markdown) describing expected `.kiln/` subdirectories and file patterns
- Create a `/kiln-doctor` skill that reads the manifest and runs validation
- Map known legacy paths to their `.kiln/` equivalents for migration
- Interactive fix mode: show each issue, suggest fix, apply on confirmation
- Post-run hook option: run a lightweight check after agent runs to catch misplaced outputs immediately
