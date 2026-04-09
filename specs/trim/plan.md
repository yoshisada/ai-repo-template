# Implementation Plan: Trim — Bidirectional Design-Code Sync Plugin

**Branch**: `build/trim-20260409` | **Date**: 2026-04-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/trim/spec.md`

## Summary

Trim is a Claude Code plugin that bridges Penpot designs and code via the Penpot MCP. It provides 6 skills (`/trim-pull`, `/trim-push`, `/trim-diff`, `/trim-library`, `/trim-design`, `/trim-config`) with wheel workflows for all multi-step operations. The plugin follows the established plugin pattern (same structure as `plugin-shelf/`) and uses command-first/agent-second workflow steps. All Penpot interactions go through MCP tools — no direct API calls.

## Technical Context

**Language/Version**: Bash 5.x (hook/command scripts), Markdown (skill/agent definitions), JSON (workflow definitions, config files)
**Primary Dependencies**: Penpot MCP tools, wheel engine (`plugin-wheel/`), `jq` (JSON parsing in command steps), `gh` CLI (optional, for issue filing)
**Storage**: File-based — `.trim-config` (key-value), `.trim-components.json` (JSON), `.wheel/outputs/` (step outputs)
**Testing**: No test suite for the plugin itself. Testing is done by running the skills on consumer projects.
**Target Platform**: macOS/Linux (Claude Code environments)
**Project Type**: Claude Code plugin (skills + workflows + templates)
**Performance Goals**: Single component pull/push completes in under 5 minutes
**Constraints**: Zero additional runtime dependencies beyond Claude Code and Penpot MCP
**Scale/Scope**: 6 skills, 5 wheel workflows, 1 config file, 1 component mapping file

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| Spec-First Development | PASS | spec.md exists with FRs, user stories, acceptance scenarios |
| 80% Test Coverage | N/A | Plugin is markdown/bash/JSON — no test suite (same as shelf, wheel, kiln) |
| PRD as Source of Truth | PASS | PRD at docs/features/2026-04-09-trim/PRD.md is authoritative |
| Hooks Enforce Rules | PASS | Existing kiln hooks already enforce the spec-first workflow |
| E2E Testing Required | N/A | Plugin skills are markdown files — tested by running on consumer projects |
| Small, Focused Changes | PASS | Each skill is a separate file; each workflow is a separate JSON |
| Interface Contracts Before Implementation | PASS | contracts/interfaces.md will be generated in this plan |
| Incremental Task Completion | PASS | Tasks will be structured for incremental completion |

## Project Structure

### Documentation (this feature)

```text
specs/trim/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── interfaces.md
├── checklists/
│   └── requirements.md
├── agent-notes/
│   └── specifier.md
└── tasks.md             # Phase 2 output (/tasks command)
```

### Source Code (repository root)

```text
plugin-trim/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest (name, version, description)
│   └── marketplace.json     # Distribution config
├── skills/
│   ├── trim-pull/
│   │   └── SKILL.md         # Design → code skill (delegates to wheel workflow)
│   ├── trim-push/
│   │   └── SKILL.md         # Code → design skill (delegates to wheel workflow)
│   ├── trim-diff/
│   │   └── SKILL.md         # Drift detection skill (delegates to wheel workflow)
│   ├── trim-library/
│   │   └── SKILL.md         # Component library management skill
│   ├── trim-design/
│   │   └── SKILL.md         # Design generation skill (delegates to wheel workflow)
│   └── trim-config/
│       └── SKILL.md         # Configuration setup skill
├── workflows/
│   ├── trim-pull.json       # Penpot → code wheel workflow
│   ├── trim-push.json       # Code → Penpot wheel workflow
│   ├── trim-diff.json       # Drift detection wheel workflow
│   ├── trim-design.json     # Design generation wheel workflow
│   └── trim-library-sync.json  # Library sync wheel workflow
├── templates/
│   ├── trim-config.tpl      # Default .trim-config template
│   └── trim-components.tpl  # Default .trim-components.json template
└── package.json             # npm package: @yoshisada/trim
```

**Structure Decision**: Follows the established plugin pattern used by `plugin-shelf/`, `plugin-wheel/`, and `plugin-kiln/`. Each skill is a markdown file in its own directory. Each multi-step operation is a wheel workflow JSON. Templates provide defaults for config files scaffolded into consumer projects.

## Phases

### Phase 1: Core Infrastructure
Create the plugin scaffold, config skill, and component mapping schema.

**Files**:
- `plugin-trim/.claude-plugin/plugin.json`
- `plugin-trim/.claude-plugin/marketplace.json`
- `plugin-trim/package.json`
- `plugin-trim/skills/trim-config/SKILL.md`
- `plugin-trim/templates/trim-config.tpl`
- `plugin-trim/templates/trim-components.tpl`

### Phase 2: Pull Workflow (Design → Code)
Create the trim-pull skill and wheel workflow. Command steps: read config, detect framework, read Penpot design via MCP. Agent steps: generate framework-appropriate code, update component mappings.

**Files**:
- `plugin-trim/skills/trim-pull/SKILL.md`
- `plugin-trim/workflows/trim-pull.json`

### Phase 3: Push Workflow (Code → Design)
Create the trim-push skill and wheel workflow. Command steps: read config, scan codebase for UI components. Agent steps: create/update Penpot components via MCP, update component mappings.

**Files**:
- `plugin-trim/skills/trim-push/SKILL.md`
- `plugin-trim/workflows/trim-push.json`

### Phase 4: Diff Workflow (Drift Detection)
Create the trim-diff skill and wheel workflow. Command steps: read config, read component mappings. Agent steps: compare Penpot state vs code state, generate categorized drift report.

**Files**:
- `plugin-trim/skills/trim-diff/SKILL.md`
- `plugin-trim/workflows/trim-diff.json`

### Phase 5: Library Management
Create the trim-library skill (inline, no workflow needed for list mode) and the library-sync wheel workflow for the sync subcommand.

**Files**:
- `plugin-trim/skills/trim-library/SKILL.md`
- `plugin-trim/workflows/trim-library-sync.json`

### Phase 6: Design Generation
Create the trim-design skill and wheel workflow. Command steps: read PRD, read existing components, detect conventions. Agent steps: generate Penpot design via MCP.

**Files**:
- `plugin-trim/skills/trim-design/SKILL.md`
- `plugin-trim/workflows/trim-design.json`

## Complexity Tracking

No constitution violations. All files are under 500 lines. No abstractions beyond the established plugin patterns.
