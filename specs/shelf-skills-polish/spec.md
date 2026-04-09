# Feature Specification: Shelf Skills Polish

**Feature Branch**: `build/shelf-skills-polish-20260408`  
**Created**: 2026-04-08  
**Status**: Draft  
**Input**: User description: "Shelf skills polish — rewrite shelf-create as wheel workflow, add shelf-repair workflow, canonical status labels, vault root navigation, holistic progress detection, shelf-full-sync summary step"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deterministic Project Scaffolding via Workflow (Priority: P1)

As a developer onboarding a new project to shelf, I want `shelf-create` to run as a wheel workflow so that each step (data gathering, vault navigation, MCP operations) executes deterministically with observable outputs, resumability on failure, and no path guessing.

**Why this priority**: This is the foundation — every other improvement (repair, status labels, progress detection) depends on shelf-create being a reliable, structured workflow rather than a monolithic skill.

**Independent Test**: Run `/shelf-create` on a repo with `.shelf-config` and verify the workflow produces the correct Obsidian project structure by checking `.wheel/outputs/` for each step's output and the vault for created notes.

**Acceptance Scenarios**:

1. **Given** a repo with `.shelf-config` containing `base_path` and `slug`, **When** the user runs `/shelf-create`, **Then** the wheel workflow executes command steps to gather repo state before any MCP calls are made.
2. **Given** a repo with no existing Obsidian project, **When** `/shelf-create` runs, **Then** the workflow navigates from vault root using `list_files({ directory: "/" })` to find or create the base_path, never guessing paths.
3. **Given** a repo with an existing Obsidian project at the target path, **When** `/shelf-create` runs, **Then** the workflow detects the duplicate and aborts with a clear message.
4. **Given** a workflow step fails mid-execution, **When** the user checks `.wheel/` state, **Then** the state file shows exactly which step failed, enabling resume.

---

### User Story 2 - Holistic Progress Detection on Create (Priority: P1)

As a developer onboarding an existing, partially-developed project to shelf, I want the initial dashboard to reflect the project's actual state (code exists, specs written, tests present) so I don't have to manually fill in status and milestones after creation.

**Why this priority**: Without this, every project starts as "idea" regardless of actual progress, making the dashboard immediately inaccurate and eroding trust.

**Independent Test**: Run `/shelf-create` on a repo with existing `src/`, `specs/`, test files, and a VERSION file, then verify the dashboard shows an appropriate status (e.g., `active`) and a progress entry summarizing detected signals.

**Acceptance Scenarios**:

1. **Given** a repo with `src/` directory, 50+ git commits, and a VERSION file, **When** `/shelf-create` runs, **Then** the dashboard status is set to `active` (not `idea`) and the initial progress entry lists detected signals.
2. **Given** a repo with only a PRD and no code, **When** `/shelf-create` runs, **Then** the dashboard status is set to `idea` and the progress entry notes "PRDs found, no implementation yet."
3. **Given** a repo with specs, code, and tests, **When** `/shelf-create` runs, **Then** the progress entry includes counts for spec files, code directories, test files, commit count, and open issues.

---

### User Story 3 - Canonical Status Labels Across All Skills (Priority: P2)

As a developer using shelf across multiple projects, I want all shelf skills to use the same set of status labels so I can filter and compare projects reliably in Obsidian without encountering inconsistencies like "in-progress" vs "active" vs "in progress."

**Why this priority**: Inconsistent labels break Obsidian queries and Dataview filters, causing real friction for multi-project tracking. This is a cross-cutting concern that affects every shelf skill.

**Independent Test**: Inspect `plugin-shelf/status-labels.md` for the canonical list, then verify each shelf skill's SKILL.md references those labels and rejects non-canonical values.

**Acceptance Scenarios**:

1. **Given** the canonical status list is defined in `plugin-shelf/status-labels.md`, **When** any shelf skill sets a project status, **Then** it uses only values from that list: `idea`, `active`, `paused`, `blocked`, `completed`, `archived`.
2. **Given** a user provides a non-canonical status like "in-progress", **When** a shelf skill processes it, **Then** the skill warns the user and suggests the closest canonical equivalent (`active`).
3. **Given** `shelf-create`, `shelf-update`, `shelf-status`, `shelf-sync`, and `shelf-repair` all exist, **When** each skill references project status, **Then** they all import the canonical list from the same source file.

---

### User Story 4 - Repair Existing Dashboards (Priority: P2)

As a developer who updates the shelf plugin, I want a `shelf-repair` workflow that re-applies the current template to existing projects so they stay current with the latest structure without losing my manually-written content (feedback, progress entries, human-needed items).

**Why this priority**: Without repair, template improvements never reach existing projects, causing format drift over time. This is the counterpart to shelf-create — create sets up new projects, repair maintains existing ones.

**Independent Test**: Run `/shelf-repair` on a project with an outdated dashboard format, then verify the structure matches the current template while user-written sections (Feedback, Feedback Log, progress entries) are preserved unchanged.

**Acceptance Scenarios**:

1. **Given** an existing project with an outdated dashboard format, **When** `/shelf-repair` runs, **Then** the dashboard structure is updated to match the current template.
2. **Given** a dashboard with user-written Feedback entries and Human Needed items, **When** `/shelf-repair` runs, **Then** those sections are preserved exactly as-is.
3. **Given** a dashboard with a non-canonical status like "in progress", **When** `/shelf-repair` runs, **Then** the status is normalized to the closest canonical equivalent (`active`).
4. **Given** `/shelf-repair` runs, **When** the diff/preview step executes, **Then** a change report is written to `.wheel/outputs/` before any modifications are applied.
5. **Given** `/shelf-repair` is run twice on the same project, **When** the second run completes, **Then** no changes are made (idempotent).

---

### User Story 5 - Full Sync Summary (Priority: P3)

As a developer running `shelf-full-sync`, I want a consolidated summary of all sync actions at the end so I can quickly see what changed without digging through individual output files.

**Why this priority**: The sync workflow currently runs silently — users have no consolidated view of what happened. This is a quality-of-life improvement that rounds out the sync experience.

**Independent Test**: Run `shelf-full-sync` and verify that `.wheel/outputs/shelf-full-sync-summary.md` is created with counts for issues created/updated/closed/skipped, docs created/updated/skipped, tags added/removed/unchanged, and progress entry status.

**Acceptance Scenarios**:

1. **Given** `shelf-full-sync` completes all steps, **When** the summary step runs, **Then** it reads all prior step outputs and produces a consolidated summary at `.wheel/outputs/shelf-full-sync-summary.md`.
2. **Given** the sync created 3 issues, updated 1, skipped 5, and added 2 tags, **When** the summary is generated, **Then** it includes these exact counts in a human-readable format.
3. **Given** a step produced no changes (e.g., 0 docs synced), **When** the summary is generated, **Then** that section still appears with a count of 0 rather than being omitted.

---

### Edge Cases

- What happens when `.shelf-config` is missing or malformed during `shelf-create` workflow? The workflow falls back to git remote defaults, same as the current skill.
- What happens when the Obsidian MCP server is unavailable during any workflow? The workflow step fails, state file records the failure point, and the user can resume after fixing MCP connectivity.
- What happens when `shelf-repair` encounters a dashboard with completely custom structure (no recognizable template sections)? The diff/preview step reports "unable to map existing structure to template" and skips destructive changes, preserving the original.
- What happens when the vault root `list_files({ directory: "/" })` returns an error? The workflow aborts with a clear error message indicating MCP connectivity or vault access issues.
- What happens when a project has progress signals but no clear status mapping (e.g., only a Dockerfile and nothing else)? The status defaults to `idea` with a note about limited signals.

## Requirements *(mandatory)*

### Functional Requirements

#### shelf-create workflow

- **FR-001**: System MUST implement `shelf-create` as a wheel workflow in `plugin-shelf/workflows/shelf-create.json` with command steps for data gathering and agent steps for MCP operations.
- **FR-002**: The workflow MUST read shelf plugin template files (from `plugin-shelf/templates/`) and produce dashboard, about, and directory structure that exactly matches the template.
- **FR-003**: The workflow's directory resolution step MUST begin from vault root using `mcp__obsidian-projects__list_files({ directory: "/" })` and navigate to the configured base_path — no path guessing.
- **FR-004**: If the configured base_path doesn't exist in the vault, the workflow MUST create it rather than failing silently or guessing alternatives.
- **FR-005**: The workflow MUST include a command step that inspects the repo for progress signals: `specs/` directory (count of spec.md files), code directories (`src/`, `lib/`, `plugin-*`), test files, VERSION file, git commit count, open issues count, and `.kiln/` artifacts.
- **FR-006**: The agent step that creates the dashboard MUST use detected signals to populate initial status (e.g., `active` if code exists, `idea` if only PRDs exist), next_step, and an initial progress entry summarizing what was found.
- **FR-007**: The `shelf-create` skill MUST delegate to `/wheel-run shelf:shelf-create` — the skill becomes a thin wrapper that validates input and launches the workflow.

#### shelf-repair workflow

- **FR-008**: System MUST create a `shelf-repair` wheel workflow in `plugin-shelf/workflows/shelf-repair.json` that re-applies the current template to an existing project's Obsidian notes.
- **FR-009**: `shelf-repair` MUST preserve user-written content (Feedback section, Human Needed items, progress entries, Feedback Log) while updating structure and formatting to match the current template.
- **FR-010**: `shelf-repair` MUST include a diff/preview step that reports what it will change before applying. The agent step reads current dashboard, compares to template, and writes a change report to `.wheel/outputs/`.
- **FR-011**: `shelf-repair` MUST normalize any non-canonical status labels found in existing dashboards to their closest canonical equivalent.

#### Canonical status labels

- **FR-012**: System MUST define a canonical set of project status values in `plugin-shelf/status-labels.md`: `idea`, `active`, `paused`, `blocked`, `completed`, `archived`. This file is the single source of truth.
- **FR-013**: `shelf-create`, `shelf-update`, `shelf-status`, `shelf-sync`, and `shelf-repair` MUST all reference the canonical status list and reject or warn on non-canonical values.

#### shelf-full-sync summary

- **FR-014**: System MUST add a final `command` step to the `shelf-full-sync` workflow that reads all prior step outputs (`sync-issues-results.md`, `sync-docs-results.md`, `update-tags-results.md`, `push-progress-result.md`) and produces a consolidated summary.
- **FR-015**: The summary MUST include counts for: issues created/updated/closed/skipped, docs created/updated/skipped, tags added/removed/unchanged, and whether the progress entry was appended. Output to `.wheel/outputs/shelf-full-sync-summary.md`.

### Key Entities

- **Workflow**: A JSON file in `plugin-shelf/workflows/` defining a sequence of command and agent steps with context dependencies and output paths.
- **Status Label**: One of six canonical values (`idea`, `active`, `paused`, `blocked`, `completed`, `archived`) that represents a project's lifecycle state.
- **Dashboard**: The main Obsidian note for a project, containing frontmatter (status, tags, next_step) and content sections (Human Needed, Feedback, Feedback Log).
- **Progress Signal**: A detectable artifact in a repo (specs, code, tests, commits, issues) used to infer a project's actual development state.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `shelf-create` executes as a wheel workflow with each step producing output in `.wheel/outputs/`, verifiable by inspecting state files after execution.
- **SC-002**: `shelf-create` produces a dashboard that passes a diff check against the rendered template — zero structural deviations.
- **SC-003**: `shelf-create` uses 10 or fewer MCP calls for a standard project scaffold (down from 12-15 with path guessing).
- **SC-004**: `shelf-create` correctly detects and reflects project progress — a repo with code, specs, and tests results in status `active` with a populated progress entry on the first run.
- **SC-005**: `shelf-repair` preserves 100% of user-written content (Feedback, Feedback Log, Human Needed, progress entries) when re-applying templates.
- **SC-006**: `shelf-repair` is idempotent — running it twice produces the same output as running it once, verifiable by diffing the dashboard before and after the second run.
- **SC-007**: All six shelf skills (`shelf-create`, `shelf-update`, `shelf-status`, `shelf-sync`, `shelf-repair`, `shelf-full-sync`) use only canonical status labels — zero non-canonical values in any skill output.
- **SC-008**: `shelf-full-sync` produces a summary file with accurate counts that match the sum of individual step outputs.

## Assumptions

- The Obsidian MCP server (`mcp__obsidian-projects__*`) is available and authenticated when workflows run. Workflows fail gracefully if it's not.
- The wheel workflow engine (`plugin-wheel/`) is functional and supports the workflow JSON format used by `shelf-full-sync`.
- The `.shelf-config` file format (key=value pairs) is stable and will continue to be the project identity resolution mechanism.
- The dashboard template at `plugin-shelf/templates/dashboard.md` is the canonical template for all new and repaired dashboards.
- Existing shelf skills (`shelf-update`, `shelf-status`, `shelf-sync`) will receive only status-label reference updates, not full rewrites.
- Cross-plugin workflow composition (shelf workflows referencing wheel engine) works as established by `shelf-full-sync`.
