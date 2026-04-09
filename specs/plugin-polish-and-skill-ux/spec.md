# Feature Specification: Plugin Polish & Skill UX

**Feature Branch**: `build/plugin-polish-and-skill-ux-20260409`
**Created**: 2026-04-09
**Status**: Draft
**Input**: User description: "Plugin polish and skill UX improvements. 12 FRs covering workflow packaging, init cleanup, wheel pre-flight, /next filtering, issue backlinks, and trim-push page compositions."

## User Scenarios & Testing

### User Story 1 - Workflow Ships with Plugin (Priority: P1)

As a consumer project user, I install `@yoshisada/kiln` via npm and run `/report-issue`. The workflow `report-issue-and-sync.json` is discovered by wheel without me manually copying any files. When I run `kiln init` or `init.mjs update`, plugin-bundled workflows are synced into my project's `workflows/` directory if they don't already exist.

**Why this priority**: This is a blocking bug. Consumer projects cannot use `/report-issue` at all without manual intervention, which defeats the purpose of a plugin.

**Independent Test**: Install the plugin in a fresh project, run `/report-issue`, and verify it completes without errors about missing workflows.

**Acceptance Scenarios**:

1. **Given** a freshly initialized consumer project with `@yoshisada/kiln` installed, **When** the user runs `/report-issue`, **Then** the `report-issue-and-sync` workflow executes successfully without manual file copying.
2. **Given** a consumer project that already has a customized `report-issue-and-sync.json` in `workflows/`, **When** `init.mjs update` runs, **Then** the existing workflow is NOT overwritten.
3. **Given** the kiln npm package, **When** inspecting its contents, **Then** `workflows/report-issue-and-sync.json` is included and declared in `plugin.json`.

---

### User Story 2 - Trim-Push Full Page Compositions (Priority: P1)

As a designer using trim, I want trim-push to create both component-level frames and full page compositions in Penpot, so I can review complete screens rather than isolated component blocks.

**Why this priority**: Without page compositions, the entire design-sync pipeline is incomplete. Designers cannot review full screens, which is the primary use case.

**Independent Test**: Run trim-push on a project with both `components/` and `pages/` directories, and verify Penpot contains both a Components page with a bento grid and individual page frames.

**Acceptance Scenarios**:

1. **Given** a project with files in `components/` and `pages/app/` directories, **When** trim-push runs, **Then** files in `components/` are classified as "component" and files in `pages/app/` are classified as "page".
2. **Given** classified components, **When** trim-push creates Penpot frames, **Then** components are placed on a single "Components" page in a bento grid layout.
3. **Given** classified pages, **When** trim-push creates Penpot frames, **Then** each page gets its own individual Penpot page as a full-screen composed frame referencing the component library.
4. **Given** a file that imports layout components and is referenced by a router, **When** classification runs, **Then** the file is classified as "page" regardless of its directory location.

---

### User Story 3 - Clean Init Scaffold (Priority: P2)

As a developer with a non-standard project layout, I want `kiln init` to only create kiln-specific directories (`.kiln/`, `specs/`, `.specify/`), not `src/` or `tests/`, so my project structure stays clean.

**Why this priority**: This causes friction for every new consumer project with a non-standard layout. Easy fix with high impact on first impressions.

**Independent Test**: Run `kiln init` on an empty repo and verify that `src/` and `tests/` directories are NOT created while `.kiln/`, `specs/`, `.specify/` ARE created.

**Acceptance Scenarios**:

1. **Given** an empty repository, **When** running `node init.mjs init`, **Then** `.kiln/`, `specs/`, and `.specify/` directories are created but `src/` and `tests/` are NOT created.
2. **Given** a repository that already has a `src/` directory, **When** running `node init.mjs init`, **Then** the existing `src/` directory is left untouched.

---

### User Story 4 - Wheel Pre-flight Auto-Setup (Priority: P2)

As a new user, I want clear guidance when wheel isn't configured, so I can fix the setup instead of getting stuck on opaque errors.

**Why this priority**: Opaque errors block new users entirely. A clear message with a suggested fix dramatically improves onboarding.

**Independent Test**: Run `/wheel-run` in a project without wheel configured and verify an actionable error message appears mentioning `/wheel-init`.

**Acceptance Scenarios**:

1. **Given** a project where wheel hooks are not registered and `.wheel/` does not exist, **When** the user attempts to run a workflow, **Then** a clear message is displayed: "Wheel is not set up for this repo. Run `/wheel-init` to configure it."
2. **Given** a project where wheel is not set up, **When** the pre-flight check fails, **Then** the system optionally offers to run setup automatically.
3. **Given** a properly configured wheel project, **When** the user runs a workflow, **Then** the pre-flight check passes silently and the workflow proceeds normally.

---

### User Story 5 - /next Shows High-Level Commands Only (Priority: P2)

As a kiln user, I want `/next` to show me meaningful high-level actions, not internal pipeline steps I shouldn't run directly.

**Why this priority**: Showing internal commands confuses users and leads to broken workflows when they run pipeline steps out of order.

**Independent Test**: Run `/next` and verify the output contains zero internal pipeline commands while still recommending appropriate high-level commands.

**Acceptance Scenarios**:

1. **Given** a project in any state, **When** the user runs `/next`, **Then** the output contains only commands from the whitelist: `/build-prd`, `/fix`, `/qa-pass`, `/create-prd`, `/create-repo`, `/init`, `/analyze-issues`, `/report-issue`, `/ux-evaluate`, `/issue-to-prd`, `/next`, `/todo`, `/roadmap`.
2. **Given** a project in any state, **When** the user runs `/next`, **Then** the output does NOT contain: `/specify`, `/plan`, `/tasks`, `/implement`, `/audit`, `/debug-diagnose`, `/debug-fix`.

---

### User Story 6 - Issue Backlinks with Repo and File Context (Priority: P3)

As a team triaging issues, I want backlog entries created via `/report-issue` to include the repo URL and relevant file paths, so I can navigate to the code without searching.

**Why this priority**: Nice-to-have that improves triage efficiency but doesn't block any core workflow.

**Independent Test**: Run `/report-issue` and verify the created backlog entry includes `repo:` and `files:` fields in its frontmatter.

**Acceptance Scenarios**:

1. **Given** a user running `/report-issue` in a GitHub-connected repo, **When** the issue is created, **Then** the frontmatter includes a `repo:` field populated with the repo URL from `gh repo view --json url`.
2. **Given** a report-issue description that references specific file paths, **When** the issue is created, **Then** the frontmatter includes a `files:` field listing the referenced paths.
3. **Given** a repo without GitHub remote configured, **When** the issue is created, **Then** the `repo:` field is left empty and no error occurs.

---

### Edge Cases

- What happens when `gh` CLI is not installed? The `repo` field should be left empty gracefully.
- What happens when a consumer project already has a customized workflow file? It must not be overwritten during update.
- What happens when a file could be classified as both component and page? Directory convention takes precedence; router/layout heuristics are secondary.
- What happens when wheel is partially configured (`.wheel/` exists but hooks are missing)? Pre-flight should detect this and report the specific missing piece.
- What happens when `/next` whitelist is empty or all commands are filtered out? At minimum, `/next` itself should always appear.

## Requirements

### Functional Requirements

**Workflow Packaging (from: workflow-in-plugin-package.md)**

- **FR-001**: Plugin MUST include `report-issue-and-sync.json` in the kiln plugin's `workflows/` directory and declare it in `plugin.json` so wheel discovers it as a plugin-provided workflow in consumer projects.
- **FR-002**: `init.mjs update` MUST sync plugin workflows into the consumer project's `workflows/` directory if they don't already exist, without overwriting customized versions.

**Trim-Push Page Compositions (from: trim-push-should-build-full-pages.md)**

- **FR-003**: Trim-push workflow MUST classify scanned files as "component" vs "page" based on directory conventions (`components/` vs `pages/app/` routes), router references, and layout imports.
- **FR-004**: Components MUST be pushed to a Penpot Components page as a bento grid. Pages MUST be pushed to their own individual Penpot pages as full-screen composed frames that reference the component library.
- **FR-005**: Trim-push agent instructions MUST explicitly distinguish component-level vs page-level push behavior with clear guidance for each classification type.

**Init Scaffold Cleanup (from: init-no-src-tests-dirs.md)**

- **FR-006**: `init.mjs` MUST NOT create `src/` and `tests/` directories. Only kiln-specific directories (`.kiln/`, `specs/`, `.specify/`, etc.) are created during initialization.

**Wheel Pre-flight (from: wheel-init-failure-auto-setup.md)**

- **FR-007**: Wheel-run (or `activate.sh`) MUST include a pre-flight check that verifies wheel hooks are registered and `.wheel/` directory exists before attempting workflow execution.
- **FR-008**: When pre-flight fails, the system MUST print a clear message ("Wheel is not set up for this repo. Run `/wheel-init` to configure it.") and optionally offer to run setup automatically.

**/next Command Filtering (from: next-high-level-commands-only.md)**

- **FR-009**: The continuance agent MUST filter command recommendations to a whitelist of high-level user-facing commands: `/build-prd`, `/fix`, `/qa-pass`, `/create-prd`, `/create-repo`, `/init`, `/analyze-issues`, `/report-issue`, `/ux-evaluate`, `/issue-to-prd`, `/next`, `/todo`, `/roadmap`.
- **FR-010**: Internal pipeline commands (`/specify`, `/plan`, `/tasks`, `/implement`, `/audit`, `/debug-diagnose`, `/debug-fix`) MUST NOT appear in `/next` output.

**Issue Backlinks (from: issue-backlinks-to-repos-files.md)**

- **FR-011**: The backlog issue frontmatter template MUST include optional `repo` and `files` fields.
- **FR-012**: When creating a backlog issue, the system MUST auto-detect the current repo URL via `gh repo view --json url` and populate the `repo` field. Referenced file paths from the description MUST be extracted into the `files` field.

## Success Criteria

### Measurable Outcomes

- **SC-001**: `/report-issue` succeeds in a freshly-initialized consumer project without manual workflow copying (100% success rate on first attempt).
- **SC-002**: `kiln init` on an empty repo creates `.kiln/`, `specs/`, `.specify/` but NOT `src/` or `tests/` (zero false directory creation).
- **SC-003**: Running a workflow without wheel configured produces an actionable error message mentioning `/wheel-init` within 2 seconds.
- **SC-004**: `/next` output contains zero internal pipeline commands across all project states.
- **SC-005**: 100% of new backlog issues created via `/report-issue` include a `repo:` field in frontmatter when running in a GitHub-connected repo.
- **SC-006**: trim-push on a project with `pages/` and `components/` directories creates both component frames and page frames in Penpot (both classification types represented).

## Assumptions

- Consumer projects have `@yoshisada/kiln` installed via npm and use the standard plugin discovery mechanism.
- The `gh` CLI may or may not be installed in consumer environments; features depending on it degrade gracefully.
- Penpot MCP tools are available when trim-push runs; if not, trim-push fails with an existing error (no new handling needed).
- Wheel plugin (`plugin-wheel/`) is co-installed with kiln; the pre-flight check is added to wheel's own activation path.
- The `/next` command whitelist is maintained in the continuance agent's skill definition and can be updated by editing that file.
- Existing consumer projects will not break when updating to this version (backwards compatibility via additive-only changes and optional fields).
