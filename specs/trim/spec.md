# Feature Specification: Trim — Bidirectional Design-Code Sync Plugin

**Feature Branch**: `build/trim-20260409`
**Created**: 2026-04-09
**Status**: Draft
**Input**: User description: "Trim — bidirectional design-code sync plugin via Penpot MCP. 6 skills (pull, push, diff, library, design, config), wheel workflows for all multi-step ops, component mapping via .trim-components.json, framework-agnostic code generation."

## User Scenarios & Testing

### User Story 1 - Pull Design into Code (Priority: P1)

A solo developer has created a page layout or component in Penpot. They want to generate working code that matches the design without manually translating visual properties. They run `/trim-pull` and the plugin reads the Penpot design via MCP, detects their project's UI framework, and generates framework-appropriate code files with correct layout, spacing, colors, and typography.

**Why this priority**: This is the primary value proposition — turning designs into code. Without this, the plugin has no core utility.

**Independent Test**: Can be tested by creating a simple Penpot component (e.g., a card with heading, image, and button), running `/trim-pull`, and verifying that generated code renders a matching layout in the detected framework.

**Acceptance Scenarios**:

1. **Given** a Penpot project with a page containing a header component, **When** the developer runs `/trim-pull`, **Then** the plugin generates framework-appropriate code files that represent the header's layout, colors, typography, and spacing.
2. **Given** a project using React with Tailwind CSS, **When** `/trim-pull` runs, **Then** generated code uses React JSX with Tailwind utility classes (not inline styles or a different framework).
3. **Given** a Penpot design that uses a component already tracked in `.trim-components.json`, **When** `/trim-pull` runs, **Then** the generated code imports and reuses the existing component instead of recreating it.
4. **Given** a Penpot design with nested component instances, **When** `/trim-pull` runs, **Then** the generated code preserves the component hierarchy with proper parent-child relationships.

---

### User Story 2 - Push Code to Penpot (Priority: P2)

A solo developer has existing UI code and wants to visualize or edit it in Penpot. They run `/trim-push` and the plugin analyzes their code components, extracts structure and styles, and creates corresponding Penpot components via MCP. This enables visual editing of code-first components.

**Why this priority**: Enables the code-first workflow, which is the second major use case. Many developers start with code and want to add visual design tooling later.

**Independent Test**: Can be tested by having a simple React/Vue/HTML component in the codebase, running `/trim-push`, and verifying that a matching Penpot component appears with correct structure and visual properties.

**Acceptance Scenarios**:

1. **Given** a codebase with a Button component at `src/components/Button.tsx`, **When** the developer runs `/trim-push`, **Then** the plugin creates a Penpot component that visually represents the Button with correct colors, typography, and sizing.
2. **Given** a push operation completes successfully, **When** the developer checks `.trim-components.json`, **Then** new entries exist mapping each pushed code component to its Penpot component ID with a `last_synced` timestamp.
3. **Given** a component that already exists in Penpot (tracked in `.trim-components.json`), **When** `/trim-push` runs, **Then** the existing Penpot component is updated rather than a duplicate being created.

---

### User Story 3 - Detect Drift Between Design and Code (Priority: P2)

A solo developer wants to know if their Penpot designs and code have diverged. They run `/trim-diff` and receive a categorized drift report showing exactly what is out of sync, with actionable suggestions for each mismatch.

**Why this priority**: Drift detection is essential for maintaining sync integrity. Without it, the developer has no way to know when things are out of sync.

**Independent Test**: Can be tested by pulling a design, manually changing the code (e.g., altering a color), running `/trim-diff`, and verifying the report identifies the color change as a style divergence.

**Acceptance Scenarios**:

1. **Given** a component exists in both code and Penpot with matching properties, **When** the developer runs `/trim-diff`, **Then** the drift report shows no mismatches for that component.
2. **Given** a component exists in code but has no Penpot counterpart, **When** `/trim-diff` runs, **Then** the report categorizes it as "code-only" and suggests pushing it to Penpot.
3. **Given** a component's color in Penpot differs from code, **When** `/trim-diff` runs, **Then** the report lists the specific style divergence with both values and suggests whether to pull or push.

---

### User Story 4 - Manage Component Library (Priority: P3)

A solo developer wants an overview of all tracked components and their sync status. They run `/trim-library` to see which components are in sync, which have drifted, and which are unlinked. They can run `/trim-library sync` to auto-sync drifted components based on which side was modified more recently.

**Why this priority**: Library management builds on top of pull/push/diff to provide a holistic view. It's a convenience feature that becomes valuable once the core sync operations are established.

**Independent Test**: Can be tested by setting up several tracked components in `.trim-components.json` (some synced, some drifted), running `/trim-library`, and verifying the status report is accurate.

**Acceptance Scenarios**:

1. **Given** three components tracked in `.trim-components.json` (one in sync, one drifted, one unlinked), **When** the developer runs `/trim-library`, **Then** the output shows each component's name, sync status, and last sync timestamp.
2. **Given** a component where the code was modified after the last sync (newer git commit than `last_synced`), **When** `/trim-library sync` runs, **Then** the component is pushed to Penpot (code wins).
3. **Given** a component where the Penpot design was modified after the last sync, **When** `/trim-library sync` runs, **Then** the component is pulled from Penpot to code (design wins).

---

### User Story 5 - Generate Design from Product Context (Priority: P3)

A solo developer has a PRD or product idea but no visual design yet. They run `/trim-design` with their product context and the plugin generates an initial Penpot design that reuses existing components, follows project visual conventions, and reflects the PRD requirements.

**Why this priority**: This is a higher-level creative feature that depends on the component library being populated. It provides significant value but is not required for core sync functionality.

**Independent Test**: Can be tested by providing a simple PRD (e.g., "login page with email, password, and submit button"), running `/trim-design`, and verifying a Penpot page is created with appropriate components.

**Acceptance Scenarios**:

1. **Given** a PRD describing a settings page with a form and save button, **When** the developer runs `/trim-design`, **Then** a Penpot page is created containing a form layout with input fields and a save button.
2. **Given** an existing component library with a Button and Input component in Penpot, **When** `/trim-design` runs for a page that needs buttons and inputs, **Then** the generated design reuses the existing library components.
3. **Given** existing code with a blue primary color and Inter font, **When** `/trim-design` runs, **Then** the generated design uses the same blue primary color and Inter font.

---

### User Story 6 - Configure Trim (Priority: P1)

A solo developer installs the trim plugin and needs to connect it to their Penpot project. They run `/trim-config` to set up the Penpot project ID, file ID, default page, and component mapping file path. The configuration is stored in `.trim-config` at the repo root.

**Why this priority**: Configuration is a prerequisite for all other operations. Without it, no Penpot connection can be established.

**Independent Test**: Can be tested by running `/trim-config` in a fresh project, providing Penpot project details, and verifying `.trim-config` is created with the correct values.

**Acceptance Scenarios**:

1. **Given** a project without a `.trim-config` file, **When** the developer runs `/trim-config`, **Then** the plugin prompts for Penpot project ID and file ID and writes a valid `.trim-config` file.
2. **Given** an existing `.trim-config` file, **When** the developer runs `/trim-config`, **Then** the plugin displays current settings and allows updating individual values.
3. **Given** a valid `.trim-config` file, **When** any trim skill runs, **Then** it reads connection details from `.trim-config` without re-prompting.

---

### Edge Cases

- What happens when Penpot MCP is unavailable or not installed? The plugin should detect this and provide a clear error message with setup instructions.
- What happens when `.trim-config` is missing when running a sync command? The plugin should prompt the user to run `/trim-config` first.
- What happens when a Penpot component referenced in `.trim-components.json` has been deleted in Penpot? The drift report should flag it as "design-deleted" and suggest removing the mapping or recreating the component.
- What happens when the project's UI framework cannot be detected? The plugin should fall back to plain HTML/CSS and inform the developer.
- What happens when a Penpot design has deeply nested layers that don't map cleanly to components? The plugin should flatten to a reasonable depth and document the mapping decisions.
- What happens when two code components map to the same Penpot component? The plugin should detect the conflict and warn the developer to resolve the duplicate mapping.

## Requirements

### Functional Requirements

#### Core Infrastructure

- **FR-001**: Plugin MUST be structured as `plugin-trim/` following the established plugin pattern: `.claude-plugin/plugin.json`, `skills/`, `workflows/`, `templates/`, `package.json`.
- **FR-002**: Plugin MUST provide a `.trim-config` file at the repo root that stores: Penpot project ID, file ID, default page, and component mapping file path. Format is plain-text key-value (same pattern as `.shelf-config`).
- **FR-003**: Plugin MUST provide a `.trim-components.json` file that tracks bidirectional links between code components and Penpot components. Each entry contains: `code_path`, `penpot_component_id`, `penpot_component_name`, and `last_synced` (ISO 8601 timestamp).
- **FR-004**: All multi-step operations (pull, push, diff, design) MUST be wheel workflows following the command-first/agent-second pattern. Command steps gather data; agent steps interact with Penpot MCP.
- **FR-005**: The spec directory MUST be `specs/trim/` with no numeric prefixes or other naming scheme.
- **FR-006**: All workflows MUST resolve the trim plugin install path at runtime by scanning `installed_plugins.json`, falling back to `plugin-trim/`.
- **FR-007**: Workflows MUST write step outputs to `.wheel/outputs/` for observability and context passing between steps.

#### Design-First: Penpot to Code (Pull)

- **FR-008**: `/trim-pull` skill MUST delegate to a `trim-pull` wheel workflow that reads the Penpot design via MCP and extracts the component tree, layout, and styles.
- **FR-009**: The trim-pull workflow MUST detect the project's UI framework (React, Vue, Svelte, plain HTML) and code conventions (CSS modules, Tailwind, styled-components) before generating code.
- **FR-010**: Generated code MUST match the Penpot design's layout, spacing, colors, typography, and component hierarchy.
- **FR-011**: Generated code MUST reuse existing components from `.trim-components.json` when a matching component exists, instead of recreating from scratch.
- **FR-012**: After generation, `.trim-components.json` MUST be updated with new mappings for any newly created components.

#### Code-First: Code to Penpot (Push)

- **FR-013**: `/trim-push` skill MUST delegate to a `trim-push` wheel workflow that analyzes code components, extracts structure and styles, and creates or updates Penpot components via MCP.
- **FR-014**: The trim-push workflow MUST scan the codebase for UI components by framework convention and extract their visual properties.
- **FR-015**: Penpot components created by push MUST be structured and editable (not screenshots) with correct layout, colors, typography, and spacing.
- **FR-016**: After pushing, `.trim-components.json` MUST be updated with mappings between code and newly created Penpot components.

#### Drift Detection

- **FR-017**: `/trim-diff` skill MUST delegate to a `trim-diff` wheel workflow that compares Penpot design state against code state.
- **FR-018**: The drift report MUST categorize mismatches as: code-only, design-only, style-divergence, or layout-difference.
- **FR-019**: The drift report MUST be actionable with a suggestion for each mismatch (pull, push, or manual review).

#### Component Library

- **FR-020**: `/trim-library` skill MUST list all tracked components with their sync status and last sync timestamp.
- **FR-021**: `/trim-library sync` MUST sync drifted components with direction determined by which side was modified more recently (git history for code, Penpot modification timestamp for design).

#### Design Generation

- **FR-022**: `/trim-design` skill MUST read product context (PRD, existing components, project conventions) and generate an initial Penpot design via MCP.
- **FR-023**: Design generation MUST reuse existing component library components where appropriate.
- **FR-024**: Generated designs MUST follow the project's established visual conventions (colors, typography, spacing) if detectable from existing code or Penpot components.

#### Configuration

- **FR-025**: `/trim-config` skill MUST create or update `.trim-config` with Penpot connection details.
- **FR-026**: All trim skills MUST read `.trim-config` before executing and fail with a clear message if it is missing or incomplete.

### Key Entities

- **Trim Config** (`.trim-config`): Plain-text key-value file mapping the local project to a Penpot project/file. Keys: `penpot_project_id`, `penpot_file_id`, `default_page`, `components_file`.
- **Component Mapping** (`.trim-components.json`): JSON array of component link records. Each record associates a code file path with a Penpot component ID and tracks sync state.
- **Drift Report**: A structured output from `/trim-diff` categorizing mismatches between Penpot and code with actionable suggestions.
- **Wheel Workflow**: JSON file defining a multi-step operation with command and agent steps, following the established wheel engine pattern.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A single Penpot component can be pulled into working, framework-appropriate code in under 5 minutes.
- **SC-002**: A round-trip sync (code to Penpot to edited Penpot back to code) preserves application logic and only updates visual properties.
- **SC-003**: Drift detection catches structural visual mismatches (missing components, color changes, layout shifts) with greater than 90% accuracy.
- **SC-004**: Component library status report accurately reflects the sync state of all tracked components.
- **SC-005**: All 6 skills are discoverable and runnable as `/trim-*` commands in Claude Code.
- **SC-006**: Plugin installs with zero additional runtime dependencies beyond Claude Code and the Penpot MCP.

## Assumptions

- Developer has the Penpot MCP server installed and running in their Claude Code environment.
- Developer has an existing Penpot project with at least one file/page created.
- The project has a detectable UI framework (or the developer is comfortable with plain HTML/CSS fallback).
- The wheel engine (`plugin-wheel/`) is installed and operational in the developer's environment.
- Penpot MCP provides tools for reading component trees, creating components, updating styles, and reading/writing layout properties.
- The `.trim-components.json` file is committed to version control alongside the codebase.
