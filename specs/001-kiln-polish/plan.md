# Implementation Plan: Kiln Polish

**Branch**: `build/kiln-polish-20260401` | **Date**: 2026-04-01 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/001-kiln-polish/spec.md`

## Summary

Two self-contained improvements to the kiln plugin: (1) add a "Suggested next" line at the end of `/next` skill output showing the single highest-priority command with a brief reason, and (2) define and enforce a canonical `.kiln/qa/` directory structure across QA skills, agents, init scaffold, and documentation.

## Technical Context

**Language/Version**: Markdown (skill/agent definitions), Bash (shell commands within skills), Node.js (init.mjs scaffold)
**Primary Dependencies**: None — uses existing kiln plugin infrastructure
**Storage**: Filesystem — `.kiln/qa/` for QA artifacts
**Testing**: Manual — run `/next` on test projects, run `init.mjs` and `/qa-setup` to verify directory creation
**Target Platform**: Any platform supported by Claude Code
**Project Type**: Claude Code plugin (markdown skills + shell scripts + Node.js scaffold)
**Performance Goals**: N/A — no runtime performance requirements
**Constraints**: Changes must be backwards-compatible with existing `.kiln/qa/` files
**Scale/Scope**: 4 skill files modified, 1 scaffold script modified, 1 new README file, 1 manifest update

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| Spec-First Development | PASS | spec.md exists with FR-001 through FR-008 |
| 80% Test Coverage | N/A | No compiled code — plugin is markdown, bash, and scaffold scripts |
| PRD as Source of Truth | PASS | PRD at docs/features/2026-04-01-kiln-polish/PRD.md |
| Hooks Enforce Rules | PASS | No changes to hook enforcement logic |
| E2E Testing Required | N/A | No CLI, API, or compiled user-facing tool being created |
| Small, Focused Changes | PASS | Two bounded changes, each touching a small number of files |
| Interface Contracts Before Implementation | PASS | Contracts defined below |
| Incremental Task Completion | PASS | Will be enforced during /implement |

## Project Structure

### Documentation (this feature)

```text
specs/001-kiln-polish/
├── spec.md
├── plan.md              # This file
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── interfaces.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Created by /tasks
```

### Source Code (repository root)

```text
plugin/
├── skills/
│   └── next/
│       └── SKILL.md           # FR-001, FR-002, FR-003: Add "Suggested next" output
├── skills/
│   └── qa-setup/
│       └── SKILL.md           # FR-005: Update to create standardized QA dirs
├── agents/
│   ├── qa-engineer.md         # FR-006: Update output paths
│   ├── qa-reporter.md         # FR-006: Update output paths
│   └── ux-evaluator.md        # FR-006: Update output paths
├── templates/
│   └── kiln-manifest.json     # FR-004: Update manifest with QA subdirectories
├── scaffold/
│   └── qa-readme.md           # FR-008: README template for .kiln/qa/
└── bin/
    └── init.mjs               # FR-007: Create QA subdirectories during scaffold
```

**Structure Decision**: This feature modifies existing plugin skill/agent markdown files and the init.mjs scaffold. No new source directories are needed. One new scaffold template file (`qa-readme.md`) is added.

## Deployment Readiness

| Artifact | Path | Required? | Notes |
|----------|------|-----------|-------|
| npm publish | plugin/ | Yes | Publish updated plugin to npm after merge |

**Deployment notes**: Consumer projects pick up changes via `npx @yoshisada/kiln update` (re-syncs templates) or by reinstalling the plugin. QA directory changes are backwards-compatible — existing files are preserved.

## Complexity Tracking

No constitution violations. No complexity justifications needed.
