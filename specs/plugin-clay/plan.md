# Implementation Plan: Plugin Clay

**Branch**: `build/plugin-clay-20260407` | **Date**: 2026-04-07 | **Spec**: `specs/plugin-clay/spec.md`
**Input**: Feature specification from `specs/plugin-clay/spec.md`

## Summary

Create `plugin-clay/`, a new Claude Code plugin that owns the idea-to-project pipeline (research, naming, PRD creation, repo scaffolding). Implement 5 skills as Markdown SKILL.md files with embedded Bash, a wheel workflow for Obsidian sync, and extend wheel's engine to discover workflows from installed plugins. All 37 FRs from the PRD are covered.

## Technical Context

**Language/Version**: Bash 5.x (shell commands in skills), Markdown (skill definitions), JSON (plugin manifests, wheel workflows)
**Primary Dependencies**: `jq` (JSON parsing), `gh` CLI (GitHub operations), wheel engine (workflow execution), shelf MCP (Obsidian sync)
**Storage**: Filesystem — `products/` directory tree for artifacts, `plugin-clay/workflows/` for bundled workflows
**Testing**: Manual pipeline execution — no automated test suite (same as kiln/wheel/shelf plugins)
**Target Platform**: macOS/Linux with Claude Code installed
**Project Type**: Claude Code plugin (Markdown + Bash)
**Constraints**: No new runtime dependencies beyond existing kiln/wheel/shelf ecosystem. Clean break from kiln — no imports of kiln skills.

## Constitution Check

- [x] Spec-first: spec.md written before implementation
- [x] PRD as source of truth: PRD at `docs/features/2026-04-07-plugin-clay/PRD.md`
- [x] Interface contracts: contracts/interfaces.md will define all exported functions
- [x] Small focused changes: Plugin structure mirrors existing conventions, each skill is a single SKILL.md
- [x] 80% coverage gate: N/A — plugin is Markdown + Bash skills, no compiled code with coverage tooling
- [x] E2E testing: Pipeline walkthrough validates end-to-end (research -> naming -> PRD -> repo)

## Project Structure

### Documentation (this feature)

```text
specs/plugin-clay/
├── spec.md              # Feature specification
├── plan.md              # This file
├── contracts/           # Interface contracts
│   └── interfaces.md    # Function signatures for wheel lib changes
└── tasks.md             # Task breakdown
```

### Source Code (repository root)

```text
plugin-clay/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest (name, version, description, workflows field)
│   └── marketplace.json     # Distribution config
├── skills/
│   ├── idea-research/
│   │   └── SKILL.md         # FR-004 through FR-009
│   ├── project-naming/
│   │   └── SKILL.md         # FR-010 through FR-014
│   ├── create-prd/
│   │   └── SKILL.md         # FR-015 through FR-021
│   ├── create-repo/
│   │   └── SKILL.md         # FR-022 through FR-027
│   └── clay-list/
│       └── SKILL.md         # FR-036, FR-037
├── workflows/
│   └── clay-sync.json       # FR-032 through FR-035 (Obsidian sync workflow)
└── package.json             # npm package: @yoshisada/clay

# Wheel engine changes (FR-028 through FR-031)
plugin-wheel/
├── lib/
│   └── workflow.sh           # Add workflow_discover_plugin_workflows() function
├── skills/
│   ├── wheel-list/
│   │   └── SKILL.md          # Update to show plugin workflows
│   └── wheel-run/
│       └── SKILL.md          # Update to accept <plugin>:<name> syntax
└── .claude-plugin/
    └── plugin.json           # Add "workflows" field to schema (self-referencing)
```

**Structure Decision**: Plugin follows the exact same pattern as kiln, wheel, and shelf. Each skill is a directory containing SKILL.md. The only compiled code touched is wheel's `workflow.sh` library (Bash functions).

## Phased Implementation

### Phase 1: Plugin Scaffold (FR-001, FR-002, FR-003)

Create the plugin-clay directory structure with manifests and package.json. This is pure scaffolding — no skill logic yet.

**Files created**:
- `plugin-clay/.claude-plugin/plugin.json`
- `plugin-clay/.claude-plugin/marketplace.json`
- `plugin-clay/package.json`
- `plugin-clay/skills/` (empty directory placeholder)
- `plugin-clay/workflows/` (empty directory placeholder)

### Phase 2: Wheel Manifest Enhancement (FR-028, FR-029, FR-030, FR-031)

Extend wheel to discover workflows from installed plugins. This must happen before clay's Obsidian workflow can be discovered.

**Files modified**:
- `plugin-wheel/lib/workflow.sh` — add `workflow_discover_plugin_workflows()` function
- `plugin-wheel/skills/wheel-list/SKILL.md` — add plugin workflow discovery step
- `plugin-wheel/skills/wheel-run/SKILL.md` — add `<plugin>:<name>` resolution in Step 1

**Key design decisions**:
- Plugin workflows discovered by scanning `.claude/plugins/*/plugin.json` for a `workflows` field
- Each entry is a relative path from plugin root to a workflow JSON file
- `workflow_discover_plugin_workflows()` returns JSON array of `{name, plugin, path, readonly: true}` objects
- `/wheel-run` resolves `clay:clay-sync` to the plugin's workflow file path, then proceeds as normal
- Local `workflows/` copies override plugin versions (name collision = local wins)

### Phase 3: Idea Research Skill (FR-004 through FR-009)

Create the `/idea-research` SKILL.md. Reimplements the `idea-research` skill from yoshisada/skills as a clay plugin skill.

**Files created**:
- `plugin-clay/skills/idea-research/SKILL.md`

**Key design decisions**:
- Uses WebSearch tool for market research (same approach as the standalone skill)
- Derives product slug from idea description using simple kebab-case transformation
- Creates `products/<slug>/` directory if it doesn't exist
- Report format matches the standalone skill's structure but outputs to the products directory
- Classification rubric: EXACT MATCH, CLOSE COMPETITOR, ADJACENT, SLIGHTLY SIMILAR (from reference skill)

### Phase 4: Project Naming Skill (FR-010 through FR-014)

Create the `/project-naming` SKILL.md. Reimplements the `project-naming` skill from yoshisada/skills.

**Files created**:
- `plugin-clay/skills/project-naming/SKILL.md`

**Key design decisions**:
- Reads product context from `products/<slug>/research.md` if available, or from user input
- Availability checks use WebSearch for npm, GitHub, and domain lookups
- Iterative refinement via conversational follow-up (same pattern as reference skill)
- Output to `products/<slug>/naming.md`

### Phase 5: Create PRD Skill (FR-015 through FR-021)

Create the `/create-prd` SKILL.md. Merges kiln's `/create-prd` and `founder-prd` from yoshisada/skills.

**Files created**:
- `plugin-clay/skills/create-prd/SKILL.md`

**Key design decisions**:
- Three modes detected from user input: Mode A (no existing product), Mode B (existing product mentioned), Mode C (explicit PRD-only workspace request)
- Clarifying questions follow the `founder-prd` pattern: 10 questions covering product, users, problem, use cases, MVP, scope control, success, constraints, tech stack, risks
- Tech stack enforcement from `founder-prd`: never undefined, propose defaults if user doesn't know
- "Absolute Musts" section with tech stack always first (from `founder-prd`)
- Incorporates `research.md` and `naming.md` if they exist in the product directory
- Output: 3 files (PRD.md, PRD-MVP.md, PRD-Phases.md) under `products/<slug>/`

### Phase 6: Create Repo Skill (FR-022 through FR-027)

Create the `/create-repo` SKILL.md. Reimplements kiln's `/create-repo` with clay-specific enhancements.

**Files created**:
- `plugin-clay/skills/create-repo/SKILL.md`

**Key design decisions**:
- Uses `gh repo create` for GitHub operations (same as kiln's version)
- Scaffolds kiln infrastructure via `node plugin-kiln/bin/init.mjs init` in the new repo
- Seeds PRD artifacts from `products/<slug>/` into `docs/`
- Installs kiln, wheel, shelf plugins (via `claude mcp add` or equivalent)
- Suggests `/build-prd` as next step (never auto-runs it)

### Phase 7: Clay List Skill (FR-036, FR-037)

Create the `/clay-list` SKILL.md for portfolio management.

**Files created**:
- `plugin-clay/skills/clay-list/SKILL.md`

**Key design decisions**:
- Scans `products/*/` directories
- Derives status from artifact presence: directory only = "idea", research.md = "researched", naming.md = "named", PRD.md = "PRD-created", .repo-url marker = "repo-created"
- Tabular output with product name, status, and artifact count

### Phase 8: Obsidian Sync Workflow (FR-032 through FR-035)

Create the `clay-sync.json` wheel workflow and declare it in clay's plugin manifest.

**Files created**:
- `plugin-clay/workflows/clay-sync.json`

**Files modified**:
- `plugin-clay/.claude-plugin/plugin.json` — add `workflows` field

**Key design decisions**:
- Workflow has 3 steps: (1) scan products directory, (2) create/update Obsidian notes via shelf MCP, (3) sync research findings as linked notes
- Product status derived the same way as `/clay-list`
- Uses shelf's `mcp__obsidian-projects__create_file` and `mcp__obsidian-projects__update_file` for Obsidian operations
- Research findings become separate linked notes, not inline in the product note

## Complexity Tracking

No constitution violations identified. The implementation follows existing patterns exactly:
- Each skill is a single SKILL.md (same as kiln/wheel/shelf skills)
- Wheel library extension is a single new function plus two skill updates
- No new abstractions, frameworks, or runtime dependencies
