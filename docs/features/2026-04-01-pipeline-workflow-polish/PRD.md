# Feature PRD: Pipeline Workflow Polish

**Date**: 2026-04-01
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)

## Background

After several `/build-prd` pipeline runs, a pattern of workflow friction has emerged: the pipeline lacks validation for non-compiled features (which are the majority of changes in this plugin repo), branch and spec directory naming is inconsistent causing agent confusion, commit noise from hooks and task-marking inflates git history on small features, the issue lifecycle stalls at `prd-created` with no automatic completion, and there's no lightweight way to capture future work ideas outside the issue system.

These 6 items collectively reduce pipeline efficiency, pollute git history, and leave backlog management gaps.

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [No validation gate for non-compiled features](.kiln/issues/2026-04-01-no-validation-gate-non-compiled.md) | #30, #28, #25 | friction | medium |
| 2 | [Branch and spec directory naming is inconsistent](.kiln/issues/2026-04-01-branch-directory-naming-inconsistency.md) | #28, #16, #9 | friction | medium |
| 3 | [Auto-mark prd-created issues as completed after build-prd](.kiln/issues/2026-04-01-auto-complete-prd-created-issues.md) | — | improvement | medium |
| 4 | [Add /kiln-cleanup command to purge QA artifacts + archive issues](.kiln/issues/2026-04-01-kiln-cleanup-qa-command.md) | — | feature-request | medium |
| 5 | [Excessive commit noise from version hooks and task-marking](.kiln/issues/2026-04-01-commit-noise-hooks-task-marking.md) | #25, #20, #19 | friction | low |
| 6 | [Add a lightweight roadmap/todo for tracking future work ideas](.kiln/issues/2026-04-01-roadmap-todo-list.md) | — | feature-request | low |

## Problem Statement

The kiln pipeline enforces quality gates for compiled code (80% test coverage) but has zero validation for markdown skills, agent definitions, hooks, and scaffold code — which is the majority of what this plugin repo produces. An entire class of deliverables ships with no automated check for broken bash snippets, invalid frontmatter, or broken file references.

Branch and spec directory naming is inconsistent across pipeline runs. Agents waste time globbing the filesystem to find spec files, branches carry commits from prior features polluting PR diffs, and retrospective agents reference wrong branches. This was observed in at least 5 pipeline runs.

The issue lifecycle stalls after `/issue-to-prd` — issues transition to `prd-created` but never to `completed`, accumulating noise. Meanwhile, QA artifacts and completed issues pile up in `.kiln/` with no cleanup mechanism beyond what was added in the qa-tooling-templates feature (which addressed the doctor/cleanup skill but not the issue archival automation at pipeline end). Finally, there's no lightweight way to capture "someday" ideas without creating a full issue.

## Goals

- Add a validation gate for non-compiled features (markdown, bash, scaffold) that substitutes for the 80% coverage gate
- Enforce consistent branch and spec directory naming across all pipeline runs
- Reduce commit noise by folding hook changes and task-marking into phase commits for small features
- Auto-complete `prd-created` issues when their pipeline finishes successfully
- Extend `/kiln-cleanup` to archive completed issues from `.kiln/issues/`
- Add a lightweight roadmap/todo mechanism for capturing future work ideas

## Non-Goals

- Adding a full test suite for markdown skills — validation is structural, not behavioral
- Changing the version numbering scheme — only how version bumps are committed
- Building a project management system — the roadmap is intentionally a simple markdown list
- Modifying the 80% coverage gate for compiled code — that stays as-is

## Requirements

### Functional Requirements

**Non-Compiled Validation Gate (medium priority)**

- **FR-001** (from: no-validation-gate-non-compiled.md): Add a validation step for non-compiled features that checks: (a) all modified markdown files have valid frontmatter structure, (b) all bash snippets in skill SKILL.md files are syntactically valid, (c) all file path references in modified files resolve to existing files, (d) `init.mjs` runs successfully in a temp directory to verify scaffold output
- **FR-002** (from: no-validation-gate-non-compiled.md): Integrate the non-compiled validation gate into `/implement` as an alternative to the 80% coverage gate — when no `src/` changes exist, run the markdown/scaffold validation instead
- **FR-003** (from: no-validation-gate-non-compiled.md): Add validation results to the auditor's checklist so the PR includes evidence of what was verified

**Branch & Directory Naming (medium priority)**

- **FR-004** (from: branch-directory-naming-inconsistency.md): Enforce branch naming convention `build/<feature-slug>-<YYYYMMDD>` in the `/build-prd` skill — the team lead MUST create the branch following this exact pattern
- **FR-005** (from: branch-directory-naming-inconsistency.md): Enforce spec directory naming to match the feature slug — `specs/<feature-slug>/` with no numeric prefixes, matching the branch name's feature portion
- **FR-006** (from: branch-directory-naming-inconsistency.md): Each `/build-prd` run MUST create a fresh branch from the current HEAD (not reuse an existing feature branch), and the team lead MUST broadcast the canonical branch name and spec directory path to all teammates at spawn time

**Issue Lifecycle Completion (medium priority)**

- **FR-007** (from: auto-complete-prd-created-issues.md): At the end of the `/build-prd` pipeline (after PR creation, before retrospective), scan `.kiln/issues/` for entries with `status: prd-created` whose `prd:` field matches the PRD that was just built, and update their status to `completed` with a `completed_date` and `pr` field linking to the created PR
- **FR-008** (from: auto-complete-prd-created-issues.md): If the issue archival feature from qa-tooling-templates is present (FR-024/025), move completed issues to `.kiln/issues/completed/` as part of the same step

**Issue & Artifact Cleanup (medium priority)**

- **FR-009** (from: kiln-cleanup-qa-command.md): Extend the `/kiln-cleanup` skill to also scan `.kiln/issues/` for issues with `status: prd-created` or `status: completed` and move them to `.kiln/issues/completed/` (archival), with `--dry-run` support
- **FR-010** (from: kiln-cleanup-qa-command.md): Update `/kiln-doctor` to report stale `prd-created` issues as a diagnostic finding (issues that were bundled into a PRD but never built)

**Commit Noise Reduction (low priority)**

- **FR-011** (from: commit-noise-hooks-task-marking.md): Update the version-increment hook to stage its changes for inclusion in the next commit rather than requiring a separate chore commit — the hook should modify files in-place and let the implementing agent include them in the phase commit
- **FR-012** (from: commit-noise-hooks-task-marking.md): Update `/implement` instructions to combine task-marking updates (`[X]` in tasks.md) into the phase commit for features with a single implementation phase, rather than creating separate task-marking commits
- **FR-013** (from: commit-noise-hooks-task-marking.md): Add guidance to `/build-prd` that QA result snapshots and incremental test-result files should NOT be committed to the feature branch — they belong in `.kiln/qa/` which is gitignored

**Roadmap Tracking (low priority)**

- **FR-014** (from: roadmap-todo-list.md): Add a `.kiln/roadmap.md` file to the scaffold — a simple markdown list grouped by theme (e.g., "DX improvements", "New capabilities", "Tech debt") with no frontmatter or status tracking
- **FR-015** (from: roadmap-todo-list.md): Create a `/roadmap` skill that appends items to `.kiln/roadmap.md` with a one-liner (e.g., `/roadmap Add support for monorepo projects`)
- **FR-016** (from: roadmap-todo-list.md): Update `/next` to optionally surface roadmap items when there's no urgent work — "Nothing pressing. Here are some ideas from your roadmap..."

### Non-Functional Requirements

- **NFR-001**: Non-compiled validation must complete in under 30 seconds for a typical plugin change (10-20 modified files)
- **NFR-002**: Branch naming enforcement must not break existing workflows for consumer projects that don't use `/build-prd`
- **NFR-003**: Commit noise reduction must not compromise the audit trail — every phase must still produce at least one commit
- **NFR-004**: Roadmap file must remain human-editable — no complex structure or tooling required to maintain it

## User Stories

- As a **plugin maintainer**, I want non-compiled changes validated before the pipeline considers them "done" so I catch broken references and invalid frontmatter before they ship
- As a **pipeline operator**, I want consistent branch and directory naming so agents don't waste time searching for spec files
- As a **pipeline operator**, I want `prd-created` issues to auto-complete when their pipeline finishes so the backlog stays clean without manual intervention
- As a **pipeline operator**, I want `/kiln-cleanup` to archive stale issues so the active backlog only contains actionable items
- As a **feature developer**, I want version bumps and task-marking folded into phase commits so small features don't produce 66 commits
- As a **user**, I want a lightweight roadmap to capture future ideas without creating full issues so nothing gets forgotten between sessions

## Success Criteria

- Non-compiled features run a validation gate that checks frontmatter, bash syntax, file references, and scaffold output — no more "N/A" coverage gate
- All `/build-prd` branches follow `build/<slug>-<YYYYMMDD>` and spec directories match `specs/<slug>/`
- `prd-created` issues are automatically marked `completed` and archived after successful pipeline runs
- `/kiln-cleanup` archives stale issues in addition to purging QA artifacts
- Commit count for single-phase features is reduced by at least 40% compared to current baseline
- `.kiln/roadmap.md` exists and `/next` surfaces roadmap items when no urgent work is available

## Tech Stack

- Markdown (skill/agent definitions)
- Bash (hook scripts, validation scripts, shell commands within skills)
- Node.js (init.mjs scaffold updates)
- JSON (hooks.json modifications)

## Risks & Open Questions

1. **Bash syntax validation depth**: FR-001 checks bash snippets in SKILL.md files for syntax validity. How deep should this go — just `bash -n` on extracted code blocks, or also check that referenced commands exist?
2. **Version hook staging behavior**: FR-011 changes the version-increment hook to stage changes rather than requiring separate commits. This may conflict with the hook's current design of running on every Edit/Write — need to verify the hook can reliably stage without creating race conditions when multiple agents edit files in parallel.
3. **Roadmap scope creep**: The roadmap feature (FR-014–016) is intentionally lightweight. Resist adding status tracking, priorities, or dates — that's what `.kiln/issues/` is for.
4. **Backwards compatibility of branch naming**: FR-004 enforces naming only in `/build-prd`. Consumer projects that create branches manually are unaffected, but should we add a hook for `require-feature-branch.sh` to also validate the pattern?
