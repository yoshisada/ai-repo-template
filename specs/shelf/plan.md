# Implementation Plan: Shelf

**Branch**: `build/shelf-20260403` | **Date**: 2026-04-03 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/shelf/spec.md`

## Summary

Build a Claude Code plugin (`@yoshisada/shelf`) with 6 Markdown SKILL.md files that sync project state to an Obsidian vault via MCP tools. Each skill is a standalone Markdown file following the kiln plugin pattern — no compiled code, no agents, no hooks. All vault writes go through `mcp__obsidian-projects__*` tools; GitHub data comes from `gh` CLI; repo metadata from `git`.

## Technical Context

**Language/Version**: Markdown (skill definitions), Bash (shell commands within skills)
**Primary Dependencies**: Obsidian MCP tools (`mcp__obsidian-projects__*`), `gh` CLI, `git` CLI
**Storage**: Obsidian vault via MCP (no direct filesystem access to vault)
**Testing**: Manual — run each skill command against a real Obsidian vault with MCP configured
**Target Platform**: Any platform supported by Claude Code
**Project Type**: Claude Code plugin (Markdown SKILL.md files)
**Performance Goals**: N/A — commands are user-invoked, not latency-sensitive
**Constraints**: MCP-only vault access; graceful degradation when MCP unavailable; no changes to kiln or wheel plugins
**Scale/Scope**: 6 SKILL.md files, 1 plugin.json manifest, 1 package.json

## Constitution Check

| Gate | Status | Notes |
|------|--------|-------|
| Spec-First Development | PASS | spec.md exists with FR-001 through FR-039 + NFR-001 through NFR-005 |
| 80% Test Coverage | N/A | No compiled code — plugin is Markdown skill files |
| PRD as Source of Truth | PASS | PRD at docs/features/2026-04-03-shelf/PRD.md and plugin-shelf/docs/PRD.md |
| Hooks Enforce Rules | PASS | No hooks in shelf plugin (deferred) |
| E2E Testing Required | N/A | No compiled CLI/API — skills are Markdown instructions executed by Claude Code |
| Small, Focused Changes | PASS | Each skill is a self-contained SKILL.md file |
| Interface Contracts Before Implementation | PASS | Contracts defined below (skill input/output contracts, not function signatures) |
| Incremental Task Completion | PASS | Will be enforced during /implement |

## Project Structure

### Documentation (this feature)

```text
specs/shelf/
├── spec.md
├── plan.md              # This file
├── contracts/
│   └── interfaces.md
└── tasks.md             # Created by /tasks
```

### Source Code (plugin directory)

```text
plugin-shelf/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest (already exists)
├── docs/
│   └── PRD.md               # Detailed PRD (already exists)
├── package.json             # npm package: @yoshisada/shelf
└── skills/
    ├── shelf-create/
    │   └── SKILL.md         # FR-001 through FR-006, FR-029, FR-030
    ├── shelf-update/
    │   └── SKILL.md         # FR-007 through FR-012, FR-031 through FR-033
    ├── shelf-sync/
    │   └── SKILL.md         # FR-013 through FR-018
    ├── shelf-feedback/
    │   └── SKILL.md         # FR-019 through FR-023
    ├── shelf-status/
    │   └── SKILL.md         # FR-024 through FR-028
    └── shelf-release/
        └── SKILL.md         # FR-034 through FR-039
```

## Design Decisions

### Why Markdown SKILL.md files (not code)

Claude Code plugins define skills as Markdown instruction files. The Claude Code runtime reads the SKILL.md, interprets the instructions, and executes tool calls (MCP, Bash, etc.) as directed. There is no compilation, transpilation, or runtime code. This matches the kiln plugin pattern exactly.

### Why no agents or hooks

The PRD explicitly defers hook integration with kiln and states "Six skills, no agents, no hooks." Each skill is user-invoked and self-contained.

### MCP tool usage pattern

Every skill that writes to Obsidian follows this pattern:
1. Resolve project slug from git repo name
2. Construct the vault path: `{base_path}/{slug}/...`
3. Read existing content via `mcp__obsidian-projects__read_file` (to avoid clobbering)
4. Write via `mcp__obsidian-projects__create_file` or `mcp__obsidian-projects__update_file`
5. If any MCP call fails, warn the user and exit gracefully

### Configurable base path

The base path defaults to `@second-brain/projects` but each SKILL.md instructs Claude to check for a `.shelf-config` or accept the path as a flag. This satisfies NFR-003.

### Slug derivation

Project slug is derived from `git remote get-url origin` (extracting the repo name) or accepted as an argument. This is documented in each SKILL.md's instructions.

## Complexity Tracking

No constitution violations. All skills are simple Markdown files with no cross-dependencies.
