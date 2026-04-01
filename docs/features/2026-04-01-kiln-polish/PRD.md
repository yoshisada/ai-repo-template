# Feature PRD: Kiln Polish — Next Command Suggestion & QA Directory Structure

**Date**: 2026-04-01
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)

## Background

Two friction points have surfaced from daily kiln usage. First, the `/next` skill outputs a prioritized list of recommendations but doesn't call out a single "do this now" action — the user still has to scan and decide. Second, the `.kiln/qa/` directory has no defined structure, so QA agents produce artifacts in inconsistent locations and users can't predict where outputs land.

Both issues are small, self-contained improvements that make the kiln workflow smoother without changing core behavior.

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [/next should suggest a specific command to run next](.kiln/issues/2026-04-01-next-suggest-runnable-command.md) | — | friction | medium |
| 2 | [Create manifest and folder structure for QA directory](.kiln/issues/2026-03-31-qa-directory-manifest.md) | — | improvement | medium |

## Problem Statement

**`/next` lacks a clear call-to-action.** Users run `/next` at session start to orient themselves, but the output is a grouped list with no single recommendation highlighted. This forces the user to parse priorities and pick a command manually — exactly the cognitive load `/next` was designed to eliminate.

**QA directory has no canonical layout.** The `.kiln/qa/` directory exists but has no manifest or standard folder structure. QA agents (`qa-engineer`, `qa-setup`, `qa-pass`) write artifacts to ad-hoc locations. Users don't know where to find test results, screenshots, videos, or config files. This makes QA outputs hard to discover and inconsistent across projects.

## Goals

- `/next` ends with a single, prominent "suggested next" line showing the highest-priority command
- `.kiln/qa/` has a defined directory structure with canonical locations for all QA artifact types
- QA skills (`/qa-setup`, `/qa-pass`, `/qa-checkpoint`) use the standardized paths
- The `init.mjs` scaffold creates the QA directory structure in new projects

## Non-Goals

- Changing the prioritization logic in `/next` — only the output format changes
- Adding new QA capabilities — only standardizing where existing outputs land
- Auto-executing the suggested command from `/next`

## Requirements

### Functional Requirements

**FR-001** (from: 2026-04-01-next-suggest-runnable-command.md): After the recommendations list, `/next` MUST output a visually distinct "Suggested next" line containing the single highest-priority command from the recommendations.

**FR-002** (from: 2026-04-01-next-suggest-runnable-command.md): The suggested command MUST include a brief reason (e.g., "3 incomplete tasks in specs/auth/tasks.md") so the user understands why it's the top pick.

**FR-003** (from: 2026-04-01-next-suggest-runnable-command.md): If no actionable recommendations exist (project is clean), the "Suggested next" line MUST say so (e.g., "Nothing urgent — check the backlog with `/issue-to-prd`").

**FR-004** (from: 2026-03-31-qa-directory-manifest.md): Define a QA directory manifest specifying the expected `.kiln/qa/` folder structure, including subdirectories for tests, results, screenshots, videos, and configuration.

**FR-005** (from: 2026-03-31-qa-directory-manifest.md): The `/qa-setup` skill MUST create the standardized `.kiln/qa/` directory structure when run.

**FR-006** (from: 2026-03-31-qa-directory-manifest.md): QA agent outputs (reports, screenshots, videos, test results) MUST be written to their canonical locations within `.kiln/qa/`.

**FR-007** (from: 2026-03-31-qa-directory-manifest.md): The `init.mjs` scaffold MUST create the `.kiln/qa/` directory structure (empty subdirectories) in new consumer projects.

**FR-008** (from: 2026-03-31-qa-directory-manifest.md): A `.kiln/qa/README.md` MUST document the directory layout so users can find artifacts without reading skill source code.

### Non-Functional Requirements

- Changes to `/next` output must not break `--brief` mode behavior
- QA directory structure must be backwards-compatible — existing `.kiln/qa/` files should not be deleted or moved automatically
- All changes are to markdown skill files, shell scripts, and the scaffold — no compiled code

## User Stories

- As a developer starting a session, I want `/next` to tell me exactly what command to run so I can get going immediately without scanning a list.
- As a developer reviewing QA results, I want to know exactly where screenshots, videos, and reports live so I can find them without searching.
- As a new project user, I want the QA directory pre-created with a README so I understand the structure before running any QA commands.

## Success Criteria

- Running `/next` on a project with outstanding work shows a "Suggested next: `/command` — reason" line at the bottom of the output
- Running `/next` on a clean project shows "Nothing urgent" with a fallback suggestion
- `.kiln/qa/` has a documented, consistent structure across all consumer projects initialized with kiln
- QA skills write outputs to the standardized paths

## Tech Stack

- Markdown (skill definitions)
- Bash (shell commands within skills)
- Node.js (init.mjs scaffold updates)

## Risks & Open Questions

- **Q: What's the exact `.kiln/qa/` subdirectory list?** Needs to be finalized during `/specify` — candidates: `tests/`, `results/`, `screenshots/`, `videos/`, `config/`, `latest/`
- **Q: Should `/kiln-doctor` validate QA directory structure?** Probably yes, but that's a separate backlog item (already tracked as kiln-doctor-manifest)
- **Risk**: Changing QA output paths could break existing pipeline runs mid-flight if a consumer project upgrades mid-build. Mitigation: QA skills should create directories on-demand if missing.
