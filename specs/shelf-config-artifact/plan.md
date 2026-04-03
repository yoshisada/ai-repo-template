# Implementation Plan: Shelf Config Artifact

**Branch**: `build/shelf-config-artifact-20260403` | **Date**: 2026-04-03 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/shelf-config-artifact/spec.md`

## Summary

Add a `.shelf-config` artifact file that `/shelf-create` writes after successfully creating an Obsidian project. All 6 shelf skills read this file to resolve the project slug and base path, eliminating the need for users to pass the project name as an argument every time. The implementation modifies 6 SKILL.md files in the shelf plugin — no compiled code, no tests, no build step.

## Technical Context

**Language/Version**: Markdown (skill definitions) + Bash (inline shell commands in skills)
**Primary Dependencies**: None — shelf plugin skills are Markdown files with embedded shell/MCP instructions
**Storage**: `.shelf-config` plain-text key-value file at repo root
**Testing**: Manual — run shelf skills and verify behavior (no test suite for Markdown skills)
**Target Platform**: Claude Code plugin system (cross-platform via Claude Code CLI)
**Project Type**: Plugin (Claude Code skill definitions)
**Performance Goals**: N/A — skill files are interpreted at invocation time
**Constraints**: Config must be parseable with basic shell tools (`grep`, `sed`, `awk`) — no JSON/YAML dependency
**Scale/Scope**: 6 SKILL.md files to modify, 1 new artifact file format to define

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| Spec-First Development | PASS | spec.md exists with FRs, user stories, acceptance scenarios |
| 80% Test Coverage | N/A | No compiled code — this is a Markdown-only plugin |
| PRD as Source of Truth | PASS | PRD at docs/features/2026-04-03-shelf-config-artifact/PRD.md is authoritative |
| Hooks Enforce Rules | PASS | Existing hooks allow edits to plugin skill files |
| E2E Testing Required | N/A | No compiled artifact — skills are Markdown instructions |
| Small Focused Changes | PASS | Each skill file gets a targeted modification to path resolution |
| Interface Contracts | PASS | contracts/interfaces.md will define the .shelf-config format and path resolution algorithm |
| Incremental Task Completion | PASS | Tasks will be marked [X] as each skill file is modified |

## Project Structure

### Documentation (this feature)

```text
specs/shelf-config-artifact/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── contracts/
│   └── interfaces.md    # .shelf-config format + path resolution algorithm
└── tasks.md             # Phase 2 output (created by /tasks)
```

### Source Code (files to modify)

```text
plugin-shelf/skills/
├── shelf-create/SKILL.md     # Add: write .shelf-config after project creation (Step 9.5)
├── shelf-sync/SKILL.md       # Modify: Steps 1-2 to read slug from .shelf-config
├── shelf-update/SKILL.md     # Modify: Steps 1-2 to read slug from .shelf-config
├── shelf-status/SKILL.md     # Modify: Steps 1-2 to read slug from .shelf-config
├── shelf-feedback/SKILL.md   # Modify: Steps 1-2 to read slug from .shelf-config
└── shelf-release/SKILL.md    # Modify: Steps 1-2 to read slug from .shelf-config
```

**Structure Decision**: No new directories or files beyond the `.shelf-config` artifact itself (which is created at runtime in consumer projects). All changes are modifications to existing SKILL.md files in the plugin-shelf package.

## Deployment Readiness

| Artifact | Path | Required? | Notes |
|----------|------|-----------|-------|
| npm package | plugin-shelf/package.json | Yes | Bump version after changes, publish via `npm publish` |

**Deployment notes**: After modifying the skill files, the plugin-shelf package version should be bumped and published. Consumer projects update via `npm update @yoshisada/shelf` or plugin cache refresh.

## Complexity Tracking

No constitution violations. All changes are small, focused modifications to existing files.
