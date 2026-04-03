# Feature PRD: Shelf Config Artifact

**Date**: 2026-04-03
**Status**: Draft
**Parent PRD**: docs/features/2026-04-03-shelf/PRD.md

## Background

The shelf plugin provides 6 skills (`shelf-create`, `shelf-sync`, `shelf-update`, `shelf-status`, `shelf-feedback`, `shelf-release`) that all need to resolve the Obsidian vault base path and project slug before doing anything. Currently, each skill independently:

1. Checks if `.shelf-config` exists (it never does — nothing creates it)
2. Falls back to `base_path: projects` and derives the slug from `git remote get-url origin`

This causes two problems:
- When the repo name differs from the desired Obsidian project slug (e.g., `ai-repo-template` repo tracking as `plugin-shelf` in Obsidian), every skill either guesses wrong or requires the user to pass the slug as an argument every time.
- The actual Obsidian base path (`@second-brain/projects`) is not `projects` — the default is wrong, and there's no way to persist the correct one.

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [Add .shelf-config artifact to track Obsidian vault path](.kiln/issues/2026-04-03-shelf-config-artifact.md) | — | feature-request | high |

## Problem Statement

Every shelf skill duplicates the same path-resolution logic and falls back to an incorrect default when `.shelf-config` doesn't exist. Since `/shelf-create` never writes this file, users must manually pass the project slug as an argument to every command — or accept the wrong project path. This is friction that compounds across every session.

## Goals

- `/shelf-create` writes a `.shelf-config` file to the repo root after successfully creating a project in Obsidian
- All 6 shelf skills read `.shelf-config` and use its values instead of guessing
- Users never need to pass the project slug as an argument after initial setup
- The config file is human-readable and editable

## Non-Goals

- Multi-project tracking (one repo = one Obsidian project)
- Vault authentication or credential storage
- Migrating existing projects — users can create `.shelf-config` manually or re-run `/shelf-create`

## Requirements

### Functional Requirements

**FR-001**: `/shelf-create` MUST write a `.shelf-config` file to the repo root after successfully creating the Obsidian project dashboard. (from: 2026-04-03-shelf-config-artifact.md)

**FR-002**: The `.shelf-config` file MUST contain at minimum: `base_path` (the Obsidian vault path prefix) and `slug` (the project slug used in vault paths). (from: 2026-04-03-shelf-config-artifact.md)

**FR-003**: The `.shelf-config` file MUST also contain `dashboard_path` — the full resolved path to the project dashboard file (e.g., `@second-brain/projects/plugin-shelf/plugin-shelf.md`). (from: 2026-04-03-shelf-config-artifact.md)

**FR-004**: The `.shelf-config` file format MUST be a simple key-value format (one key per line, `key = value`), human-readable and editable. (from: 2026-04-03-shelf-config-artifact.md)

**FR-005**: All 6 shelf skills (`shelf-create`, `shelf-sync`, `shelf-update`, `shelf-status`, `shelf-feedback`, `shelf-release`) MUST read `.shelf-config` as the first step in path resolution, before falling back to defaults. (from: 2026-04-03-shelf-config-artifact.md)

**FR-006**: When `.shelf-config` exists and contains valid `base_path` and `slug`, skills MUST NOT prompt the user for a project name or derive one from the git remote. (from: 2026-04-03-shelf-config-artifact.md)

**FR-007**: `/shelf-create` MUST ask the user to confirm the slug and base path before writing `.shelf-config`, especially when the slug differs from the repo name. (from: 2026-04-03-shelf-config-artifact.md)

**FR-008**: The `.shelf-config` file SHOULD be committed to the repo (not gitignored) so that all collaborators share the same Obsidian project mapping. (from: 2026-04-03-shelf-config-artifact.md)

### Non-Functional Requirements

**NFR-001**: The `.shelf-config` file must be parseable with basic shell tools (`grep`, `sed`, `awk`) — no JSON or YAML dependency.

**NFR-002**: If `.shelf-config` is malformed or missing required keys, skills must fall back to the existing default behavior (derive from git remote) and warn the user.

**NFR-003**: Writing `.shelf-config` must not break the existing shelf-create flow — it's an addition after the Obsidian project is confirmed created.

## User Stories

**US-001**: As a developer, I want `/shelf-create` to remember where my Obsidian project lives so I don't have to pass the slug every time I run a shelf command.

**US-002**: As a collaborator cloning a repo, I want `.shelf-config` checked in so shelf commands work for me without setup.

**US-003**: As a developer, I want to manually edit `.shelf-config` if I rename my Obsidian project or move it to a different vault path.

## Success Criteria

- After running `/shelf-create plugin-shelf`, a `.shelf-config` file exists in the repo root with correct `base_path`, `slug`, and `dashboard_path`
- Running `/shelf-sync` (with no arguments) resolves to the correct Obsidian project via `.shelf-config`
- All 6 shelf skills work without arguments when `.shelf-config` is present
- `.shelf-config` is a plain text file readable by `cat` and parseable by `grep`

## Tech Stack

- Markdown (skill definitions) — modifications to 6 existing SKILL.md files + shelf-create
- Shell (key-value parsing in skill instructions)
- No new dependencies

## Risks & Open Questions

1. **Existing repos**: Repos that already ran `/shelf-create` before this feature won't have `.shelf-config`. The fallback behavior handles this, but users may want a `/shelf-init` or similar to retroactively create the config.
2. **Config format**: Key-value (`key = value`) is simplest but doesn't support nested config. This is fine for now — we only need 3 keys.

## Example `.shelf-config`

```ini
# Shelf configuration — maps this repo to its Obsidian project
base_path = @second-brain/projects
slug = plugin-shelf
dashboard_path = @second-brain/projects/plugin-shelf/plugin-shelf.md
```
