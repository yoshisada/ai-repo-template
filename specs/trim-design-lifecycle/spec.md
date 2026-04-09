# Feature Specification: Trim Design Lifecycle

**Feature Branch**: `build/trim-design-lifecycle-20260409`  
**Created**: 2026-04-09  
**Status**: Draft  
**Input**: User description: "Trim design lifecycle — add /trim-edit (natural language Penpot edits with changelog), /trim-verify (visual verification via Playwright/chrome screenshots vs Penpot), /trim-redesign (full UI overhaul), /trim-flows (user flow tracking for verification and QA test generation). Extends plugin-trim/ with 4 new skills, 4 new wheel workflows, .trim-changes.md changelog, .trim-flows.json schema."

## User Scenarios & Testing

### User Story 1 - Natural Language Design Editing (Priority: P1)

A solo developer wants to make targeted changes to their Penpot design without opening the Penpot editor. They run `/trim-edit "make the sidebar narrower and change the accent color to blue"` and the design is updated in Penpot via MCP. The change is recorded in a changelog with what was requested, what actually changed, and which frames were affected. The code is NOT modified — the developer decides when to pull.

**Why this priority**: This is the most frequent interaction — quick design tweaks during development. It unblocks the edit-verify-pull cycle that all other stories depend on.

**Independent Test**: Can be fully tested by running `/trim-edit` with a description, then verifying the Penpot design changed and `.trim-changes.md` has a new entry.

**Acceptance Scenarios**:

1. **Given** a project with Penpot MCP configured and `.trim-components.json` present, **When** the developer runs `/trim-edit "make the header background darker"`, **Then** the Penpot design is updated with the requested change and `.trim-changes.md` has a new entry with timestamp, request description, actual changes, and affected frames.
2. **Given** a completed edit, **When** the developer checks the codebase, **Then** no source files have been modified — changes exist only in Penpot.
3. **Given** a project without Penpot MCP configured, **When** the developer runs `/trim-edit`, **Then** the system reports that Penpot MCP is required and stops.

---

### User Story 2 - User Flow Management (Priority: P2)

A developer wants to define and track all user flows in their application so that visual verification and QA test generation have a structured source of truth. They run `/trim-flows add "checkout"` to define a new flow with ordered steps, or `/trim-flows list` to see all tracked flows. Each flow maps steps to pages, components, and Penpot frames.

**Why this priority**: Flows are the foundation for verification (Story 3) and QA integration. Without tracked flows, verification has nothing to walk and QA has no test stubs to generate.

**Independent Test**: Can be tested by adding a flow, listing flows, and verifying `.trim-flows.json` contains the correct structure.

**Acceptance Scenarios**:

1. **Given** no existing `.trim-flows.json`, **When** the developer runs `/trim-flows add "login"` and describes the steps, **Then** `.trim-flows.json` is created with the flow containing name, description, ordered steps (each with action, target, page, component, penpot_frame_id), and a null last_verified timestamp.
2. **Given** existing flows in `.trim-flows.json`, **When** the developer runs `/trim-flows list`, **Then** all flows are displayed with their step count and last verification date.
3. **Given** flows with missing Penpot frame IDs, **When** the developer runs `/trim-flows sync`, **Then** the system maps flow steps to Penpot frames and code routes/components.
4. **Given** tracked flows, **When** the developer runs `/trim-flows export-tests`, **Then** Playwright test stubs are generated with one test per flow and one step per assertion.

---

### User Story 3 - Visual Verification (Priority: P3)

After pulling design changes to code, the developer wants to verify that the rendered code actually matches the Penpot design. They run `/trim-verify` which walks each tracked user flow in a headless browser, screenshots each step, fetches the corresponding Penpot frames, and uses Claude vision to compare them semantically. A report is generated identifying mismatches.

**Why this priority**: Verification is the quality gate — it catches visual drift between design and code. It depends on flows (Story 2) being defined first.

**Independent Test**: Can be tested by defining at least one flow, running `/trim-verify`, and checking that `.trim-verify-report.md` is generated with per-step pass/fail results.

**Acceptance Scenarios**:

1. **Given** a project with tracked flows and a running dev server, **When** the developer runs `/trim-verify`, **Then** the system walks each flow step in a headless browser, screenshots each step, fetches the Penpot frame, compares them via Claude vision, and outputs `.trim-verify-report.md`.
2. **Given** a visual mismatch between code and Penpot, **When** verification runs, **Then** the report identifies the specific differences: layout shifts, color differences, missing elements, typography mismatches, or spacing issues.
3. **Given** screenshots captured during verification, **When** checking the filesystem, **Then** all screenshot artifacts are stored in `.trim-verify/` (gitignored) and not committed.
4. **Given** no tracked flows in `.trim-flows.json`, **When** the developer runs `/trim-verify`, **Then** the system reports that no flows are defined and suggests running `/trim-flows add`.

---

### User Story 4 - Full UI Redesign (Priority: P4)

A developer wants to completely rethink the visual design of their application while preserving the information architecture. They run `/trim-redesign "modernize the dashboard with a dark theme"` and the system reads the PRD, existing components, current design, and user flows, then generates a complete new Penpot design. All changes are logged with rationale.

**Why this priority**: Redesign is the least frequent operation — it's a major undertaking used occasionally, not daily. It builds on all other capabilities (components, flows, changelog).

**Independent Test**: Can be tested by running `/trim-redesign` with context, then verifying the Penpot design was updated and `.trim-changes.md` has a comprehensive redesign entry.

**Acceptance Scenarios**:

1. **Given** a project with existing Penpot design, components, and user flows, **When** the developer runs `/trim-redesign "switch to dark theme"`, **Then** the Penpot design is reimagined with the requested direction while preserving page structure, navigation, and user flows.
2. **Given** a completed redesign, **When** checking `.trim-changes.md`, **Then** a comprehensive entry documents what was redesigned and the rationale for each change.
3. **Given** a completed redesign, **When** checking the codebase, **Then** no source files have been modified — the developer reviews in Penpot and pulls when ready.

---

### User Story 5 - QA Integration via Flows (Priority: P5)

The kiln QA engineer needs to generate Playwright E2E test stubs without manually discovering user flows. The QA system reads `.trim-flows.json` and generates one test per flow with pre-defined steps. This eliminates manual flow discovery from the QA process.

**Why this priority**: This is a downstream consumer of flow data (Story 2) — it provides value to the QA pipeline but doesn't introduce new user-facing functionality.

**Independent Test**: Can be tested by having `.trim-flows.json` with flows, running `/trim-flows export-tests`, and verifying generated Playwright test stubs match the flow definitions.

**Acceptance Scenarios**:

1. **Given** `.trim-flows.json` with defined flows, **When** the QA engineer or developer runs `/trim-flows export-tests`, **Then** Playwright test files are generated with one test per flow where each flow step becomes an assertion.
2. **Given** a flow step with action "click", target "submit-button", and page "/checkout", **When** test stubs are generated, **Then** the test navigates to "/checkout" and includes a click action on the target element.

### Edge Cases

- What happens when Penpot MCP is unavailable mid-workflow? The workflow reports the error and stops cleanly without partial changes.
- What happens when `.trim-flows.json` has flows with stale Penpot frame IDs (deleted frames)? The verification reports the stale reference and skips that step.
- What happens when the dev server is not running during `/trim-verify`? The workflow detects the unreachable URL and reports it before attempting screenshots.
- What happens when `.trim-changes.md` does not exist before the first edit? It is created automatically with a header.
- What happens when a redesign is run on a project with no existing design? The workflow creates a new design from scratch using PRD context and component library.

## Requirements

### Functional Requirements

#### Design Editing

- **FR-001**: `/trim-edit <description>` skill MUST accept a natural language description and delegate to a `trim-edit` wheel workflow that modifies the Penpot design via MCP.
- **FR-002**: The trim-edit workflow MUST read current Penpot design state and `.trim-components.json` before making changes, so edits are context-aware.
- **FR-003**: The workflow MUST apply targeted changes to the Penpot design — not regenerate the entire design.
- **FR-004**: After editing, the workflow MUST NOT sync changes to code. Changes stay in Penpot only.
- **FR-005**: After editing, the workflow MUST append an entry to `.trim-changes.md` with: timestamp, description of what was requested, what was actually changed (components/properties modified), and which Penpot frames were affected.
- **FR-006**: `.trim-changes.md` serves as the design decision changelog. Each entry MUST include enough context to understand why the change was made without looking at a diff.

#### Visual Verification

- **FR-007**: `/trim-verify` skill MUST visually compare rendered code against Penpot designs by delegating to a `trim-verify` wheel workflow.
- **FR-008**: The trim-verify workflow MUST render code in a browser using Playwright (headless) by default, or /chrome MCP when specified or when Playwright is unavailable.
- **FR-009**: For each tracked user flow in `.trim-flows.json`, the workflow MUST navigate through flow steps, screenshot each step, and fetch the corresponding Penpot frame.
- **FR-010**: The workflow MUST compare each screenshot against its Penpot counterpart using Claude vision (screenshot analysis) and report semantic visual differences: layout shifts, color differences, missing/extra elements, typography mismatches, spacing issues.
- **FR-011**: Output a verification report to `.trim-verify-report.md` with: flow name, step, pass/fail, description of mismatch, screenshot paths, and Penpot frame reference.
- **FR-012**: Screenshots and artifacts MUST be stored in `.trim-verify/` (gitignored), not committed.

#### Full Redesign

- **FR-013**: `/trim-redesign [context]` skill MUST generate a complete new Penpot design by delegating to a `trim-redesign` wheel workflow.
- **FR-014**: The redesign workflow MUST read: PRD, existing `.trim-components.json`, current Penpot design, `.trim-flows.json`, and optional user context.
- **FR-015**: The redesign MUST preserve information architecture (pages, navigation, user flows) while reimagining visual design (layout, colors, typography, component styling).
- **FR-016**: All redesign changes MUST be logged to `.trim-changes.md` with a summary and rationale.
- **FR-017**: After redesign, the workflow MUST NOT auto-sync to code.

#### User Flow Management

- **FR-018**: `/trim-flows` skill MUST manage user flows in `.trim-flows.json`.
- **FR-019**: `.trim-flows.json` schema: array of flows, each with `name`, `description`, `steps` (ordered array of `{ action, target, page, component, penpot_frame_id }`), and `last_verified` timestamp.
- **FR-020**: `/trim-flows add <name>` MUST add a new flow by asking the developer to describe steps, then mapping each step to a page/component and Penpot frame.
- **FR-021**: `/trim-flows list` MUST display all flows with step count and last verification date.
- **FR-022**: `/trim-flows sync` MUST map flow steps to Penpot frames and code routes/components for flows missing those mappings.
- **FR-023**: `/trim-flows export-tests` MUST generate Playwright test stubs from `.trim-flows.json` — one test per flow, one step per assertion.
- **FR-024**: `.trim-flows.json` MUST be readable by kiln's QA engineer for E2E test stub generation, with enough detail (action, target, expected page/route) per step.

#### Wheel Workflow Pattern

- **FR-025**: All multi-step operations (edit, verify, redesign) MUST be wheel workflows following the command-first/agent-second pattern.
- **FR-026**: All workflows MUST resolve the trim plugin install path at runtime (scan `installed_plugins.json`, fall back to `plugin-trim/`).
- **FR-027**: Workflows MUST write step outputs to `.wheel/outputs/` for observability.

### Key Entities

- **Design Change Entry**: A record in `.trim-changes.md` — timestamp, request description, actual changes, affected Penpot frames, rationale.
- **User Flow**: A named sequence of steps in `.trim-flows.json` — name, description, ordered steps, last verification timestamp.
- **Flow Step**: An individual interaction within a flow — action (click, navigate, fill), target (selector or component), page/route, component name, Penpot frame ID.
- **Verification Report**: Per-step comparison results — flow name, step index, pass/fail, mismatch description, screenshot path, Penpot frame reference.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A natural language edit request results in a visible Penpot design change and a changelog entry within a single workflow run.
- **SC-002**: Visual verification catches more than 80% of rendering mismatches between Penpot design and live code (layout, color, typography, spacing).
- **SC-003**: The edit-verify cycle (edit a single component, then verify) completes in under 3 minutes.
- **SC-004**: All defined user flows can be walked and verified automatically without manual intervention.
- **SC-005**: The QA engineer can generate Playwright test stubs from `.trim-flows.json` without needing to discover user flows manually.
- **SC-006**: The design changelog (`.trim-changes.md`) provides enough context per entry that a developer can understand design decisions without viewing the Penpot diff.

## Assumptions

- The Penpot MCP is installed and configured in the developer's Claude Code environment, providing tools for reading and modifying Penpot designs.
- The parent trim plugin (`plugin-trim/`) will be created by a prior pipeline and provides the base infrastructure (pull, push, diff, library, design skills).
- Playwright is available in the developer's environment for headless browser screenshots, or /chrome MCP is available as a fallback.
- The project has a dev server that can be started for visual verification (the developer starts it before running `/trim-verify`).
- `.trim-components.json` exists from the parent trim plugin's component library management.
- This is a plugin source repo — deliverables are markdown skill files and JSON workflow files in `plugin-trim/`, not application code.
