# Feature PRD: Shelf — Obsidian Project Dashboard Plugin

## Parent Product

[ai-repo-template](../../PRD.md) — Multi-plugin repo for Claude Code development tooling. Shelf is a new plugin (`plugin-shelf/`) alongside `plugin-kiln` and `plugin-wheel`.

## Feature Overview

Shelf is a Claude Code plugin (`@yoshisada/shelf`) that keeps an Obsidian vault in sync with code project state. It pushes progress updates, syncs issues, reads feedback, records decisions and releases — turning Obsidian into a live project dashboard without manual effort.

Six skills, no agents, no hooks (hook integration with kiln deferred).

## Problem / Motivation

- Pipeline output (status, progress, issues, blockers) is ephemeral — lives in git history and terminal output
- No single place to see "what's the current state of all my projects?"
- Leaving feedback for Claude between sessions requires opening a terminal
- GitHub issues and `.kiln/issues/` backlog items aren't reflected in the knowledge base
- Progress history is lost unless manually documented
- Decisions made during sessions have no structured record

## Goals

- Automatically update Obsidian project files after work sessions
- Read and process feedback left by the user in Obsidian at session start
- Sync GitHub issues and `.kiln/issues/` into Obsidian issue notes
- Record decisions alongside progress entries
- Record releases with auto-generated changelogs
- Support multiple projects in a single vault with a consistent structure

## Non-Goals

- Replacing GitHub Issues as the canonical issue tracker
- Real-time sync (updates happen at command invocation, not continuously)
- Multi-user collaboration (single developer, multiple AI agents)
- Obsidian community plugin development (this is a Claude Code plugin)
- Hook integration with kiln (deferred — will be added later)
- CLAUDE.md auto-triggers for feedback ingestion (deferred)
- Modifying any other plugins (kiln, wheel) in this repo

## Target Users

Solo developer using Claude Code with Obsidian as their knowledge base, who has the `obsidian-mcp` server configured with scoped write access to the vault's `projects/` directory.

## Core User Stories

- As a developer, I want to open Obsidian and see the current status of all my projects without checking GitHub or running commands
- As a developer, I want to leave feedback in Obsidian ("fix the sidebar before merging") and have Claude act on it next session
- As a developer, I want pipeline results automatically logged so I have a progress history without manual effort
- As a developer, I want GitHub issues reflected in my Obsidian project dashboard so I don't have to check two places
- As a developer, I want to scaffold a new project's Obsidian structure with one command
- As a developer, I want decisions recorded with context and rationale so future-me knows why things were done
- As a developer, I want release notes auto-generated from git history when I ship a version

## Functional Requirements

### `/shelf-create` — Scaffold a New Project

| ID | Requirement |
|----|-------------|
| FR-001 | Create the full directory structure: `{slug}/`, `docs/`, `progress/`, `releases/`, `issues/`, `decisions/` |
| FR-002 | Generate `{slug}.md` dashboard from the project template with populated frontmatter (`type: project`, `status: idea`, `repo`, `tags`, `next_step`, `last_updated`) |
| FR-003 | Generate `docs/about.md` with repo description, tech stack placeholder, and architecture placeholder |
| FR-004 | Derive project slug from the current git repo name (or accept as argument) |
| FR-005 | Check if project already exists in Obsidian before creating — warn and abort if duplicate |
| FR-006 | All writes go through Obsidian MCP tools — no direct filesystem access |
| FR-029 | Detect tech stack from repo files (package.json, Cargo.toml, pyproject.toml, etc.) and populate `tags` with namespaced values (`language/`, `framework/`, `product/`, `infra/`) |
| FR-030 | Accept `--tags` argument to manually specify additional tags (merged with auto-detected ones) |

### `/shelf-update` — Push Progress Update

| ID | Requirement |
|----|-------------|
| FR-007 | Append a progress entry to `progress/YYYY-MM.md` with: date, summary, key outcomes, links (PR, commit, etc.) |
| FR-008 | Create the monthly progress file if it doesn't exist yet |
| FR-009 | Update dashboard frontmatter: `status`, `next_step`, `last_updated` |
| FR-010 | Update `## Human Needed` section with checkbox items (`- [ ]`) requiring user action. Completed items (`- [x]`) are preserved but not re-added. |
| FR-011 | Accept arguments for summary, status, and next_step — or prompt interactively if none given |
| FR-012 | Read current dashboard state before updating to avoid clobbering existing content |
| FR-031 | If a decision was made during the session, create a decision record in `decisions/YYYY-MM-DD-{slug}.md` with context, options considered, decision, and rationale |
| FR-032 | Accept `--decision` flag to explicitly indicate a decision was made (or detect from conversation context) |
| FR-033 | Reference the decision in the progress entry so the two are linked |

### `/shelf-sync` — Sync Issues from GitHub and Backlog

| ID | Requirement |
|----|-------------|
| FR-013 | Read open GitHub issues via `gh issue list` and create/update corresponding Obsidian issue notes in `issues/` |
| FR-014 | Read `.kiln/issues/` directory and create/update corresponding Obsidian issue notes |
| FR-015 | Issue notes include frontmatter: `type: issue`, `status`, `severity`, `source` (GitHub #N or backlog path), `last_synced` |
| FR-016 | Closed GitHub issues update the corresponding Obsidian note to `status: closed` |
| FR-017 | Skip issues that haven't changed since last sync (compare `last_synced` timestamp) |
| FR-018 | Generate a human-readable slug for each issue filename from the issue title |

### `/shelf-feedback` — Read and Process Feedback

| ID | Requirement |
|----|-------------|
| FR-019 | Read the project dashboard from Obsidian and extract the `## Feedback` section |
| FR-020 | If feedback items exist, display them and suggest actions (fix requests, scope changes, notes) |
| FR-021 | After processing, move feedback items to `## Feedback Log` with timestamp |
| FR-022 | If no project file exists for the current repo, suggest running `/shelf-create` |
| FR-023 | If no feedback exists, report "no feedback" and continue |

### `/shelf-status` — Quick Project Status View

| ID | Requirement |
|----|-------------|
| FR-024 | Read dashboard frontmatter and display: status, next_step, last_updated, blockers |
| FR-025 | Read the most recent progress entry (latest in `progress/YYYY-MM.md`) and display it |
| FR-026 | Count open issues from `issues/` directory and display summary |
| FR-027 | Display `## Human Needed` items if any exist |
| FR-028 | If no project file exists, suggest `/shelf-create` |

### `/shelf-release` — Record a Release

| ID | Requirement |
|----|-------------|
| FR-034 | Create a release note at `releases/v{version}.md` with frontmatter: `type: release`, `version`, `date`, `summary` |
| FR-035 | Auto-detect version from `VERSION` file, `package.json`, or git tags — or accept as argument |
| FR-036 | Generate changelog from git log between the previous release tag and current (commits, PRs merged) |
| FR-037 | Accept `--summary` flag for a human-readable one-liner, or prompt if not given |
| FR-038 | Check if release note already exists for this version — warn and abort if duplicate |
| FR-039 | Append a progress entry noting the release was published |

### Cross-Cutting

| ID | Requirement |
|----|-------------|
| NFR-001 | All vault writes go through Obsidian MCP tools — no direct filesystem access |
| NFR-002 | Plugin must work with any Obsidian MCP server (not hardcoded to a specific vault path) |
| NFR-003 | The `projects/` base path should be configurable (default: `@second-brain/projects`) |
| NFR-004 | Plugin must degrade gracefully if MCP server is unavailable — warning, not error |
| NFR-005 | No credentials or secrets stored in Obsidian notes |

## Absolute Musts

1. **Tech stack**: Markdown skills + Bash (same pattern as kiln/wheel plugins), Obsidian MCP for vault access, `gh` CLI for GitHub issue sync
2. **No other plugin modifications**: Shelf is standalone — no changes to `plugin-kiln/` or `plugin-wheel/`
3. **MCP-only vault access**: All Obsidian writes via `mcp__obsidian-projects__*` tools, never direct filesystem
4. **Graceful degradation**: Every command must handle MCP server unavailability with a warning, not a crash
5. **Tags use Obsidian's native `#tag` system**: Namespaced tags (`language/`, `framework/`, `product/`, `infra/`) stored in frontmatter, rendered as clickable `#tags`

## Tech Stack

Inherited from repo pattern — no additions needed:

- **Skills**: Markdown SKILL.md files (same as kiln)
- **Shell**: Bash for any scripting within skills
- **MCP**: `obsidian-mcp` server tools (`list_files`, `read_file`, `create_file`, `update_file`, `search_files`)
- **CLI**: `gh` (GitHub CLI) for issue sync, `git` for repo metadata and changelog generation
- **Package**: `@yoshisada/shelf` on npm (same publishing pattern as `@yoshisada/kiln`)

## Impact on Existing Features

**None.** Shelf is a standalone plugin in `plugin-shelf/`. It does not modify, depend on, or interact with:
- `plugin-kiln/` — no changes
- `plugin-wheel/` — no changes
- `CLAUDE.md` — no changes (CLAUDE.md integration deferred)
- Hooks — no new hooks (kiln hook integration deferred)

The only shared concern is the `VERSION` file at repo root (used by version-increment hook), which shelf-release reads but does not write.

## Success Metrics

| Metric | Target | Timeframe |
|--------|--------|-----------|
| `/shelf-create` scaffolds complete project structure | All 6 directories + dashboard + about.md created | Per invocation |
| `/shelf-update` records session work | Progress entry appended + frontmatter updated | Per invocation |
| `/shelf-sync` reflects all open GitHub issues | 100% of open issues have corresponding Obsidian notes | Per invocation |
| `/shelf-feedback` processes user notes | Feedback moved to log, actions surfaced | Per invocation |
| `/shelf-status` provides useful summary | Status, progress, issues, human-needed displayed | Per invocation |
| `/shelf-release` generates release notes | Changelog from git history + release note created | Per invocation |
| Graceful degradation | Warning (not error) when MCP unavailable | Always |

## Risks / Unknowns

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| MCP server downtime blocks all vault writes | Medium | High | Graceful degradation — warn and skip, don't crash |
| Large projects with many issues generate excessive Obsidian files | Low | Medium | Pagination or archival strategy (future work) |
| Obsidian sync latency — updates may not appear on mobile for 30-60s | Medium | Low | Acceptable for async workflow |
| Concurrent edits — user edits Obsidian while shelf is writing | Low | Medium | Read-before-write pattern (FR-012), but no locking mechanism |
| MCP tool names may differ across Obsidian MCP server versions | Low | High | Document required MCP tools; test against current server |

## Assumptions

- The user has `obsidian-mcp` server running and configured in Claude Code's MCP settings
- The MCP server has write access scoped to the `projects/` directory (or configured base path)
- Obsidian has the Dataview plugin installed for dashboard queries
- The user has `gh` CLI authenticated for issue sync
- One Obsidian vault per user (not multiple vaults)
- Project slug maps 1:1 to repo name

## Open Questions

- Should shelf also track non-code projects (design docs, research, learning)?
- How should conflicts be handled if the user edits a file in Obsidian while shelf is updating it?
- Should there be a `/shelf-dashboard` that generates a cross-project summary note?
