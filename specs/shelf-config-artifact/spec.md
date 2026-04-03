# Feature Specification: Shelf Config Artifact

**Feature Branch**: `build/shelf-config-artifact-20260403`  
**Created**: 2026-04-03  
**Status**: Draft  
**Input**: User description: "Add .shelf-config artifact file to shelf plugin skills so they can track which Obsidian directory a project is being tracked in. The config is written by /shelf-create and read by all 6 shelf skills."

## User Scenarios & Testing

### User Story 1 - Config Created on Project Setup (Priority: P1)

A developer runs `/shelf-create` to scaffold a new Obsidian project. After the project is created, the skill automatically writes a `.shelf-config` file to the repo root containing the base path, slug, and dashboard path. The developer never needs to manually create this file.

**Why this priority**: This is the foundation — without the config being written, no other skill can read it. This story must work before anything else has value.

**Independent Test**: Run `/shelf-create plugin-shelf` in a repo. Verify `.shelf-config` exists in the repo root with correct `base_path`, `slug`, and `dashboard_path` values.

**Acceptance Scenarios**:

1. **Given** a repo without `.shelf-config`, **When** the user runs `/shelf-create plugin-shelf`, **Then** a `.shelf-config` file is written to the repo root containing `base_path`, `slug`, and `dashboard_path` with correct values.
2. **Given** a repo without `.shelf-config`, **When** the user runs `/shelf-create` (no argument), **Then** the skill derives the slug from the git remote, confirms it with the user, and writes `.shelf-config` with the confirmed values.
3. **Given** a repo where the desired slug differs from the repo name, **When** the user runs `/shelf-create custom-name`, **Then** `.shelf-config` contains `slug = custom-name` and the dashboard path reflects that slug.

---

### User Story 2 - Skills Read Config Automatically (Priority: P1)

A developer who has already run `/shelf-create` uses any shelf skill (`/shelf-sync`, `/shelf-update`, `/shelf-status`, `/shelf-feedback`, `/shelf-release`) without passing a project name argument. The skill reads `.shelf-config` and resolves the correct Obsidian project path automatically.

**Why this priority**: This is the core value proposition — eliminating the need to pass the slug every time. Equal priority to US-1 because both are required for the feature to deliver value.

**Independent Test**: After `.shelf-config` exists with `slug = plugin-shelf` and `base_path = @second-brain/projects`, run `/shelf-status` with no arguments. Verify it reads from the correct Obsidian project path.

**Acceptance Scenarios**:

1. **Given** `.shelf-config` exists with valid `base_path` and `slug`, **When** the user runs `/shelf-sync` with no arguments, **Then** the skill uses the config values instead of deriving from git remote.
2. **Given** `.shelf-config` exists with valid values, **When** the user runs `/shelf-update` with no arguments, **Then** the skill resolves the correct Obsidian project path from the config.
3. **Given** `.shelf-config` exists with valid values, **When** the user runs any shelf skill with an explicit project name argument, **Then** the argument takes precedence over the config file values.

---

### User Story 3 - Graceful Fallback Without Config (Priority: P2)

A developer clones a repo that does not have `.shelf-config` (e.g., created before this feature existed). All shelf skills continue to work exactly as they do today — deriving the slug from the git remote and using the default base path.

**Why this priority**: Backward compatibility is important but is largely the existing behavior — this story confirms nothing breaks rather than adding new capability.

**Independent Test**: Remove `.shelf-config` from a repo and run `/shelf-status`. Verify it falls back to deriving the slug from git remote and using the default base path.

**Acceptance Scenarios**:

1. **Given** no `.shelf-config` exists, **When** the user runs any shelf skill, **Then** the skill falls back to deriving the slug from `git remote get-url origin` and using `projects` as the default base path.
2. **Given** `.shelf-config` exists but is malformed (missing required keys), **When** the user runs a shelf skill, **Then** the skill warns the user about the malformed config and falls back to default behavior.

---

### User Story 4 - Manual Config Editing (Priority: P3)

A developer renames their Obsidian project or moves it to a different vault path. They manually edit `.shelf-config` to update the values, and all shelf skills immediately respect the new configuration.

**Why this priority**: This is an edge case that provides flexibility but isn't part of the primary workflow.

**Independent Test**: Manually edit `.shelf-config` to change the slug, then run `/shelf-status`. Verify it uses the updated slug.

**Acceptance Scenarios**:

1. **Given** `.shelf-config` exists, **When** the user manually edits the `slug` value, **Then** all shelf skills use the new slug on the next run.
2. **Given** `.shelf-config` exists, **When** the user manually edits the `base_path` value, **Then** all shelf skills use the new base path on the next run.

---

### Edge Cases

- What happens when `.shelf-config` exists but contains extra unknown keys? Skills should ignore unknown keys and only read the ones they need.
- What happens when `.shelf-config` has trailing whitespace or inconsistent spacing around `=`? The parser should be tolerant of whitespace variations.
- What happens when `.shelf-config` contains comment lines (starting with `#`)? Comments should be ignored during parsing.
- What happens when the Obsidian MCP server is unavailable during `/shelf-create`? The `.shelf-config` should NOT be written if the project was not actually created in Obsidian.

## Requirements

### Functional Requirements

- **FR-001**: `/shelf-create` MUST write a `.shelf-config` file to the repo root after successfully creating the Obsidian project dashboard.
- **FR-002**: The `.shelf-config` file MUST contain at minimum: `base_path` (the Obsidian vault path prefix) and `slug` (the project slug used in vault paths).
- **FR-003**: The `.shelf-config` file MUST also contain `dashboard_path` — the full resolved path to the project dashboard file (e.g., `@second-brain/projects/plugin-shelf/plugin-shelf.md`).
- **FR-004**: The `.shelf-config` file format MUST be a simple key-value format (one key per line, `key = value`), human-readable and editable.
- **FR-005**: All 6 shelf skills (`shelf-create`, `shelf-sync`, `shelf-update`, `shelf-status`, `shelf-feedback`, `shelf-release`) MUST read `.shelf-config` as the first step in path resolution, before falling back to defaults.
- **FR-006**: When `.shelf-config` exists and contains valid `base_path` and `slug`, skills MUST NOT prompt the user for a project name or derive one from the git remote.
- **FR-007**: `/shelf-create` MUST ask the user to confirm the slug and base path before writing `.shelf-config`, especially when the slug differs from the repo name.
- **FR-008**: The `.shelf-config` file SHOULD be committed to the repo (not gitignored) so that all collaborators share the same Obsidian project mapping.

### Key Entities

- **`.shelf-config`**: A plain-text key-value configuration file at the repo root. Contains `base_path`, `slug`, and `dashboard_path`. Human-readable, parseable with basic shell tools (`grep`, `sed`, `awk`). Supports `#` comment lines.

## Success Criteria

### Measurable Outcomes

- **SC-001**: After running `/shelf-create`, a `.shelf-config` file exists in the repo root with all three required keys (`base_path`, `slug`, `dashboard_path`).
- **SC-002**: All 6 shelf skills resolve the correct Obsidian project path when `.shelf-config` is present, without requiring any arguments from the user.
- **SC-003**: All 6 shelf skills continue to work correctly when `.shelf-config` is absent, using the existing fallback behavior.
- **SC-004**: The `.shelf-config` file is readable by `cat` and parseable by `grep` — no specialized tooling required.

## Assumptions

- The Obsidian MCP server is available and functional when `/shelf-create` is run (if not, the skill already handles this gracefully and `.shelf-config` is simply not written).
- One repo maps to one Obsidian project — multi-project tracking is out of scope.
- The shelf plugin is already installed and functional in the consumer project.
- Users who set up projects before this feature can manually create `.shelf-config` or re-run `/shelf-create`.
