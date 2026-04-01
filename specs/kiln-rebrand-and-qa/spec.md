# Feature Specification: Kiln Rebrand, Infrastructure & QA Reliability

**Feature Branch**: `build/kiln-rebrand-and-qa-20260331`
**Created**: 2026-03-31
**Status**: Draft
**Input**: User description: "Kiln rebrand, .kiln/ infrastructure, kiln doctor, and QA build verification as described in docs/features/2026-03-31-kiln-rebrand-and-qa/PRD.md"

## User Scenarios & Testing

### User Story 1 - Plugin Identity is Clear and Consistent (Priority: P1)

As a new user discovering the plugin, I want the name "kiln" to appear consistently across all touchpoints (npm install, plugin commands, documentation) so that I immediately understand what the tool does and never encounter mixed branding.

**Why this priority**: The rebrand is the foundational change that all other work depends on. Mixed branding confuses users and undermines trust. Every user-facing surface must say "kiln" before other features make sense.

**Independent Test**: Install the plugin via npm, run `/init`, and verify that every command name, log output, and generated file references "kiln" with zero mentions of "speckit-harness."

**Acceptance Scenarios**:

1. **Given** the plugin is published to npm, **When** a user runs `npm install @yoshisada/kiln`, **Then** the package installs successfully and the plugin manifest identifies itself as "kiln."
2. **Given** a consumer project with the plugin installed, **When** the user lists available commands, **Then** all skill names use the new naming convention (e.g., `/specify`, `/plan`, `/tasks`) with no `speckit-` prefixes.
3. **Given** a consumer project still referencing `speckit-harness:` prefixed skills, **When** the user invokes an old skill name, **Then** the system displays a deprecation notice directing them to the new name.
4. **Given** the CLAUDE.md, README, and all documentation files, **When** a user reads any documentation, **Then** all references use "kiln" branding with no remaining "speckit-harness" strings.

---

### User Story 2 - Centralized Artifact Storage in .kiln/ (Priority: P1)

As a developer using kiln, I want all automation artifacts (agent outputs, QA results, workflow definitions, issue tracking, logs) stored in a single `.kiln/` directory so that I have one predictable place to find everything the pipeline produced.

**Why this priority**: Artifact sprawl across ad-hoc directories is a daily pain point. Centralizing storage is the infrastructure that all other features (doctor, QA routing) build upon.

**Independent Test**: Run `/init` on a fresh project and verify `.kiln/` is created with the correct subdirectory structure. Run a build pipeline and verify outputs land in the expected `.kiln/` subdirectories.

**Acceptance Scenarios**:

1. **Given** a new consumer project, **When** the user runs `/init`, **Then** a `.kiln/` directory is created with subdirectories: `workflows/`, `agents/`, `issues/`, `qa/`, `logs/`.
2. **Given** a project with `.kiln/` already present, **When** the user runs `/init` again, **Then** the existing directory is preserved without duplication or corruption.
3. **Given** a running pipeline, **When** an agent completes a run, **Then** the agent's outputs (logs, artifacts) are written to `.kiln/agents/` in a per-run subdirectory.
4. **Given** a user running `/report-issue`, **When** they submit an issue, **Then** the issue file is created in `.kiln/issues/` instead of `docs/backlog/`.
5. **Given** a QA pass completes, **When** results are generated, **Then** QA artifacts are written to `.kiln/qa/`.
6. **Given** a pipeline build completes, **When** logs are generated, **Then** build/pipeline logs are written to `.kiln/logs/`.
7. **Given** the `.kiln/` directory, **When** the user checks `.gitignore`, **Then** transient outputs (agent run logs, QA test runs) are excluded while workflow definitions and issues are tracked.

---

### User Story 3 - Kiln Doctor Validates and Migrates Project State (Priority: P2)

As a developer upgrading from speckit-harness, I want to run `kiln doctor` to automatically detect outdated directory structures and migrate them so that I don't have to manually reorganize my project files.

**Why this priority**: Without a migration tool, the rebrand and `.kiln/` changes would require every existing user to manually restructure their project. Doctor makes the upgrade path seamless.

**Independent Test**: Set up a project with legacy directory structure (e.g., `docs/backlog/` with issues, `qa-results/` with QA artifacts), run `/kiln-doctor`, and verify it detects and migrates all legacy paths to `.kiln/` equivalents.

**Acceptance Scenarios**:

1. **Given** a project with legacy `docs/backlog/` directory containing issue files, **When** the user runs `/kiln-doctor` in diagnose mode, **Then** the tool reports that `docs/backlog/` should be migrated to `.kiln/issues/`.
2. **Given** a project with legacy `qa-results/` directory, **When** the user runs `/kiln-doctor` in diagnose mode, **Then** the tool reports that `qa-results/` should be migrated to `.kiln/qa/`.
3. **Given** a project with missing `.kiln/` subdirectories, **When** the user runs `/kiln-doctor` in diagnose mode, **Then** the tool reports which directories are missing.
4. **Given** diagnosed issues exist, **When** the user runs `/kiln-doctor` in fix mode, **Then** each suggested fix is presented for confirmation and applied when approved.
5. **Given** a project that has already been fully migrated, **When** the user runs `/kiln-doctor` again, **Then** the tool reports no issues found (idempotent).
6. **Given** a manifest file defining the expected `.kiln/` structure, **When** the doctor runs, **Then** it validates the current project state against the manifest.

---

### User Story 4 - QA Engineer Verifies Latest Build Before Testing (Priority: P2)

As a pipeline operator, I want the QA engineer to verify it's testing the latest build before evaluating so that I don't waste time investigating phantom bugs from stale builds.

**Why this priority**: This is a reliability fix for a recurring issue that wastes investigation time. It's critical for pipeline trustworthiness but doesn't block other features.

**Independent Test**: Make a code change, deliberately skip rebuilding, then trigger QA. Verify the QA agent detects the version mismatch, triggers a rebuild, and only proceeds after confirming the build is current.

**Acceptance Scenarios**:

1. **Given** the app is built and running with version matching the VERSION file, **When** the QA engineer starts a test run, **Then** the pre-flight version check passes and testing proceeds immediately.
2. **Given** the app is running with a version that does not match the VERSION file, **When** the QA engineer starts a test run, **Then** the pre-flight step detects the mismatch and triggers a rebuild.
3. **Given** a rebuild was triggered and completed, **When** the version is re-checked, **Then** the versions now match and testing proceeds.
4. **Given** a rebuild was triggered but the version still doesn't match after rebuild, **When** the re-check fails, **Then** the QA engineer warns the team lead and proceeds with a disclaimer note in the QA report.
5. **Given** the `/qa-pass` or `/ux-evaluate` skill is invoked, **When** the skill starts, **Then** the same version verification pre-flight runs before any evaluation begins.

---

### User Story 5 - Reusable Workflow Definitions (Priority: P3)

As a developer, I want to define reusable workflows in `.kiln/workflows/` so that recurring automation tasks can be stored and executed on demand from a standard location.

**Why this priority**: This is forward-looking infrastructure. The directory and format specification need to exist, but active workflow execution can be iterated on in future releases.

**Independent Test**: Create a workflow definition file in `.kiln/workflows/`, verify it conforms to the format specification, and confirm skills/agents can read it.

**Acceptance Scenarios**:

1. **Given** a workflow format specification exists, **When** a developer creates a workflow file in `.kiln/workflows/`, **Then** the file follows the defined format and is discoverable by skills and agents.
2. **Given** workflow definitions exist in `.kiln/workflows/`, **When** `.gitignore` is checked, **Then** workflow definitions are tracked in version control.

---

### Edge Cases

- What happens when a consumer project has both old (`docs/backlog/`) and new (`.kiln/issues/`) directories with different content? Doctor must merge without data loss.
- What happens when the VERSION file does not exist in a consumer project? QA version check should skip gracefully with a warning.
- What happens when the app does not expose a version string in the UI? The system should fall back to checking build output timestamps or git SHA.
- What happens when `/init` is run on a project that already has a partial `.kiln/` structure? Must create only missing subdirectories without affecting existing content.
- What happens when a consumer project uses custom skill names that collide with the new short names? The plugin should detect and warn about conflicts.

## Requirements

### Functional Requirements

**Rename**

- **FR-001**: System MUST rename the npm package from `@yoshisada/speckit-harness` to `@yoshisada/kiln` in the package manifest.
- **FR-002**: System MUST update the plugin manifest name field to "kiln."
- **FR-003**: System MUST rename all skill prefixes from `speckit-harness:` to `kiln:` in skill directory names and namespace references.
- **FR-004**: System MUST rename internal skill names by dropping the `speckit-` prefix: `speckit-specify` becomes `specify`, `speckit-plan` becomes `plan`, `speckit-tasks` becomes `tasks`, `speckit-implement` becomes `implement`, `speckit-audit` becomes `audit`, `speckit-constitution` becomes `constitution`, `speckit-analyze` becomes `analyze`, `speckit-coverage` becomes `coverage`, `speckit-checklist` becomes `checklist`, `speckit-clarify` becomes `clarify`, `speckit-taskstoissues` becomes `taskstoissues`.
- **FR-005**: System MUST update all references in CLAUDE.md, README, scaffold templates, and documentation to use "kiln" branding.
- **FR-006**: System MUST update the init script to reference the new package name and internal naming.
- **FR-007**: System MUST provide a deprecation notice when a consumer project references old `speckit-harness:` prefixed skill names, pointing to the new names.

**.kiln/ Directory**

- **FR-008**: System MUST define the `.kiln/` directory structure with subdirectories: `workflows/`, `agents/`, `issues/`, `qa/`, `logs/`.
- **FR-009**: System MUST update the init script to scaffold the `.kiln/` directory structure in consumer projects.
- **FR-010**: System MUST route agent run outputs (logs, artifacts) into `.kiln/agents/` with per-run directories.
- **FR-011**: System MUST move issue/backlog tracking from `docs/backlog/` to `.kiln/issues/` and update the `/report-issue` skill to write to the new location.
- **FR-012**: System MUST route QA artifacts from `/qa-pass`, `/qa-final`, `/qa-checkpoint` into `.kiln/qa/`.
- **FR-013**: System MUST route build/pipeline logs from `/build-prd` into `.kiln/logs/`.
- **FR-014**: System MUST configure `.gitignore` to exclude transient outputs (agent run logs, QA test runs) while tracking workflow definitions and issues.
- **FR-015**: System MUST define a workflow format specification that skills and agents can produce and consume from `.kiln/workflows/`.

**Kiln Doctor**

- **FR-016**: System MUST define a manifest format (JSON) describing the expected `.kiln/` directory structure, required subdirectories, and file naming conventions.
- **FR-017**: System MUST provide a `/kiln-doctor` skill that reads the manifest and compares current project state against it.
- **FR-018**: Doctor MUST support a diagnose mode that reports missing directories, misplaced files, stale artifacts, and legacy paths needing migration.
- **FR-019**: Doctor MUST support a fix mode that presents suggested fixes for confirmation and applies them idempotently.
- **FR-020**: System MUST map all known legacy paths to their `.kiln/` equivalents for automatic migration detection.

**QA Build Verification**

- **FR-021**: System MUST add a pre-flight step to the qa-engineer agent that reads the version string from the app and compares it against the VERSION file or latest git commit.
- **FR-022**: If a version mismatch is detected, the system MUST trigger a rebuild, wait for completion, and re-check the version.
- **FR-023**: If the version still doesn't match after rebuild, the system MUST warn the team lead and proceed with a disclaimer note in the QA report.
- **FR-024**: System MUST add the same version verification pre-flight to `/qa-pass` and `/ux-evaluate` skills.

### Key Entities

- **Plugin Manifest**: The `plugin.json` file that identifies the plugin name, version, and capabilities to the Claude Code platform.
- **.kiln/ Directory**: The standardized directory in consumer projects for storing all automation artifacts, with defined subdirectories for different artifact types.
- **Doctor Manifest**: A JSON schema defining the expected project structure, used by kiln doctor to validate and migrate consumer projects.
- **Legacy Path Mapping**: A defined set of old-path to new-path mappings (e.g., `docs/backlog/` to `.kiln/issues/`) used by the doctor for migration.
- **Workflow Definition**: A file format specification for reusable automation workflows stored in `.kiln/workflows/`.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All user-facing references say "kiln" with zero remaining "speckit-harness" strings in plugin code, documentation, or scaffold output.
- **SC-002**: Consumer projects scaffolded with `/init` have a properly structured `.kiln/` directory with all 5 required subdirectories present.
- **SC-003**: `kiln doctor` correctly identifies and migrates at least 2 legacy path mappings: `docs/backlog/` to `.kiln/issues/` and `qa-results/` to `.kiln/qa/`.
- **SC-004**: QA engineer agent version verification runs before every evaluation with no findings produced against a stale build.
- **SC-005**: Existing consumer projects can upgrade without manual file reorganization by running `kiln doctor`.
- **SC-006**: Running `/init` twice on the same project produces no duplicate directories or corrupted state.
- **SC-007**: Doctor completes a full project scan in under 10 seconds for typical consumer projects.
- **SC-008**: QA version check adds no more than 30 seconds to the pre-flight phase.

## Assumptions

- The `.specify/` directory for speckit memory and constitution is unchanged and remains separate from `.kiln/`.
- The `specs/` directory for feature spec artifacts remains in its current location.
- The core workflow (specify, plan, tasks, implement, audit) is unchanged; only naming and artifact routing change.
- Consumer projects may or may not expose a version string in the UI; the QA version check must support fallback strategies (build timestamps, git SHA).
- The npm package `@yoshisada/speckit-harness` will be deprecated on npm pointing users to `@yoshisada/kiln`.
- Claude Code's plugin discovery system supports skill renames without requiring cache invalidation by the user.
- Existing consumer projects will continue to function without the `.kiln/` directory until they explicitly run `/init` or `kiln doctor` to migrate.
