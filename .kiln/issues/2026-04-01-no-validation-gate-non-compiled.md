---
title: "No validation gate for non-compiled features (markdown skills, agents, scaffold)"
type: friction
severity: medium
category: workflow
source: analyze-issues
github_issue: "#30, #28, #25"
status: prd-created
prd: docs/features/2026-04-01-pipeline-workflow-polish/PRD.md
date: 2026-04-01
---

## Description

The 80% test coverage gate only applies to compiled code with test suites. Features that only modify markdown skills, agent definitions, or scaffold code bypass this gate entirely. There is no alternative validation mechanism — a skill could have broken bash snippets, invalid frontmatter, or broken file references with no automated check.

This was noted in at least 3 separate pipeline runs (#30, #28, #25) where the coverage gate was marked "N/A" with no substitute quality check.

## Impact

Medium — an entire class of deliverables (kiln's own skills, agents, templates) has no automated quality gate. The pipeline's quality enforcement is effectively bypassed for the majority of changes in this repo.

## Suggested Fix

For features that only modify markdown skills, agents, or scaffold code (no src/ changes), require:
1. Running `init.mjs` in a temp directory to verify scaffold output
2. Linting modified markdown files for valid frontmatter and structure
3. Grepping all modified files for path consistency and broken references
4. Optionally: a dry-run smoke test that exercises the skill on a test repo

Document validation steps in the commit message so the retro agent can review what was verified.

## Source Retrospectives

- #30: Proposes skill-only validation gate
- #28: Proposes non-compiled change validation protocol
- #25: Notes no runtime validation possible for markdown-only features
