# Feature PRD: Plugin Clay

**Date**: 2026-04-07
**Status**: Draft

## Parent Product

[Kiln Plugin Ecosystem](../../PRD.md) — spec-first development workflow plugins for Claude Code. Clay is a new sibling plugin to kiln, wheel, and shelf, focused on the pre-development pipeline: turning raw ideas into structured PRDs and scaffolded repositories.

## Feature Overview

`plugin-clay` is a Claude Code plugin that owns the idea-to-project pipeline. It takes a rough product idea through market research, naming, PRD creation, and repo scaffolding — producing a ready-to-build project that kiln's `/build-prd` can execute against.

Clay consolidates and reimplements scattered PRD/repo functionality:
- Kiln's `/create-prd` and `/create-repo` are replaced by clay's versions (clean break, not a wrapper)
- Five standalone skills from `yoshisada/skills` are reimplemented as clay plugin skills
- Wheel + shelf integration enables idea/PRD tracking in Obsidian

## Problem / Motivation

The pipeline from "I have an idea" to "I'm building it" is fragmented:
1. PRD creation lives inside kiln, but kiln is a build tool — PRD work is a separate concern
2. Market research, naming, and repo scaffolding are standalone skills in a separate repo with no plugin infrastructure
3. There's no unified workflow to go from idea → research → name → PRD → repo
4. Ideas and PRDs aren't tracked in the Obsidian product suite, so product thinking happens outside the knowledge system

Clay solves this by owning everything before `git init` — from the first spark of an idea through to a scaffolded repo ready for kiln.

## Goals

- Provide a single plugin for the entire pre-development pipeline: research → name → PRD → repo
- Reimplement PRD creation as a first-class clay skill (merged from kiln's create-prd + founder-prd from skills repo)
- Move repo scaffolding out of kiln into clay where it belongs
- Track ideas and PRDs in Obsidian via wheel + shelf integration
- Support multi-product management via `products/<slug>/` directory structure
- Work standalone (without kiln) for users who only want PRD tooling

## Non-Goals

- Multi-user collaboration on PRDs
- Post-repo project management (kiln's job — clay hands off after repo creation)
- `speckit-prd-workflow` integration (stays in kiln's domain)
- Auto-executing `/build-prd` after repo creation (suggest it, don't run it)
- Replacing kiln's spec/plan/tasks/implement pipeline

## Target Users

- **Solo founders/developers** who go from idea to code frequently
- **Product thinkers** who want structured PRD creation with market research
- **Existing kiln users** who want a dedicated pre-development workflow

## Core User Stories

### US-1: Research Before Building
As a developer with a product idea, I want to research the market landscape before committing to a PRD, so I can validate the idea and understand what already exists.

### US-2: Name My Product
As a founder, I want help naming my product with brand availability checks, so I can pick a distinctive name before creating the PRD.

### US-3: Create a Structured PRD
As a developer, I want to answer a series of clarifying questions and get a complete PRD set (PRD.md + PRD-MVP.md + PRD-Phases.md), so I have a clear product spec to build against.

### US-4: Turn a PRD into a Repo
As a developer with a finished PRD, I want to create a GitHub repo scaffolded with kiln infrastructure and my PRD seeded into `docs/`, so I can immediately start building with `/build-prd`.

### US-5: Track Ideas in Obsidian
As a product thinker, I want my ideas, research findings, and PRDs synced to my Obsidian vault, so my product thinking lives alongside my knowledge system.

### US-6: Manage Multiple Products
As a developer with multiple product ideas, I want PRDs organized under `products/<slug>/` with a list view, so I can manage my product portfolio.

## Functional Requirements

### Plugin Infrastructure

- **FR-001**: Create `plugin-clay/` directory structure mirroring kiln/wheel/shelf conventions: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `skills/`, `package.json`
- **FR-002**: Plugin manifest declares dependency on `wheel` and `shelf` plugins
- **FR-003**: Plugin registers all clay skills as `/clay:<skill-name>` commands

### Idea Research Skill (`/idea-research`)

- **FR-004**: Accept a 1-5 sentence idea description as input
- **FR-005**: Search the web for similar products, startups, and open source projects
- **FR-006**: Classify findings into categories: exact match, close competitor, adjacent alternative, loosely similar
- **FR-007**: Output a structured research report to `products/<slug>/research.md` (or `.clay/research/` if no product slug yet)
- **FR-008**: Report includes: product name, URL, description, similarity classification, key differentiators, pricing model (if available)
- **FR-009**: Summarize findings with a go/no-go recommendation based on market density

### Project Naming Skill (`/project-naming`)

- **FR-010**: Accept product context (from PRD, research report, or user description)
- **FR-011**: Generate 5-10 candidate names with rationale for each
- **FR-012**: For each name, check: npm package availability, GitHub org/repo availability, .com/.dev/.io domain likelihood
- **FR-013**: Output a naming report to `products/<slug>/naming.md` with ranked recommendations
- **FR-014**: Support iterative refinement — user can say "more like X" or "avoid Y patterns"

### PRD Creation Skill (`/create-prd`)

- **FR-015**: Merge functionality from kiln's current `/create-prd` and the `founder-prd` skill from yoshisada/skills
- **FR-016**: Support three modes: Mode A (new product PRD), Mode B (feature addition to existing product), Mode C (PRD-only repo with `products/` directory)
- **FR-017**: Ask clarifying questions one at a time with multiple-choice options where inferable
- **FR-018**: Generate 3-file PRD set: `PRD.md`, `PRD-MVP.md`, `PRD-Phases.md`
- **FR-019**: Store PRDs under `products/<product-slug>/` by default
- **FR-020**: If research.md or naming.md exist for the product, incorporate their findings into the PRD automatically
- **FR-021**: Enforce tech stack definition — never leave it undefined

### Repo Creation Skill (`/create-repo`)

- **FR-022**: Create a GitHub repository from a finished PRD (replaces kiln's `/create-repo`)
- **FR-023**: Scaffold the new repo with kiln infrastructure (CLAUDE.md, templates, constitution, project structure)
- **FR-024**: Seed the PRD artifacts from `products/<slug>/` into the new repo's `docs/` directory
- **FR-025**: Support visibility options (public/private) and custom GitHub org/user
- **FR-026**: Install kiln, wheel, and shelf plugins in the new repo
- **FR-027**: After creation, suggest next step: "Run `/build-prd` in the new repo to start building"

### Wheel Workflow Manifest (prerequisite — wheel enhancement)

- **FR-028**: Extend wheel's `plugin.json` schema to support a `workflows` field — an array of workflow file paths relative to the plugin root that the plugin exposes
- **FR-029**: Wheel's engine and `/wheel-list` must discover workflows from all installed plugins by reading each plugin's `plugin.json` manifest, in addition to the project-level `workflows/` directory
- **FR-030**: Plugin-provided workflows are read-only from the consumer's perspective — they execute but cannot be edited in-place. Users can copy them to `workflows/` to customize.
- **FR-031**: `/wheel-run` accepts both project workflows (by name) and plugin workflows (by `<plugin>:<workflow-name>` syntax, e.g., `clay:clay-sync`)

### Obsidian Integration (via wheel + shelf)

- **FR-032**: Ship a wheel workflow (`plugin-clay/workflows/clay-sync.json`) declared in clay's `plugin.json` manifest that syncs product ideas and PRDs to Obsidian
- **FR-033**: Each product in `products/` gets an Obsidian note with: name, status (idea/researched/PRD-created/repo-created), links to artifacts
- **FR-034**: Research findings sync as linked notes in Obsidian
- **FR-035**: PRD phase transitions update the Obsidian note status

### Product Portfolio Management

- **FR-036**: Provide a `/clay-list` skill that shows all products under `products/` with their status (idea, researched, PRD-created, repo-created)
- **FR-037**: Each product directory follows the structure: `products/<slug>/research.md`, `products/<slug>/naming.md`, `products/<slug>/PRD.md`, `products/<slug>/PRD-MVP.md`, `products/<slug>/PRD-Phases.md`

## Absolute Musts

1. **Tech stack**: Markdown skills + Bash (same as kiln/wheel/shelf) — no new runtime dependencies
2. **Plugin dependency**: wheel + shelf must be declared as dependencies
3. **Clean break from kiln**: Clay reimplements, not wraps — no import/require of kiln skills
4. **Kiln's `/create-prd` and `/create-repo` remain functional** — clay doesn't break kiln, it provides alternatives. Kiln's versions can be deprecated later.
5. **PRD quality**: Generated PRDs must be buildable by kiln's `/build-prd` without modification
6. **Obsidian sync**: Ideas and PRDs must be trackable in the Obsidian product suite via wheel workflows

## Tech Stack

Inherited from kiln/wheel/shelf plugin ecosystem — no additions:
- Markdown (skill definitions)
- Bash 5.x (shell commands within skills)
- jq (JSON parsing for wheel workflows)
- `gh` CLI (GitHub operations for repo creation)
- Wheel engine (workflow execution for Obsidian sync)
- Shelf MCP (Obsidian note management)

## Impact on Existing Features

- **Kiln `/create-prd`**: Superseded by clay's version. Kiln's stays functional but should be deprecated with a message: "Use `/clay:create-prd` for the full idea-to-project pipeline."
- **Kiln `/create-repo`**: Moved to clay. Kiln's stays functional but should show deprecation notice.
- **Wheel**: No impact — clay uses wheel as a dependency for workflows
- **Shelf**: No impact — clay uses shelf for Obsidian sync via wheel workflows

## Success Metrics

1. Full pipeline (`/idea-research` → `/project-naming` → `/create-prd` → `/create-repo`) completes in a single session
2. Generated PRDs pass kiln's `/build-prd` without manual edits
3. Products tracked in Obsidian via `/clay-sync` workflow
4. All 4 skills work standalone (any can be run independently without the others)

## Risks / Unknowns

- **Market research quality**: Web search results may be noisy — idea-research needs good classification heuristics to avoid false matches
- **Name availability checking**: Domain/npm/GitHub availability checks are best-effort (no authoritative API for all registrars)
- **PRD merge complexity**: Merging kiln's create-prd with founder-prd may surface conflicts in question flow or output format — need to pick the best of each
- **Wheel dependency**: Clay requires wheel to be installed for Obsidian sync — should gracefully degrade if wheel isn't available

## Assumptions

- Users have `gh` CLI installed and authenticated (for repo creation)
- Users have the wheel and shelf plugins installed (for Obsidian sync)
- The `products/` directory pattern is acceptable for multi-product management
- Kiln's `/build-prd` accepts PRDs from any location (not hardcoded to `docs/PRD.md`)

## Open Questions

- Should clay have its own hooks, or rely entirely on wheel hooks for workflow execution?
- Should `/create-repo` also run `/build-prd` automatically, or always just suggest it?
- How should clay handle PRDs that were created outside of clay (e.g., manually written PRDs)?
- What's the exact `plugin.json` schema for the `workflows` field? Proposal: `"workflows": ["workflows/clay-sync.json"]` — array of relative paths from plugin root
