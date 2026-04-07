# Feature Specification: Plugin Clay

**Feature Branch**: `build/plugin-clay-20260407`  
**Created**: 2026-04-07  
**Status**: Draft  
**Input**: User description: "Plugin Clay — a new Claude Code plugin (plugin-clay/) that owns the idea-to-project pipeline. 37 FRs: plugin infrastructure (FR-001-003), idea-research skill (FR-004-009), project-naming skill (FR-010-014), create-prd skill merged from kiln+founder-prd (FR-015-021), create-repo skill moved from kiln (FR-022-027), wheel workflow manifest enhancement (FR-028-031), Obsidian integration via wheel+shelf (FR-032-035), clay-list portfolio management (FR-036-037). Tech stack: Markdown + Bash + jq. Reference yoshisada/skills repo for existing patterns."

## User Scenarios & Testing

### User Story 1 - Research a Product Idea (Priority: P1)

A developer has a rough product idea and wants to understand the competitive landscape before investing effort. They run `/idea-research` with a short description and get a structured report classifying existing products by similarity.

**Why this priority**: Research is the natural first step in the idea-to-project pipeline. Without market context, everything downstream (naming, PRD, repo) risks building something that already exists.

**Independent Test**: Run `/idea-research "a CLI tool that generates changelogs from git history"` and verify a research report is created at `products/<slug>/research.md` with classified findings.

**Acceptance Scenarios**:

1. **Given** a user provides a 1-5 sentence idea description, **When** they run `/idea-research`, **Then** the skill searches for similar products and outputs a structured report to `products/<slug>/research.md`.
2. **Given** the research finds existing products, **When** the report is generated, **Then** each finding is classified as `EXACT MATCH`, `CLOSE COMPETITOR`, `ADJACENT`, or `SLIGHTLY SIMILAR` with evidence.
3. **Given** no product slug exists yet, **When** the skill runs, **Then** it derives a slug from the idea description and creates the `products/<slug>/` directory.
4. **Given** the research is complete, **When** the user reads the report, **Then** it includes a go/no-go recommendation based on market density.

---

### User Story 2 - Name a Product (Priority: P2)

A founder has validated their idea and wants a distinctive, brandable name. They run `/project-naming` and get candidate names with availability checks and rationale.

**Why this priority**: Naming depends on having product context (ideally from research) and feeds into PRD creation. It's the second natural step.

**Independent Test**: Run `/project-naming` with product context and verify a naming report is created at `products/<slug>/naming.md` with ranked candidates.

**Acceptance Scenarios**:

1. **Given** a user provides product context (from PRD, research report, or description), **When** they run `/project-naming`, **Then** the skill generates 5-10 candidate names with rationale.
2. **Given** candidate names are generated, **When** the report is written, **Then** each name includes npm package availability, GitHub org/repo availability, and .com/.dev/.io domain likelihood.
3. **Given** the naming report exists, **When** the user says "more like X" or "avoid Y patterns", **Then** the skill refines the list iteratively.
4. **Given** a product slug already has a `products/<slug>/` directory, **When** the naming skill runs, **Then** the report is saved to `products/<slug>/naming.md`.

---

### User Story 3 - Create a Structured PRD (Priority: P1)

A developer wants to turn their validated idea into a buildable PRD set. They run `/create-prd` and answer clarifying questions to produce PRD.md, PRD-MVP.md, and PRD-Phases.md that kiln's `/build-prd` can execute against.

**Why this priority**: PRD creation is the core deliverable of clay — the artifact that bridges ideation and building. Tied with research as P1 because it's the most complex skill.

**Independent Test**: Run `/create-prd` with a product idea, answer clarifying questions, and verify all three PRD files are created under `products/<slug>/` and pass kiln's `/build-prd` validation.

**Acceptance Scenarios**:

1. **Given** a user invokes `/create-prd`, **When** the skill starts, **Then** it asks clarifying questions one at a time with multiple-choice options where inferable.
2. **Given** Mode A (new product PRD), **When** the user answers all questions, **Then** the skill generates PRD.md, PRD-MVP.md, and PRD-Phases.md under `products/<slug>/`.
3. **Given** Mode B (feature addition to existing product), **When** the user specifies an existing product, **Then** the PRD is generated in the context of the existing product's docs/features/ directory.
4. **Given** Mode C (PRD-only repo with products/ directory), **When** the user wants a PRD workspace, **Then** the skill creates the directory structure without repo scaffolding.
5. **Given** `products/<slug>/research.md` or `naming.md` exist, **When** the PRD is generated, **Then** their findings are incorporated automatically (market context, chosen name).
6. **Given** the PRD is complete, **When** it is reviewed, **Then** the tech stack is always defined (never left undefined) and an "Absolute Musts" section is present.

---

### User Story 4 - Turn a PRD into a GitHub Repo (Priority: P2)

A developer has a finished PRD and wants to create a GitHub repository scaffolded with kiln infrastructure, ready for `/build-prd`. They run `/create-repo` and get a live repo with the PRD seeded.

**Why this priority**: Repo creation is the final step of the pipeline. It depends on a PRD existing but delivers the handoff to kiln.

**Independent Test**: Run `/create-repo` pointing at a finished PRD and verify a GitHub repo is created with kiln infrastructure and PRD files in `docs/`.

**Acceptance Scenarios**:

1. **Given** a finished PRD exists at `products/<slug>/PRD.md`, **When** the user runs `/create-repo`, **Then** a GitHub repository is created with the specified name and visibility.
2. **Given** the repo is created, **When** scaffolding completes, **Then** kiln infrastructure (CLAUDE.md, templates, constitution) is installed.
3. **Given** the PRD artifacts exist in `products/<slug>/`, **When** the repo is scaffolded, **Then** PRD.md, PRD-MVP.md, and PRD-Phases.md are copied to `docs/` in the new repo.
4. **Given** the repo is live, **When** the skill finishes, **Then** kiln, wheel, and shelf plugins are installed and the user is told: "Run `/build-prd` in the new repo to start building."
5. **Given** the user specifies visibility and org, **When** the repo is created, **Then** those options are respected (public/private, custom org/user).

---

### User Story 5 - Track Ideas in Obsidian (Priority: P3)

A product thinker wants their ideas, research findings, and PRDs synced to their Obsidian vault so product thinking lives alongside their knowledge system.

**Why this priority**: Obsidian integration is valuable but depends on the core pipeline (research, naming, PRD, repo) working first. It's an enhancement layer.

**Independent Test**: Run the `clay-sync` wheel workflow and verify Obsidian notes are created/updated for products in `products/`.

**Acceptance Scenarios**:

1. **Given** products exist under `products/`, **When** the `clay-sync` wheel workflow runs, **Then** each product gets an Obsidian note with name, status, and artifact links.
2. **Given** a product has research findings, **When** the sync runs, **Then** research findings are synced as linked notes in Obsidian.
3. **Given** a product's PRD phase changes, **When** the sync runs, **Then** the Obsidian note status is updated (idea/researched/PRD-created/repo-created).

---

### User Story 6 - Manage Product Portfolio (Priority: P3)

A developer with multiple product ideas wants a quick overview of all their products and their statuses. They run `/clay-list` to see the portfolio.

**Why this priority**: Portfolio management is a convenience feature that depends on the products/ directory being populated by the core skills.

**Independent Test**: Create a few product directories with varying artifacts, run `/clay-list`, and verify all products are listed with correct statuses.

**Acceptance Scenarios**:

1. **Given** multiple products exist under `products/`, **When** the user runs `/clay-list`, **Then** all products are listed with their status (idea, researched, PRD-created, repo-created).
2. **Given** a product has only `research.md`, **When** listed, **Then** its status shows "researched".
3. **Given** a product has PRD.md, PRD-MVP.md, and PRD-Phases.md, **When** listed, **Then** its status shows "PRD-created".

---

### User Story 7 - Wheel Discovers Plugin Workflows (Priority: P2)

A user installs clay and wants to run clay's bundled wheel workflows (like `clay-sync`) without manually copying JSON files. Wheel discovers workflows from installed plugins automatically.

**Why this priority**: This is a prerequisite for Obsidian integration (US5) and enables any plugin to ship workflows, making it foundational infrastructure.

**Independent Test**: Install clay plugin, run `/wheel-list`, and verify `clay:clay-sync` appears. Run `/wheel-run clay:clay-sync` and verify it executes.

**Acceptance Scenarios**:

1. **Given** clay's `plugin.json` declares a `workflows` field listing workflow file paths, **When** wheel's engine reads installed plugins, **Then** it discovers and lists clay's workflows.
2. **Given** a plugin workflow is discovered, **When** the user runs `/wheel-run clay:clay-sync`, **Then** the workflow executes using the `<plugin>:<workflow-name>` syntax.
3. **Given** a user wants to customize a plugin workflow, **When** they copy it to `workflows/`, **Then** the local copy takes precedence over the plugin version.
4. **Given** plugin workflows are listed, **When** `/wheel-list` runs, **Then** they are clearly labeled as plugin-provided (read-only) vs project-local.

---

### Edge Cases

- What happens when `products/` doesn't exist? Skills should create it automatically.
- What happens when `gh` CLI isn't authenticated? `/create-repo` should detect and report the blocker before attempting creation.
- What happens when wheel or shelf plugins aren't installed? Clay skills that depend on them should gracefully degrade with a message: "Install wheel/shelf for Obsidian sync."
- What happens when a product slug collides with an existing directory? Skills should detect the collision and either reuse the existing directory or prompt the user.
- What happens when `/create-prd` is run without answering clarifying questions? The skill should not generate PRD files — it waits or uses TBD placeholders only with explicit user approval.
- What happens when a plugin workflow JSON is malformed? Wheel should reject it at load time with a clear validation error.

## Requirements

### Functional Requirements

#### Plugin Infrastructure
- **FR-001**: Create `plugin-clay/` directory structure mirroring kiln/wheel/shelf conventions: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `skills/`, `package.json`
- **FR-002**: Plugin manifest declares dependency on `wheel` and `shelf` plugins
- **FR-003**: Plugin registers all clay skills as `/clay:<skill-name>` commands (idea-research, project-naming, create-prd, create-repo, clay-list)

#### Idea Research Skill (`/idea-research`)
- **FR-004**: Accept a 1-5 sentence idea description as input
- **FR-005**: Search the web for similar products, startups, and open source projects
- **FR-006**: Classify findings into categories: `EXACT MATCH`, `CLOSE COMPETITOR`, `ADJACENT`, `SLIGHTLY SIMILAR`
- **FR-007**: Output a structured research report to `products/<slug>/research.md` (or derive slug from idea if no product slug yet)
- **FR-008**: Report includes: product name, URL, description, similarity classification, key differentiators, pricing model (if available)
- **FR-009**: Summarize findings with a go/no-go recommendation based on market density

#### Project Naming Skill (`/project-naming`)
- **FR-010**: Accept product context (from PRD, research report, or user description)
- **FR-011**: Generate 5-10 candidate names with rationale for each
- **FR-012**: For each name, check: npm package availability, GitHub org/repo availability, .com/.dev/.io domain likelihood
- **FR-013**: Output a naming report to `products/<slug>/naming.md` with ranked recommendations
- **FR-014**: Support iterative refinement — user can say "more like X" or "avoid Y patterns"

#### PRD Creation Skill (`/create-prd`)
- **FR-015**: Merge functionality from kiln's current `/create-prd` and the `founder-prd` skill from yoshisada/skills
- **FR-016**: Support three modes: Mode A (new product PRD), Mode B (feature addition to existing product), Mode C (PRD-only repo with `products/` directory)
- **FR-017**: Ask clarifying questions one at a time with multiple-choice options where inferable
- **FR-018**: Generate 3-file PRD set: `PRD.md`, `PRD-MVP.md`, `PRD-Phases.md`
- **FR-019**: Store PRDs under `products/<product-slug>/` by default
- **FR-020**: If research.md or naming.md exist for the product, incorporate their findings into the PRD automatically
- **FR-021**: Enforce tech stack definition — never leave it undefined

#### Repo Creation Skill (`/create-repo`)
- **FR-022**: Create a GitHub repository from a finished PRD (replaces kiln's `/create-repo`)
- **FR-023**: Scaffold the new repo with kiln infrastructure (CLAUDE.md, templates, constitution, project structure)
- **FR-024**: Seed the PRD artifacts from `products/<slug>/` into the new repo's `docs/` directory
- **FR-025**: Support visibility options (public/private) and custom GitHub org/user
- **FR-026**: Install kiln, wheel, and shelf plugins in the new repo
- **FR-027**: After creation, suggest next step: "Run `/build-prd` in the new repo to start building"

#### Wheel Workflow Manifest Enhancement
- **FR-028**: Extend wheel's `plugin.json` schema to support a `workflows` field — an array of workflow file paths relative to the plugin root
- **FR-029**: Wheel's engine and `/wheel-list` must discover workflows from all installed plugins by reading each plugin's `plugin.json` manifest, in addition to the project-level `workflows/` directory
- **FR-030**: Plugin-provided workflows are read-only from the consumer's perspective — they execute but cannot be edited in-place. Users can copy them to `workflows/` to customize.
- **FR-031**: `/wheel-run` accepts both project workflows (by name) and plugin workflows (by `<plugin>:<workflow-name>` syntax, e.g., `clay:clay-sync`)

#### Obsidian Integration (via wheel + shelf)
- **FR-032**: Ship a wheel workflow (`plugin-clay/workflows/clay-sync.json`) declared in clay's `plugin.json` manifest
- **FR-033**: Each product in `products/` gets an Obsidian note with: name, status (idea/researched/PRD-created/repo-created), links to artifacts
- **FR-034**: Research findings sync as linked notes in Obsidian
- **FR-035**: PRD phase transitions update the Obsidian note status

#### Product Portfolio Management
- **FR-036**: Provide a `/clay-list` skill that shows all products under `products/` with their status (idea, researched, PRD-created, repo-created)
- **FR-037**: Each product directory follows the structure: `products/<slug>/research.md`, `products/<slug>/naming.md`, `products/<slug>/PRD.md`, `products/<slug>/PRD-MVP.md`, `products/<slug>/PRD-Phases.md`

### Key Entities

- **Product**: A product idea tracked under `products/<slug>/`. Status derived from which artifacts exist (idea=directory only, researched=research.md, named=naming.md, PRD-created=PRD.md+PRD-MVP.md+PRD-Phases.md, repo-created=has associated GitHub repo).
- **Research Report**: Structured market analysis at `products/<slug>/research.md` with classified findings.
- **Naming Report**: Candidate name analysis at `products/<slug>/naming.md` with availability data.
- **PRD Set**: Three-file artifact (PRD.md, PRD-MVP.md, PRD-Phases.md) that kiln's `/build-prd` can consume.
- **Plugin Workflow**: A wheel workflow JSON file shipped inside a plugin and discoverable via the plugin manifest.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Full pipeline (`/idea-research` -> `/project-naming` -> `/create-prd` -> `/create-repo`) completes in a single session without errors
- **SC-002**: Generated PRDs pass kiln's `/build-prd` without manual edits
- **SC-003**: Products are tracked in Obsidian via `clay-sync` wheel workflow
- **SC-004**: All 5 clay skills work standalone (any can be run independently without the others)
- **SC-005**: `/wheel-list` discovers and displays plugin-provided workflows
- **SC-006**: `/wheel-run clay:clay-sync` executes successfully
- **SC-007**: `/clay-list` correctly reports product statuses derived from artifact presence

## Assumptions

- Users have `gh` CLI installed and authenticated (for `/create-repo`)
- Users have the wheel and shelf plugins installed (for Obsidian sync — graceful degradation if missing)
- The `products/` directory pattern is acceptable for multi-product management at repo root
- Kiln's `/build-prd` accepts PRDs from any `docs/` location (not hardcoded)
- Kiln's existing `/create-prd` and `/create-repo` remain functional — clay provides alternatives, not replacements that break kiln
- Web search capabilities are available for `/idea-research` (via WebSearch tool)
- Plugin directory structure follows existing conventions from kiln/wheel/shelf
