# Implementation Plan: Shelf Skills Polish

**Branch**: `build/shelf-skills-polish-20260408` | **Date**: 2026-04-08 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/shelf-skills-polish/spec.md`

## Summary

Rewrite `shelf-create` as a wheel workflow with deterministic step ordering, add a `shelf-repair` workflow for re-templating existing projects, define canonical status labels in a single-source-of-truth file, and add a summary step to `shelf-full-sync`. All shelf skills that reference project status will be updated to use the canonical list.

## Technical Context

**Language/Version**: Bash 5.x (workflow shell commands), Markdown (skill definitions, status labels config)
**Primary Dependencies**: Wheel workflow engine (`plugin-wheel/`), Obsidian MCP tools (`mcp__obsidian-projects__*`), `jq` (JSON parsing in command steps), `gh` CLI (GitHub operations)
**Storage**: File-based JSON workflows in `plugin-shelf/workflows/`, `.wheel/outputs/` for step outputs, `.wheel/state_*.json` for workflow state
**Testing**: Manual testing via running workflows on consumer projects. No automated test suite for the plugin itself.
**Target Platform**: macOS/Linux (Bash 5.x), Claude Code plugin runtime
**Project Type**: Claude Code plugin (skills + workflows + config files)
**Performance Goals**: `shelf-create` in <=10 MCP calls (NFR-001), `shelf-repair` idempotent (NFR-002)
**Constraints**: All Obsidian writes go through MCP (never filesystem). Workflows must follow command-first/agent-second/summary-last pattern (NFR-004).
**Scale/Scope**: 2 new workflow JSON files, 1 new config file, 1 new skill, updates to 5 existing skills, 1 existing workflow update

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| Spec-First Development | PASS | spec.md exists with FRs and acceptance scenarios |
| 80% Test Coverage | N/A | Plugin source repo — no test suite, testing is done via consumer project runs |
| PRD as Source of Truth | PASS | PRD at `docs/features/2026-04-08-shelf-skills-polish/PRD.md` is authoritative |
| Hooks Enforce Rules | PASS | Not editing `src/` — editing plugin skills/workflows/config, which hooks allow |
| Interface Contracts Before Implementation | PASS | contracts/interfaces.md will be produced in this plan |
| Incremental Task Completion | PASS | Tasks will be marked `[X]` after each completion |

## Project Structure

### Documentation (this feature)

```text
specs/shelf-skills-polish/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── interfaces.md    # Workflow JSON schemas and skill interface contracts
└── tasks.md             # Phase 2 output (/tasks command)
```

### Source Code (repository root)

```text
plugin-shelf/
├── workflows/
│   ├── shelf-create.json       # NEW — shelf-create wheel workflow (FR-001)
│   ├── shelf-repair.json       # NEW — shelf-repair wheel workflow (FR-008)
│   └── shelf-full-sync.json    # MODIFIED — add summary step (FR-014)
├── skills/
│   ├── shelf-create/SKILL.md   # MODIFIED — rewrite as thin wrapper (FR-007)
│   ├── shelf-repair/SKILL.md   # NEW — thin wrapper for shelf-repair workflow
│   ├── shelf-update/SKILL.md   # MODIFIED — reference canonical status labels (FR-013)
│   ├── shelf-status/SKILL.md   # MODIFIED — reference canonical status labels (FR-013)
│   └── shelf-sync/SKILL.md     # MODIFIED — reference canonical status labels (FR-013)
├── status-labels.md            # NEW — canonical status label definitions (FR-012)
└── templates/
    └── dashboard.md            # EXISTING — no changes needed
```

**Structure Decision**: This is a plugin source repo. All deliverables are Markdown files (skills, config), JSON files (workflows), or updates to existing files. No `src/` or `tests/` directories.

## Phases

### Phase 1: Canonical Status Labels + shelf-full-sync Summary

**Deliverables**: `plugin-shelf/status-labels.md`, updated `shelf-full-sync.json`

1. Create `plugin-shelf/status-labels.md` with the six canonical statuses and their descriptions (FR-012)
2. Add summary command step to `shelf-full-sync.json` that reads all prior outputs and generates `.wheel/outputs/shelf-full-sync-summary.md` (FR-014, FR-015)

### Phase 2: shelf-create Workflow

**Deliverables**: `plugin-shelf/workflows/shelf-create.json`, rewritten `plugin-shelf/skills/shelf-create/SKILL.md`

1. Create `shelf-create.json` workflow with these steps:
   - `read-shelf-config` (command): read `.shelf-config` or derive defaults
   - `detect-repo-progress` (command): inspect repo for progress signals (FR-005)
   - `detect-tech-stack` (command): scan for config files and dependencies
   - `get-repo-metadata` (command): git remote URL, description
   - `resolve-vault-path` (agent): navigate from vault root via `list_files("/")`, verify/create base_path (FR-003, FR-004)
   - `check-duplicate` (agent): list files at target path, abort if exists
   - `create-project` (agent): create dashboard + about + directory structure using templates (FR-002, FR-006)
   - `write-shelf-config` (command): write `.shelf-config` to repo root
2. Rewrite `shelf-create` skill as thin wrapper that validates input and runs `/wheel-run shelf:shelf-create` (FR-007)

### Phase 3: shelf-repair Workflow + Skill

**Deliverables**: `plugin-shelf/workflows/shelf-repair.json`, `plugin-shelf/skills/shelf-repair/SKILL.md`

1. Create `shelf-repair.json` workflow with these steps:
   - `read-shelf-config` (command): read config
   - `read-current-template` (command): read current template files
   - `read-existing-dashboard` (agent): read current dashboard from Obsidian (FR-010)
   - `generate-diff-report` (agent): compare dashboard to template, write change report (FR-010)
   - `apply-repairs` (agent): update dashboard preserving user content, normalize status labels (FR-009, FR-011)
   - `verify-repair` (agent): re-read dashboard, confirm it matches template
2. Create `shelf-repair` skill as thin wrapper

### Phase 4: Status Label References in Existing Skills

**Deliverables**: Updated `shelf-update/SKILL.md`, `shelf-status/SKILL.md`, `shelf-sync/SKILL.md`

1. Add canonical status label reference to each skill's instructions (FR-013)
2. Add warning/rejection behavior for non-canonical values
