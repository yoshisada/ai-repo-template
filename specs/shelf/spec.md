# Feature Specification: Shelf — Obsidian Project Dashboard Plugin

**Feature Branch**: `build/shelf-20260403`
**Created**: 2026-04-03
**Status**: Draft
**Input**: User description: "Shelf — Claude Code plugin with 6 skills (shelf-create, shelf-update, shelf-sync, shelf-feedback, shelf-status, shelf-release) that syncs project state to an Obsidian vault via MCP. See docs/features/2026-04-03-shelf/PRD.md and plugin-shelf/docs/PRD.md for full requirements."

## User Scenarios & Testing

### User Story 1 - Scaffold New Project in Obsidian (Priority: P1)

As a developer starting a new project, I want to run `/shelf-create` so that Obsidian immediately has a complete project dashboard with the right directory structure, auto-detected tech stack tags, and populated frontmatter — without me having to create any of it manually.

**Why this priority**: This is the foundational command. No other shelf command works until a project exists in Obsidian. Every user must run this first.

**Independent Test**: Run `/shelf-create` in a repo with a `package.json` and verify the full Obsidian structure is created via MCP with correct frontmatter and auto-detected tags.

**Acceptance Scenarios**:

1. **Given** a git repo named `my-app` with no existing Obsidian project, **When** the user runs `/shelf-create`, **Then** the following are created via MCP: `projects/my-app/my-app.md` (dashboard), `projects/my-app/docs/about.md`, and empty directories for `progress/`, `releases/`, `issues/`, `decisions/`
2. **Given** a repo with `package.json` containing `react` and `typescript` dependencies, **When** the user runs `/shelf-create`, **Then** the dashboard frontmatter `tags` array includes `language/typescript`, `framework/react`
3. **Given** a repo whose project slug already exists in Obsidian, **When** the user runs `/shelf-create`, **Then** the skill warns "Project already exists" and aborts without overwriting
4. **Given** the user passes `--tags "product/claude-code, infra/docker"`, **When** `/shelf-create` runs, **Then** those tags are merged with auto-detected tags in the frontmatter
5. **Given** the MCP server is unreachable, **When** the user runs `/shelf-create`, **Then** the skill prints a warning ("MCP server unavailable — cannot create project") and exits without error

---

### User Story 2 - Push Progress Update (Priority: P1)

As a developer finishing a work session, I want to run `/shelf-update` so that my progress, status change, next steps, and any decisions are recorded in Obsidian automatically — giving me a persistent history without manual note-taking.

**Why this priority**: This is the most frequently used command. Every session should end with a progress update. It drives the core value of the plugin.

**Independent Test**: Run `/shelf-update --summary "Added auth" --status "in-progress" --next-step "Add tests"` and verify a progress entry is appended and dashboard frontmatter is updated in Obsidian.

**Acceptance Scenarios**:

1. **Given** a project exists in Obsidian, **When** the user runs `/shelf-update --summary "Implemented login" --status "in-progress" --next-step "Add tests"`, **Then** a timestamped progress entry is appended to `progress/2026-04.md` and dashboard frontmatter is updated with the new status, next_step, and last_updated
2. **Given** `progress/2026-04.md` does not exist yet, **When** `/shelf-update` runs in April 2026, **Then** the file is created via MCP before the entry is appended
3. **Given** the user passes `--decision "Chose JWT over sessions"`, **When** `/shelf-update` runs, **Then** a decision record is created at `decisions/2026-04-03-chose-jwt-over-sessions.md` and the progress entry links to it
4. **Given** the user provides human-needed items, **When** `/shelf-update` runs, **Then** the `## Human Needed` section of the dashboard is updated with new `- [ ]` items and existing `- [x]` items are preserved
5. **Given** no arguments are provided, **When** the user runs `/shelf-update`, **Then** the skill analyzes recent git log and conversation context and prompts the user for a summary

---

### User Story 3 - Sync Issues from GitHub and Backlog (Priority: P1)

As a developer, I want to run `/shelf-sync` so that all open GitHub issues and `.kiln/issues/` backlog items are reflected as Obsidian issue notes — keeping my project dashboard complete without checking multiple sources.

**Why this priority**: Issue visibility is a core dashboard feature. Without sync, the Obsidian project view is incomplete.

**Independent Test**: Create a GitHub issue, add a `.kiln/issues/` file, run `/shelf-sync`, and verify corresponding Obsidian issue notes exist with correct frontmatter.

**Acceptance Scenarios**:

1. **Given** 3 open GitHub issues and 2 files in `.kiln/issues/`, **When** the user runs `/shelf-sync`, **Then** 5 Obsidian issue notes are created in `issues/` with frontmatter including `type: issue`, `status`, `severity`, `source`, and `last_synced`
2. **Given** a previously synced issue that has not changed since `last_synced`, **When** `/shelf-sync` runs, **Then** that issue is skipped (not re-written)
3. **Given** a GitHub issue that was open at last sync but is now closed, **When** `/shelf-sync` runs, **Then** the corresponding Obsidian note is updated to `status: closed`
4. **Given** a GitHub issue titled "Fix sidebar overflow on mobile", **When** `/shelf-sync` creates the note, **Then** the filename is `fix-sidebar-overflow-on-mobile.md` (human-readable slug)
5. **Given** the MCP server is unreachable, **When** the user runs `/shelf-sync`, **Then** the skill prints a warning and exits gracefully

---

### User Story 4 - Read and Process Feedback (Priority: P2)

As a developer starting a session, I want to run `/shelf-feedback` so that any notes I left in Obsidian's Feedback section are surfaced to Claude with suggested actions — and then archived so they don't repeat.

**Why this priority**: Feedback is the key "Obsidian to Claude" channel. Important but less frequent than progress updates.

**Independent Test**: Add text under `## Feedback` in the Obsidian dashboard, run `/shelf-feedback`, and verify items are displayed, acted on, and moved to `## Feedback Log`.

**Acceptance Scenarios**:

1. **Given** the project dashboard has `## Feedback` with items "- Fix sidebar before merge" and "- Consider dark mode", **When** the user runs `/shelf-feedback`, **Then** both items are displayed with suggested actions (e.g., "Fix request: run /fix for sidebar issue")
2. **Given** feedback items have been displayed, **When** processing completes, **Then** the items are moved to `## Feedback Log` with a `[2026-04-03 14:30]` timestamp prefix
3. **Given** no project file exists for the current repo, **When** the user runs `/shelf-feedback`, **Then** the skill suggests "No project found — run /shelf-create first"
4. **Given** the `## Feedback` section is empty, **When** the user runs `/shelf-feedback`, **Then** the skill reports "No feedback" and continues without error

---

### User Story 5 - Quick Project Status View (Priority: P2)

As a developer, I want to run `/shelf-status` to see a formatted summary of my project's current state — status, next step, latest progress, open issue count, and human-needed items — without modifying anything.

**Why this priority**: Read-only view is low risk and high utility, but depends on other commands having populated the data.

**Independent Test**: After running `/shelf-create` and `/shelf-update`, run `/shelf-status` and verify the output shows status, next_step, last_updated, latest progress entry, issue count, and human-needed items.

**Acceptance Scenarios**:

1. **Given** a project exists with status "in-progress", next_step "Add tests", and 3 open issues, **When** the user runs `/shelf-status`, **Then** the output displays all frontmatter fields, the most recent progress entry, "3 open issues", and any Human Needed items
2. **Given** no project file exists for the current repo, **When** the user runs `/shelf-status`, **Then** the skill suggests "No project found — run /shelf-create first"
3. **Given** no progress entries exist yet, **When** the user runs `/shelf-status`, **Then** the progress section shows "No progress entries yet" instead of an error

---

### User Story 6 - Record a Release (Priority: P2)

As a developer publishing a version, I want to run `/shelf-release` so that a release note with auto-generated changelog is created in Obsidian and a progress entry records the release event.

**Why this priority**: Releases are less frequent than updates but are the capstone event that ties together progress history.

**Independent Test**: Tag a release, run `/shelf-release`, and verify a release note is created with changelog from git log and a progress entry is appended.

**Acceptance Scenarios**:

1. **Given** the `VERSION` file contains `1.2.0.5`, **When** the user runs `/shelf-release`, **Then** a release note is created at `releases/v1.2.0.5.md` with frontmatter `type: release`, `version: 1.2.0.5`, `date: 2026-04-03`, and `summary`
2. **Given** there are 5 commits since the last release tag, **When** `/shelf-release` runs, **Then** the changelog section lists those 5 commits with messages and any merged PR numbers
3. **Given** a release note for version `1.2.0.5` already exists in Obsidian, **When** the user runs `/shelf-release`, **Then** the skill warns "Release note already exists for v1.2.0.5" and aborts
4. **Given** the user passes `--summary "Bug fixes and performance"`, **When** `/shelf-release` runs, **Then** that summary is used in the frontmatter and progress entry
5. **Given** no `--summary` is provided, **When** `/shelf-release` runs, **Then** the skill prompts the user for a one-liner

---

### Edge Cases

- What happens when the MCP server becomes unavailable mid-command (e.g., after reading but before writing)? The skill prints a warning for the failed write and reports partial completion.
- What happens when `gh` CLI is not authenticated? `/shelf-sync` warns "GitHub CLI not authenticated — skipping GitHub issues" and continues with `.kiln/issues/` only.
- What happens when the progress file is very large (months of entries)? Entries are appended — the skill reads only the file metadata and appends, never loads the entire file into context unnecessarily.
- What happens when two shelf commands run concurrently? Not supported — commands are sequential by nature (user invokes one at a time). No locking mechanism needed.
- What happens when the vault base path is misconfigured? MCP tools will return errors; the skill catches them and reports "Check your Obsidian MCP configuration".

## Requirements

### Functional Requirements

#### /shelf-create

- **FR-001**: Skill MUST create the full directory structure via MCP: `{slug}/`, `docs/`, `progress/`, `releases/`, `issues/`, `decisions/`
- **FR-002**: Skill MUST generate `{slug}.md` dashboard with populated frontmatter (`type: project`, `status: idea`, `repo`, `tags`, `next_step`, `last_updated`)
- **FR-003**: Skill MUST generate `docs/about.md` with repo description, tech stack, and architecture placeholders
- **FR-004**: Skill MUST derive project slug from the current git repo name (or accept as argument)
- **FR-005**: Skill MUST check if project already exists in Obsidian before creating and abort with warning if duplicate
- **FR-006**: All writes MUST go through Obsidian MCP tools — no direct filesystem access
- **FR-029**: Skill MUST detect tech stack from repo files (package.json, Cargo.toml, pyproject.toml, etc.) and populate `tags` with namespaced values (`language/`, `framework/`, `product/`, `infra/`)
- **FR-030**: Skill MUST accept `--tags` argument to manually specify additional tags (merged with auto-detected ones)

#### /shelf-update

- **FR-007**: Skill MUST append a progress entry to `progress/YYYY-MM.md` with date, summary, key outcomes, and links
- **FR-008**: Skill MUST create the monthly progress file if it doesn't exist
- **FR-009**: Skill MUST update dashboard frontmatter: `status`, `next_step`, `last_updated`
- **FR-010**: Skill MUST update `## Human Needed` section with `- [ ]` items; preserve existing `- [x]` items
- **FR-011**: Skill MUST accept arguments for summary, status, and next_step — or prompt interactively
- **FR-012**: Skill MUST read current dashboard state before updating to avoid clobbering
- **FR-031**: Skill MUST create a decision record in `decisions/YYYY-MM-DD-{slug}.md` if a decision was made
- **FR-032**: Skill MUST accept `--decision` flag or detect decisions from conversation context
- **FR-033**: Skill MUST reference the decision in the progress entry

#### /shelf-sync

- **FR-013**: Skill MUST read open GitHub issues via `gh issue list` and create/update Obsidian issue notes
- **FR-014**: Skill MUST read `.kiln/issues/` directory and create/update Obsidian issue notes
- **FR-015**: Issue notes MUST include frontmatter: `type: issue`, `status`, `severity`, `source`, `last_synced`
- **FR-016**: Closed GitHub issues MUST update the Obsidian note to `status: closed`
- **FR-017**: Skill MUST skip issues that haven't changed since last sync
- **FR-018**: Skill MUST generate human-readable slug filenames from issue titles

#### /shelf-feedback

- **FR-019**: Skill MUST read the project dashboard and extract `## Feedback` section
- **FR-020**: Skill MUST display feedback items and suggest actions
- **FR-021**: Skill MUST move processed items to `## Feedback Log` with timestamp
- **FR-022**: Skill MUST suggest `/shelf-create` if no project file exists
- **FR-023**: Skill MUST report "no feedback" if section is empty

#### /shelf-status

- **FR-024**: Skill MUST read dashboard frontmatter and display: status, next_step, last_updated, blockers
- **FR-025**: Skill MUST read and display the most recent progress entry
- **FR-026**: Skill MUST count open issues and display summary
- **FR-027**: Skill MUST display `## Human Needed` items if any exist
- **FR-028**: Skill MUST suggest `/shelf-create` if no project file exists

#### /shelf-release

- **FR-034**: Skill MUST create release note at `releases/v{version}.md` with frontmatter: `type: release`, `version`, `date`, `summary`
- **FR-035**: Skill MUST auto-detect version from `VERSION`, `package.json`, or git tags — or accept as argument
- **FR-036**: Skill MUST generate changelog from git log between previous release tag and current
- **FR-037**: Skill MUST accept `--summary` flag or prompt for one-liner
- **FR-038**: Skill MUST check if release note already exists and abort if duplicate
- **FR-039**: Skill MUST append a progress entry noting the release

#### Cross-Cutting

- **NFR-001**: All vault writes MUST go through Obsidian MCP tools — no direct filesystem access
- **NFR-002**: Plugin MUST work with any Obsidian MCP server (not hardcoded to a vault path)
- **NFR-003**: The `projects/` base path MUST be configurable (default: `@second-brain/projects`)
- **NFR-004**: Plugin MUST degrade gracefully if MCP server is unavailable — warning, not error
- **NFR-005**: No credentials or secrets stored in Obsidian notes

### Key Entities

- **Project Dashboard**: The central `{slug}.md` file with YAML frontmatter (type, status, repo, tags, next_step, last_updated) and markdown sections (Human Needed, Feedback, Feedback Log)
- **Progress Entry**: Timestamped append-only record in monthly files (`progress/YYYY-MM.md`) with date, summary, outcomes, and links
- **Issue Note**: Per-issue file in `issues/` with frontmatter tracking status, severity, source, and last_synced timestamp
- **Decision Record**: Immutable per-decision file in `decisions/` with context, options, decision, and rationale
- **Release Note**: Immutable per-version file in `releases/` with frontmatter and auto-generated changelog
- **About Doc**: Overview file in `docs/about.md` with repo description, tech stack, and architecture

## Success Criteria

### Measurable Outcomes

- **SC-001**: `/shelf-create` scaffolds the complete Obsidian project structure (6 directories + dashboard + about.md) in a single invocation
- **SC-002**: `/shelf-update` appends a progress entry and updates dashboard frontmatter without clobbering existing content
- **SC-003**: `/shelf-sync` creates issue notes for 100% of open GitHub issues and `.kiln/issues/` items
- **SC-004**: `/shelf-feedback` reads, displays, and archives all feedback items from the dashboard
- **SC-005**: `/shelf-status` displays a complete project summary (status, progress, issues, human-needed) without modifying anything
- **SC-006**: `/shelf-release` creates a release note with auto-generated changelog from git history
- **SC-007**: All 6 commands degrade gracefully (warning, not error) when MCP server is unreachable

## Assumptions

- The user has `obsidian-mcp` server running and configured in Claude Code's MCP settings
- The MCP server has write access scoped to the `projects/` directory (or configured base path)
- Obsidian has the Dataview plugin installed for dashboard queries
- The user has `gh` CLI authenticated for issue sync
- One Obsidian vault per user (not multiple vaults)
- Project slug maps 1:1 to repo name
- This is a Claude Code plugin — skills are Markdown SKILL.md files, no compiled code
- No test suite for the plugin itself (same as kiln pattern)
