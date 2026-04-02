# Interface Contracts: Pipeline Workflow Polish

**Date**: 2026-04-01
**Spec**: [spec.md](../spec.md) | **Plan**: [plan.md](../plan.md)

This document defines the contracts for all new and modified artifacts. Since this is a plugin repo (markdown skills + bash hooks + Node.js scaffold), "interfaces" are skill entry points, script CLIs, and hook behaviors rather than function signatures.

---

## New Files

### 1. `scripts/validate-non-compiled.sh` (FR-001)

**Type**: Bash script
**Invocation**: `bash scripts/validate-non-compiled.sh [--files <file1> <file2> ...] [--all]`
**Exit code**: `0` on all checks pass, `1` on any failure
**Stdout format**:
```
## Non-Compiled Validation Report

| Check | Files Tested | Pass | Fail | Details |
|-------|-------------|------|------|---------|
| Frontmatter | N | N | N | [list of failures] |
| Bash syntax | N | N | N | [list of failures] |
| File references | N | N | N | [list of failures] |
| Scaffold output | 1 | 0/1 | 0/1 | [pass/fail] |

Result: PASS / FAIL
```

**Behavior**:
- `--files`: Validate only the specified files
- `--all`: Validate all markdown/bash files in `plugin/`
- Default (no args): Detect modified files via `git diff --name-only HEAD~1` and validate those
- Frontmatter check: Verify `---` delimiters and valid YAML structure in skill SKILL.md files
- Bash syntax check: Extract bash/sh code blocks from SKILL.md files, write to temp file, run `bash -n`
- File reference check: Find file path patterns in modified files, verify each path exists relative to repo root
- Scaffold check: Run `node plugin/bin/init.mjs init` in a temp directory, verify exit code 0

### 2. `plugin/skills/roadmap/SKILL.md` (FR-015)

**Type**: Markdown skill definition
**Trigger**: `/roadmap <item description>`
**Behavior**:
- If `.kiln/roadmap.md` does not exist, create it from `plugin/templates/roadmap-template.md`
- Parse the item description
- Identify the best matching theme group in the roadmap (or append to a "General" group)
- Append the item as a bullet under the theme group
- Report what was added and where

**Frontmatter**:
```yaml
---
name: roadmap
description: Append items to .kiln/roadmap.md with a one-liner description. Use as "/roadmap Add support for monorepo projects".
---
```

### 3. `plugin/templates/roadmap-template.md` (FR-014)

**Type**: Markdown template
**Content structure**:
```markdown
# Roadmap

Ideas and future work items. Grouped by theme, no priority or status tracking.
Edit freely — this is a scratchpad, not a project plan.

## DX Improvements

## New Capabilities

## Tech Debt

## General
```

---

## Modified Files

### 4. `plugin/skills/implement/SKILL.md` (FR-002, FR-012)

**FR-002 — Non-compiled validation gate**:
- **Location**: After step 9 (completion validation), before extension hooks
- **Contract**: When no `src/` directory changes exist in the feature branch, skip the 80% coverage gate and instead run `bash scripts/validate-non-compiled.sh`. Report the validation results as the coverage substitute. If the script exits non-zero, halt and report failures.

**FR-012 — Task-marking in phase commits**:
- **Location**: Step 8 (progress tracking), in the guidance for committing
- **Contract**: Add instruction that for features with a single implementation phase, task-marking updates to tasks.md SHOULD be included in the phase commit rather than committed separately. Multi-phase features continue to commit per-phase as before.

### 5. `plugin/skills/audit/SKILL.md` (FR-003)

**Location**: In the audit checklist section
**Contract**: Add a checklist item: "Non-compiled validation: [PASS/FAIL/N/A] — Frontmatter: N files, Bash syntax: N files, File refs: N files, Scaffold: [pass/fail]". Populated from the validation report generated during `/implement`. If no validation was run (compiled project), mark as N/A.

### 6. `plugin/skills/build-prd/SKILL.md` (FR-004, FR-005, FR-006, FR-007, FR-008, FR-013)

**FR-004 — Branch naming**:
- **Location**: Step 5 (branch creation)
- **Contract**: Replace the current branch creation logic with: `BRANCH_NAME="build/$(echo "$FEATURE_SLUG" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')-$(date +%Y%m%d)"`. The feature slug MUST be derived from the PRD directory name or feature description (2-4 words, lowercased, hyphenated).

**FR-005 — Spec directory naming**:
- **Location**: In the specifier agent prompt
- **Contract**: The spec directory MUST be `specs/<feature-slug>/` where `<feature-slug>` matches the branch name's feature portion (the part between `build/` and `-YYYYMMDD`).

**FR-006 — Fresh branch + broadcast**:
- **Location**: Step 5 (branch creation) and Step 2 (agent spawn messages)
- **Contract**: Always create branch from current HEAD via `git checkout -b`. When spawning each agent, include in the prompt: "Working directory: <path>, Branch: <branch-name>, Spec directory: specs/<feature-slug>/".

**FR-007 — Issue lifecycle completion**:
- **Location**: After audit-pr creates the PR, before retrospective
- **Contract**: Add a new step that:
  1. Reads the PRD path that was used for this build
  2. Scans `.kiln/issues/*.md` for entries with `status: prd-created`
  3. For each matching issue, checks if its `prd:` frontmatter field matches the PRD path
  4. Updates matching issues: set `status: completed`, add `completed_date: YYYY-MM-DD`, add `pr: #<PR-number>`
  5. Reports how many issues were updated

**FR-008 — Issue archival**:
- **Location**: Same step as FR-007, immediately after status update
- **Contract**: If `.kiln/issues/completed/` exists (or can be created), move the updated issues there via `mv`.

**FR-013 — QA snapshot guidance**:
- **Location**: In the QA engineer role description (Step 1)
- **Contract**: Add instruction: "QA result snapshots and incremental test-result files MUST NOT be committed to the feature branch. They belong in `.kiln/qa/` which is gitignored."

### 7. `plugin/skills/kiln-cleanup/SKILL.md` (FR-009)

**Location**: Add a new Step 2.5 between the current Step 2 (scan QA artifacts) and Step 3 (purge)
**Contract**:
- Scan `.kiln/issues/*.md` for entries with `status: prd-created` or `status: completed`
- In dry-run mode: report what would be archived
- In delete mode: create `.kiln/issues/completed/` if needed, move matching issues there
- Display results in the same table format as QA artifact scan

### 8. `plugin/skills/kiln-doctor/SKILL.md` (FR-010)

**Location**: Add a new Step 3f after Step 3e (report)
**Contract**:
- Grep `.kiln/issues/*.md` for `status: prd-created`
- Report each as a diagnostic finding: "STALE: <filename> — status is prd-created (bundled into PRD but never built)"
- Include in the diagnosis table as a new row type

### 9. `plugin/hooks/version-increment.sh` (FR-011)

**Location**: At the end of the script, after writing VERSION and syncing to package.json/plugin.json
**Contract**: Add `git add` calls to stage the modified files:
```bash
git add "$VERSION_FILE" 2>/dev/null || true
[ -f "$PKG_FILE" ] && git add "$PKG_FILE" 2>/dev/null || true
[ -f "$PLUGIN_JSON" ] && git add "$PLUGIN_JSON" 2>/dev/null || true
```
This stages the version changes for inclusion in the next commit the agent creates. No separate commit is created by the hook.

### 10. `plugin/skills/next/SKILL.md` (FR-016)

**Location**: In the output generation section (after all state gathering, in the prioritization logic)
**Contract**: Add a conditional section:
- If no urgent work exists (no incomplete tasks, no open blockers, no critical issues):
  - Read `.kiln/roadmap.md` if it exists
  - Extract up to 5 bullet items
  - Display: "Nothing pressing. Here are some ideas from your roadmap:" followed by the items
- If urgent work exists: do not show roadmap items

### 11. `plugin/bin/init.mjs` (FR-014)

**Location**: In the scaffold function, after creating `.kiln/` directories
**Contract**: Copy `plugin/templates/roadmap-template.md` to `.kiln/roadmap.md` in the target project. Use the existing `copyIfMissing` pattern so it doesn't overwrite existing roadmap files.
