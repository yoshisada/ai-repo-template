# Feature PRD: Plugin Polish & Skill UX

**Date**: 2026-04-09
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)

## Background

As kiln matures, several rough edges have surfaced around plugin packaging, project scaffolding, and skill behavior. Consumer projects encounter broken workflows because assets aren't shipped with the npm package, the init script creates opinionated directories that don't match all project layouts, and error recovery when dependencies are missing is poor. On the skill side, `/next` overwhelms users with internal pipeline commands, `/report-issue` doesn't capture source-code context, and trim-push produces incomplete Penpot representations that undermine the entire design-sync pipeline.

These issues share a common thread: the plugin works well for the maintainer's repo but falls short for consumer projects and new users who expect a polished out-of-box experience.

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [report-issue-and-sync workflow must ship with kiln plugin](.kiln/issues/2026-04-08-workflow-in-plugin-package.md) | — | bug | high |
| 2 | [trim-push should build full page compositions](.kiln/issues/2026-04-09-trim-push-should-build-full-pages.md) | — | friction | high |
| 3 | [Init script should not create src/ and tests/ directories](.kiln/issues/2026-04-08-init-no-src-tests-dirs.md) | — | improvement | medium |
| 4 | [Wheel activation should detect missing setup and offer auto-install](.kiln/issues/2026-04-08-wheel-init-failure-auto-setup.md) | — | improvement | medium |
| 5 | [/next should only recommend high-level commands](.kiln/issues/2026-04-08-next-high-level-commands-only.md) | — | improvement | medium |
| 6 | [Backlog issues should backlink to GitHub repos or file locations](.kiln/issues/2026-04-08-issue-backlinks-to-repos-files.md) | — | improvement | medium |

## Problem Statement

Consumer projects that install `@yoshisada/kiln` hit failures when `/report-issue` delegates to a workflow that doesn't exist in their project. The init script scaffolds `src/` and `tests/` directories that conflict with non-standard project layouts. When wheel isn't set up, users get opaque errors instead of helpful recovery. Meanwhile, `/next` suggests low-level pipeline steps that confuse users, backlog issues lack code-context backlinks, and trim-push only creates isolated components instead of full page compositions — rendering the design-sync pipeline incomplete.

## Goals

- All kiln-bundled workflows ship with the npm package and are discoverable by wheel in consumer projects
- Init script only creates kiln-specific directories, leaving project structure to the user
- Wheel failures produce actionable guidance and offer auto-setup
- `/next` only surfaces high-level user-facing commands
- Backlog issues automatically capture repo URL and relevant file paths
- trim-push produces both component-level and page-level Penpot frames

## Non-Goals

- Redesigning the wheel plugin architecture or hook system
- Adding new workflow types beyond fixing existing ones
- Changing the kiln 4-gate enforcement model
- Migrating existing consumer projects (only new init/update runs are affected)

## Requirements

### Functional Requirements

**FR-001** (from: workflow-in-plugin-package.md) — Include `report-issue-and-sync.json` in the kiln plugin's `workflows/` directory and declare it in `plugin.json` so wheel discovers it as a plugin-provided workflow in consumer projects.

**FR-002** (from: workflow-in-plugin-package.md) — `init.mjs update` must sync plugin workflows into the consumer project's `workflows/` directory if they don't already exist.

**FR-003** (from: trim-push-should-build-full-pages.md) — Update trim-push workflow to classify scanned files as "component" vs "page" based on directory conventions (components/ vs pages/app/ routes), router references, and layout imports.

**FR-004** (from: trim-push-should-build-full-pages.md) — Components are pushed to a Penpot Components page as a bento grid. Pages are pushed to their own individual Penpot pages as full-screen composed frames that reference the component library.

**FR-005** (from: trim-push-should-build-full-pages.md) — Update trim-push agent instructions to explicitly distinguish component-level vs page-level push behavior.

**FR-006** (from: init-no-src-tests-dirs.md) — Remove `src/` and `tests/` directory creation from `init.mjs`. Only create kiln-specific directories (`.kiln/`, `specs/`, `.specify/`, etc.).

**FR-007** (from: wheel-init-failure-auto-setup.md) — Add a pre-flight check to wheel-run (or activate.sh) that verifies wheel hooks are registered and `.wheel/` directory exists before attempting workflow execution.

**FR-008** (from: wheel-init-failure-auto-setup.md) — When pre-flight fails, print a clear message ("Wheel is not set up for this repo. Run `/wheel-init` to configure it.") and optionally offer to run setup automatically.

**FR-009** (from: next-high-level-commands-only.md) — Update the continuance agent to filter command recommendations to a whitelist of high-level user-facing commands: `/build-prd`, `/fix`, `/qa-pass`, `/create-prd`, `/create-repo`, `/init`, `/analyze-issues`, `/report-issue`, `/ux-evaluate`, `/issue-to-prd`, `/next`, `/todo`, `/roadmap`.

**FR-010** (from: next-high-level-commands-only.md) — Internal pipeline commands (`/specify`, `/plan`, `/tasks`, `/implement`, `/audit`, `/debug-diagnose`, `/debug-fix`) must not appear in `/next` output.

**FR-011** (from: issue-backlinks-to-repos-files.md) — Add optional `repo` and `files` fields to the backlog issue frontmatter template.

**FR-012** (from: issue-backlinks-to-repos-files.md) — When creating a backlog issue, auto-detect the current repo URL via `gh repo view --json url` and populate the `repo` field. Extract referenced file paths from the description into the `files` field.

### Non-Functional Requirements

**NFR-001** — Backwards compatibility: existing consumer projects must not break when updating to this version. New frontmatter fields are optional. Workflow sync is additive only.

**NFR-002** — No new runtime dependencies introduced. All changes use existing tooling (bash, jq, gh CLI, Penpot MCP).

**NFR-003** — Workflow files included in the npm package must be under 50KB total to keep the package lightweight.

## User Stories

- **As a consumer project user**, I want `/report-issue` to work out of the box after installing `@yoshisada/kiln`, so I don't have to manually copy workflow files.
- **As a developer with a non-standard project layout**, I want `kiln init` to not create `src/` and `tests/` directories, so my project structure stays clean.
- **As a new user**, I want clear guidance when wheel isn't configured, so I can fix the setup instead of getting stuck on opaque errors.
- **As a kiln user**, I want `/next` to show me meaningful high-level actions, not internal pipeline steps I shouldn't run directly.
- **As a team triaging issues**, I want backlog entries to link back to the relevant repo and files, so I can navigate to the code without searching.
- **As a designer using trim**, I want trim-push to create full page compositions in Penpot, so I can review complete screens — not just isolated component blocks.

## Success Criteria

- `/report-issue` succeeds in a freshly-initialized consumer project without manual workflow copying
- `kiln init` on an empty repo creates `.kiln/`, `specs/`, `.specify/` but NOT `src/` or `tests/`
- Running `/wheel-run` without wheel configured produces an actionable error message mentioning `/wheel-init`
- `/next` output contains zero internal pipeline commands (`/specify`, `/plan`, `/tasks`, `/implement`, `/audit`)
- New backlog issues created via `/report-issue` include a `repo:` field in frontmatter
- trim-push on a project with pages/ and components/ directories creates both component frames and page frames in Penpot

## Tech Stack

Inherited from parent PRD:
- Markdown (skill/agent definitions), Bash 5.x (hooks/scripts), Node.js 18+ (init.mjs), JSON (workflow/config files)
- Wheel workflow engine, Penpot MCP tools, `jq`, `gh` CLI

## Risks & Open Questions

- **Workflow discovery**: Need to verify that wheel can discover workflows bundled inside `node_modules/@yoshisada/kiln/workflows/` — may need a manifest entry or path convention
- **Page classification heuristic**: The component vs page classification relies on directory conventions that vary by framework (Next.js `app/`, React Router `pages/`, etc.) — may need framework-specific detection
- **Auto-setup scope**: How much should the wheel auto-setup do? Full hook registration, or just create the `.wheel/` directory?
