# Feature Specification: Kiln Polish — Next Command Suggestion & QA Directory Structure

**Feature Branch**: `build/kiln-polish-20260401`
**Created**: 2026-04-01
**Status**: Draft
**Input**: User description: "Kiln Polish — Add suggested next command to /next skill output and define QA directory manifest/structure for .kiln/qa/"

## User Scenarios & Testing

### User Story 1 - Suggested Next Command (Priority: P1)

As a developer starting a session, I run `/next` to find out what to do. Currently the output is a prioritized list and I have to scan it to decide which command to run. I want `/next` to end with a single prominent "Suggested next" line that tells me exactly what command to run and why, so I can get going immediately.

**Why this priority**: This directly addresses the primary friction point — cognitive load when starting a session. Every kiln user runs `/next` at session start, so this has the widest impact.

**Independent Test**: Run `/next` on a project with outstanding work and verify the output ends with a visually distinct "Suggested next" line containing a single command and brief reason.

**Acceptance Scenarios**:

1. **Given** a project with incomplete tasks in `specs/auth/tasks.md`, **When** the user runs `/next`, **Then** the output ends with a prominent "Suggested next" line showing the highest-priority command (e.g., `Suggested next: /implement — 3 incomplete tasks in specs/auth/tasks.md`)
2. **Given** a project with no outstanding work (all tasks complete, no specs in progress), **When** the user runs `/next`, **Then** the "Suggested next" line says "Nothing urgent" with a fallback suggestion (e.g., "Nothing urgent — check the backlog with `/issue-to-prd`")
3. **Given** a project with multiple actionable recommendations at different priority levels, **When** the user runs `/next`, **Then** the "Suggested next" line shows only the single highest-priority command, not multiple options

---

### User Story 2 - QA Directory Structure (Priority: P1)

As a developer reviewing QA results, I want to know exactly where screenshots, videos, reports, and test configs live so I can find them without searching. The `.kiln/qa/` directory should have a defined, documented structure with canonical locations for all QA artifact types.

**Why this priority**: Without a standard structure, QA agents write artifacts to inconsistent locations, making outputs hard to discover across projects. This is equally important as the `/next` improvement.

**Independent Test**: Run `/qa-setup` on a fresh project and verify the `.kiln/qa/` directory contains the expected subdirectories and a README documenting the layout.

**Acceptance Scenarios**:

1. **Given** a new consumer project initialized with kiln, **When** the user runs `/qa-setup`, **Then** the `.kiln/qa/` directory is created with subdirectories: `tests/`, `results/`, `screenshots/`, `videos/`, `config/`
2. **Given** an existing project with ad-hoc files already in `.kiln/qa/`, **When** the user runs `/qa-setup`, **Then** the standardized subdirectories are created without deleting or moving existing files
3. **Given** a `.kiln/qa/` directory with the standard structure, **When** a QA agent produces a screenshot, **Then** the screenshot is saved to `.kiln/qa/screenshots/`, not an ad-hoc location

---

### User Story 3 - QA Directory README (Priority: P2)

As a new project user, I want a README inside `.kiln/qa/` that documents the directory layout so I can understand the structure before running any QA commands.

**Why this priority**: Documentation is important but secondary to having the structure itself. The README makes the structure self-documenting.

**Independent Test**: Open `.kiln/qa/README.md` in a freshly initialized project and verify it documents each subdirectory's purpose and expected contents.

**Acceptance Scenarios**:

1. **Given** a project initialized with kiln via `init.mjs`, **When** the user opens `.kiln/qa/README.md`, **Then** the file documents each subdirectory's purpose, expected file types, and which skills/agents write to each location
2. **Given** a project where `/qa-setup` has been run, **When** the user opens `.kiln/qa/README.md`, **Then** the content is consistent with the actual directory structure created

---

### User Story 4 - Scaffold Creates QA Structure (Priority: P2)

As a project bootstrapper, I want `init.mjs` to create the `.kiln/qa/` directory structure automatically so new projects start with the canonical layout from day one.

**Why this priority**: Ensures consistency across all consumer projects without requiring manual setup.

**Independent Test**: Run `node plugin/bin/init.mjs init` on a fresh repo and verify `.kiln/qa/` subdirectories and README exist.

**Acceptance Scenarios**:

1. **Given** a fresh repo with no `.kiln/` directory, **When** the user runs `node plugin/bin/init.mjs init`, **Then** `.kiln/qa/` is created with subdirectories `tests/`, `results/`, `screenshots/`, `videos/`, `config/` and a `README.md`
2. **Given** an existing project with a `.kiln/qa/` directory already present, **When** the user runs `node plugin/bin/init.mjs update`, **Then** missing subdirectories are created without disturbing existing files

---

### Edge Cases

- What happens when `/next` has multiple recommendations at the same priority level? The system picks the first one encountered in its evaluation order and uses that as the suggested command.
- What happens when `.kiln/qa/` subdirectories already exist with files? The scaffold and `/qa-setup` create only missing directories; existing files are never deleted or moved.
- What happens if `/next` is run in `--brief` mode? The "Suggested next" line still appears but the full recommendations list is suppressed.

## Requirements

### Functional Requirements

- **FR-001**: After the recommendations list, `/next` MUST output a visually distinct "Suggested next" line containing the single highest-priority command from the recommendations.
- **FR-002**: The suggested command MUST include a brief reason (e.g., "3 incomplete tasks in specs/auth/tasks.md") so the user understands why it is the top pick.
- **FR-003**: If no actionable recommendations exist (project is clean), the "Suggested next" line MUST say so (e.g., "Nothing urgent — check the backlog with `/issue-to-prd`").
- **FR-004**: A QA directory manifest MUST define the expected `.kiln/qa/` folder structure, including subdirectories for tests, results, screenshots, videos, and configuration.
- **FR-005**: The `/qa-setup` skill MUST create the standardized `.kiln/qa/` directory structure when run.
- **FR-006**: QA agent outputs (reports, screenshots, videos, test results) MUST be written to their canonical locations within `.kiln/qa/`.
- **FR-007**: The `init.mjs` scaffold MUST create the `.kiln/qa/` directory structure (empty subdirectories) in new consumer projects.
- **FR-008**: A `.kiln/qa/README.md` MUST document the directory layout so users can find artifacts without reading skill source code.

### Key Entities

- **QA Directory Manifest**: The canonical definition of `.kiln/qa/` subdirectory structure and the purpose of each subdirectory.
- **Suggested Next Command**: A single command extracted from the prioritized recommendations list, displayed as the final line of `/next` output.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Running `/next` on a project with outstanding work shows a "Suggested next: `/command` — reason" line at the bottom of the output 100% of the time.
- **SC-002**: Running `/next` on a clean project shows "Nothing urgent" with a fallback suggestion 100% of the time.
- **SC-003**: All consumer projects initialized with kiln have a `.kiln/qa/` directory with 5 standard subdirectories (`tests/`, `results/`, `screenshots/`, `videos/`, `config/`) and a README.
- **SC-004**: QA skills (`/qa-setup`, `/qa-pass`, `/qa-checkpoint`) write outputs to the standardized paths, with zero artifacts written to ad-hoc locations outside the structure.

## Assumptions

- The `/next` skill's existing prioritization logic is correct and does not need changes — only the output format changes to highlight the top recommendation.
- The `.kiln/qa/` subdirectory list is: `tests/`, `results/`, `screenshots/`, `videos/`, `config/`. No `latest/` symlink directory is needed at this time.
- Existing `.kiln/qa/` files in consumer projects are not moved or deleted — only missing subdirectories are created.
- The `--brief` mode of `/next` still shows the "Suggested next" line (it suppresses the full list, not the suggestion).
- QA skills create directories on-demand if missing, providing backwards compatibility during mid-flight upgrades.
