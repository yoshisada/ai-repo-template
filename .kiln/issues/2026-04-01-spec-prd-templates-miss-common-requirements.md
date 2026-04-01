---
title: "Spec/PRD templates miss common requirements — grep verification, CLI discovery, auth docs, local validation"
type: friction
severity: medium
category: templates
source: analyze-issues
github_issue: "#22, #23, #17, #18"
status: open
date: 2026-04-01
---

## Description

Four recurring gaps in spec/PRD templates that cause rework across multiple pipeline runs:

### 1. No catch-all grep verification for renames/rebrands (#22)
In #22, the PRD enumerated specific files for renaming but missed `.claude-plugin/marketplace.json`. A catch-all "grep and update all remaining references" FR would have caught it. The PRD template doesn't prompt for this.

### 2. No CLI discovery task for container-dependent features (#23)
In #23, the implementer used fictional `ob config get/set` CLI commands that don't exist (real commands: `ob sync-status/sync-config`). The spec left CLI command names as "implementation-time discovery" but the implementer didn't actually inspect the container. 15 tests failed, requiring a 6-file fix commit.

### 3. QA credentials/auth not documented in spec (#17)
In #17, QA couldn't access the admin panel because `ADMIN_PASSWORD` wasn't documented in spec or plan artifacts. QA had to create authentication scaffolding independently.

### 4. No local axe-core validation before committing a11y fixes (#18)
In #18, the a11y implementer didn't run axe-core locally before committing. Fixing one violation unmasked the next, causing 4+ fix-retest cascades (6 contrast-related fixup commits).

## Impact

Medium — each gap individually caused 1+ wasted cycles. Collectively, these template gaps cause predictable, avoidable rework in every pipeline run that involves renames, containers, auth, or a11y.

## Suggested Fix

Add to PRD/spec/plan templates:

1. **Rename/rebrand checklist**: "Include an FR for grep-based verification that catches ALL references, not just enumerated files"
2. **Container CLI discovery task**: "When a plan depends on CLI commands inside a container, add Phase 1 task: Run `docker exec <container> <cli> --help` and document in research.md before writing any code"
3. **QA auth documentation**: "Document credentials and auth flow required for QA testing in spec or plan artifacts"
4. **Local validation before commit**: "For a11y features, implementer MUST run axe-core locally and fix all violations in a single pass before committing"

## Source Retrospectives

- #22: PRD missed marketplace.json in rename scope
- #23: Implementer guessed CLI commands, 15 tests failed
- #17: QA blocked by undocumented auth wall
- #18: 4+ contrast fix cascades from no local axe-core
