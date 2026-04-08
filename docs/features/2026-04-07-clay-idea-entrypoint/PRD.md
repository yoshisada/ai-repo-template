# Feature PRD: Clay Idea Entrypoint

**Date**: 2026-04-07
**Status**: Draft

## Parent Product

[Plugin Clay](../2026-04-07-plugin-clay/PRD.md) — idea-to-project pipeline plugin for Claude Code.

## Feature Overview

Add `/clay:idea` as the primary entrypoint to the clay plugin. It takes a raw idea, checks for overlap with existing products and tracked repos, decides where it belongs, and routes to the right next step. Also introduces `clay.config` at the project root to track where repos were created.

## Problem / Motivation

Currently clay has individual skills (`/idea-research`, `/create-prd`, `/create-repo`) but no single "start here" command. A user with a new idea has to decide which skill to run first. They also have no way to know if a similar product already exists in their portfolio or in a repo they've already created.

Additionally, once `/create-repo` creates a repo, there's no record of where it went. The user has to remember or search GitHub manually.

## Goals

- Provide a single entrypoint that takes an idea from zero to the right next step
- Detect overlap with existing products in `products/` and repos tracked in `clay.config`
- Route ideas to the right destination: new product, existing product feature, or existing repo
- Track all created repos in `clay.config` for cross-project awareness

## Non-Goals

- Auto-running the entire pipeline without user confirmation
- Syncing `clay.config` across machines (local file only)
- Managing or updating existing repos (just tracking where they are)

## Target Users

Same as plugin-clay: solo founders/developers who go from idea to code frequently.

## Core User Stories

### US-1: Start from Scratch
As a developer with a raw idea, I want to run `/clay:idea` and have it figure out whether this is a new product or belongs somewhere I've already built, so I don't accidentally duplicate work.

### US-2: Route to Existing Product
As a developer, when I describe an idea that overlaps with an existing product in `products/`, I want clay to suggest adding it as a feature to that product instead of creating a new one.

### US-3: Route to Existing Repo
As a developer, when I describe an idea that overlaps with a repo I've already created (tracked in `clay.config`), I want clay to suggest working in that repo instead.

### US-4: Track Created Repos
As a developer, I want all repos created by `/clay:create-repo` to be automatically logged in `clay.config`, so I have a registry of my projects.

## Functional Requirements

### Idea Skill (`/clay:idea`)

- **FR-001**: Accept a 1-5 sentence idea description as input
- **FR-002**: Read all existing products from `products/` directory — extract names, descriptions, and PRD summaries
- **FR-003**: Read `clay.config` to get list of tracked repos with their descriptions and URLs
- **FR-004**: Compare the input idea against existing products and tracked repos for semantic overlap
- **FR-005**: Present findings to the user with routing options:
  - **"New product"** — no overlap found, proceed to `/idea-research` → `/project-naming` → `/create-prd`
  - **"Add to existing product"** — overlap with a product in `products/`, suggest `/create-prd` in Mode B (feature addition) targeting that product
  - **"Work in existing repo"** — overlap with a tracked repo, suggest opening that repo and running `/build-prd` or `/clay:idea` there
  - **"Similar but distinct"** — partial overlap, let the user decide
- **FR-006**: After the user chooses a route, chain to the appropriate clay skill automatically (with user confirmation)
- **FR-007**: If routing to "new product", run `/idea-research` first, then offer `/project-naming`, then `/create-prd` — the full pipeline in sequence

### Clay Config (`clay.config`)

- **FR-008**: `clay.config` is a plain-text file at the project root with one entry per line: `<product-slug> <repo-url> <local-path> <created-date>`
- **FR-009**: `/clay:create-repo` automatically appends an entry to `clay.config` after successfully creating a repo
- **FR-010**: `/clay:idea` reads `clay.config` to discover tracked repos for overlap detection
- **FR-011**: `/clay:clay-list` reads `clay.config` and shows repo URLs alongside product status
- **FR-012**: If `clay.config` doesn't exist, skills that read it gracefully skip repo-based overlap detection

### Integration Updates

- **FR-013**: Update `/clay:create-repo` to write to `clay.config` after repo creation (append, not overwrite)
- **FR-014**: Update `/clay:clay-list` to include repo URL and local path from `clay.config` in its output

## Absolute Musts

1. **Tech stack**: Markdown skills + Bash (same as clay/kiln/wheel/shelf)
2. `clay.config` format must be simple and human-readable (no JSON, no YAML — plain text)
3. `/clay:idea` must always ask for user confirmation before routing — never auto-execute a skill without consent
4. Existing clay skills must not break — this is additive

## Tech Stack

Inherited from plugin-clay — no additions.

## Impact on Existing Features

- **`/clay:create-repo`**: Modified to append to `clay.config` after repo creation
- **`/clay:clay-list`**: Modified to read and display `clay.config` entries
- **All other clay skills**: No changes

## Success Metrics

1. `/clay:idea "build a todo app"` correctly detects if a similar product exists in `products/`
2. Created repos appear in `clay.config` automatically
3. `/clay:clay-list` shows repo URLs for products that have been turned into repos

## Risks / Unknowns

- **Semantic overlap detection**: Comparing a raw idea against existing product descriptions requires LLM reasoning — this is an agent step, not a bash heuristic
- **clay.config drift**: If a user moves or deletes a repo, `clay.config` becomes stale. No auto-cleanup for v1.

## Open Questions

- Should `clay.config` track products that DON'T have repos yet (status: idea, researched)?
