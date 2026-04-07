# Feature Specification: Clay Idea Entrypoint

**Feature Branch**: `build/clay-idea-entrypoint-20260407`
**Created**: 2026-04-07
**Status**: Draft
**Input**: User description: "Clay Idea Entrypoint — /clay:idea skill (FR-001-007) as the primary entrypoint that takes a raw idea, checks products/ and clay.config for overlap, routes to new product or existing product/repo. Plus clay.config plain-text registry (FR-008-012) and integration updates to create-repo and clay-list (FR-013-014)."

## User Scenarios & Testing

### User Story 1 - New Idea with No Overlap (Priority: P1)

As a developer with a raw idea, I run `/clay:idea "build a habit tracker"` and the system scans my products/ directory and clay.config, finds no overlap, and routes me through the full new-product pipeline: idea-research → project-naming → create-prd.

**Why this priority**: This is the primary happy path — the most common use case for a new idea entering the system.

**Independent Test**: Run `/clay:idea` with an idea description when products/ is empty and clay.config doesn't exist. Verify it presents "New product" as the recommended route and chains to `/idea-research`.

**Acceptance Scenarios**:

1. **Given** no products/ directory and no clay.config, **When** user runs `/clay:idea "build a habit tracker"`, **Then** the skill presents "New product" as the route and offers to chain to `/idea-research`
2. **Given** products/ exists with unrelated products, **When** user runs `/clay:idea "build a habit tracker"`, **Then** the skill finds no overlap and routes to "New product"
3. **Given** the user confirms "New product" route, **When** the skill chains forward, **Then** it runs `/idea-research` first, then offers `/project-naming`, then `/create-prd` — in sequence, with user confirmation at each step

---

### User Story 2 - Overlap with Existing Product (Priority: P2)

As a developer, when I describe an idea that overlaps with an existing product in products/, the system detects the overlap and suggests adding it as a feature to that product instead of creating a new one.

**Why this priority**: Prevents duplicated effort and keeps the portfolio organized.

**Independent Test**: Create a products/todo-app/ directory with a research.md describing a task management app. Run `/clay:idea "build a task list with reminders"`. Verify it detects overlap and suggests "Add to existing product."

**Acceptance Scenarios**:

1. **Given** products/todo-app/ exists with research.md describing a task manager, **When** user runs `/clay:idea "build a task list with reminders"`, **Then** the skill presents "Add to existing product: todo-app" as a routing option
2. **Given** partial overlap detected, **When** the skill presents options, **Then** it includes "Similar but distinct" as an alternative route letting the user decide
3. **Given** user selects "Add to existing product", **When** the skill chains forward, **Then** it runs `/create-prd` in Mode C (feature addition) targeting the matched product

---

### User Story 3 - Overlap with Tracked Repo (Priority: P2)

As a developer, when I describe an idea that overlaps with a repo tracked in clay.config, the system suggests working in that existing repo.

**Why this priority**: Prevents creating a new repo when an existing one covers the same space.

**Independent Test**: Create a clay.config with an entry for a "notes-app" repo. Run `/clay:idea "build a note taking tool"`. Verify it detects overlap and suggests "Work in existing repo."

**Acceptance Scenarios**:

1. **Given** clay.config contains `notes-app https://github.com/user/notes-app /path/to/notes-app 2026-04-01`, **When** user runs `/clay:idea "build a note taking tool"`, **Then** the skill presents "Work in existing repo: notes-app" as a routing option with the repo URL
2. **Given** user selects "Work in existing repo", **When** the skill chains forward, **Then** it suggests opening that repo and running `/build-prd` or `/clay:idea` there

---

### User Story 4 - Repo Tracking via create-repo (Priority: P1)

As a developer, when I run `/clay:create-repo` and it successfully creates a repo, the repo details are automatically appended to clay.config so my portfolio is tracked.

**Why this priority**: The registry must be populated for overlap detection to work. Tied directly to US-1/US-3.

**Independent Test**: Run `/clay:create-repo` for a product. Verify clay.config is created (if it doesn't exist) and an entry is appended with the correct format.

**Acceptance Scenarios**:

1. **Given** no clay.config exists, **When** `/clay:create-repo` creates a repo at `https://github.com/user/my-app` cloned to `../my-app`, **Then** clay.config is created with one entry: `my-app https://github.com/user/my-app ../my-app 2026-04-07`
2. **Given** clay.config already exists with entries, **When** `/clay:create-repo` creates another repo, **Then** the new entry is appended (not overwritten) to clay.config
3. **Given** the repo creation fails, **When** the skill exits, **Then** no entry is written to clay.config

---

### User Story 5 - Enhanced clay-list with Repo URLs (Priority: P3)

As a developer, when I run `/clay:clay-list`, the output includes repo URLs and local paths from clay.config alongside the existing product status table.

**Why this priority**: Enriches the portfolio view but is not blocking for the core idea skill.

**Independent Test**: Create products/ with a product that has .repo-url AND a clay.config entry. Run `/clay:clay-list`. Verify the output table includes the repo URL and local path columns.

**Acceptance Scenarios**:

1. **Given** products/my-app/ exists with .repo-url AND clay.config has a matching entry, **When** user runs `/clay:clay-list`, **Then** the table includes "Repo URL" and "Local Path" columns populated from clay.config
2. **Given** clay.config does not exist, **When** user runs `/clay:clay-list`, **Then** the table renders normally without repo columns (graceful skip)

---

### Edge Cases

- **Empty idea description**: If user runs `/clay:idea` with no arguments, the skill prompts for a 1-5 sentence idea description
- **Malformed clay.config**: Lines that don't match the expected 4-field format are silently skipped with a warning
- **Multiple overlaps**: If the idea overlaps with both a product and a tracked repo, all matches are presented with similarity reasoning
- **clay.config with stale entries**: Repos that have been moved or deleted are still listed (no auto-cleanup in v1)
- **Concurrent writes to clay.config**: Not handled in v1 — single-user assumption

## Requirements

### Functional Requirements

- **FR-001**: `/clay:idea` MUST accept a 1-5 sentence idea description as input (prompt if empty)
- **FR-002**: `/clay:idea` MUST read all existing products from `products/` directory — extract names, descriptions, and PRD summaries
- **FR-003**: `/clay:idea` MUST read `clay.config` to get list of tracked repos with their descriptions and URLs
- **FR-004**: `/clay:idea` MUST compare the input idea against existing products and tracked repos for semantic overlap
- **FR-005**: `/clay:idea` MUST present findings with routing options: "New product", "Add to existing product", "Work in existing repo", "Similar but distinct"
- **FR-006**: `/clay:idea` MUST chain to the appropriate clay skill after user confirmation (never auto-execute)
- **FR-007**: When routing to "new product", `/clay:idea` MUST run `/idea-research` first, then offer `/project-naming`, then `/create-prd` in sequence
- **FR-008**: `clay.config` MUST be a plain-text file at the project root with format: `<product-slug> <repo-url> <local-path> <created-date>` (one entry per line)
- **FR-009**: `/clay:create-repo` MUST automatically append an entry to `clay.config` after successfully creating a repo
- **FR-010**: `/clay:idea` MUST read `clay.config` to discover tracked repos for overlap detection
- **FR-011**: `/clay:clay-list` MUST read `clay.config` and show repo URLs alongside product status
- **FR-012**: If `clay.config` doesn't exist, skills that read it MUST gracefully skip repo-based overlap detection
- **FR-013**: `/clay:create-repo` MUST be updated to write to `clay.config` after repo creation (append, not overwrite)
- **FR-014**: `/clay:clay-list` MUST be updated to include repo URL and local path from `clay.config` in its output

### Key Entities

- **Idea**: A 1-5 sentence user description of a product concept
- **Product**: A directory under `products/<slug>/` containing research, naming, and PRD artifacts
- **Tracked Repo**: An entry in `clay.config` representing a created GitHub repository
- **Route**: One of four destinations for an idea: new-product, existing-product, existing-repo, similar-but-distinct

## Success Criteria

### Measurable Outcomes

- **SC-001**: `/clay:idea "build a todo app"` correctly detects if a similar product exists in `products/` and presents appropriate routing
- **SC-002**: Repos created via `/clay:create-repo` automatically appear in `clay.config` with correct format
- **SC-003**: `/clay:clay-list` shows repo URLs for products that have been turned into repos
- **SC-004**: The idea skill never auto-executes a downstream skill without user confirmation
- **SC-005**: All existing clay skills continue to work without regression

## Assumptions

- clay.config is a local file only — no cross-machine sync
- Overlap detection is LLM-based semantic comparison, not a bash heuristic
- Single-user assumption — no concurrent write handling for clay.config
- Stale entries in clay.config are acceptable for v1 (no auto-cleanup)
- The skill runs in the plugin source repo (ai-repo-template) where products/ lives
