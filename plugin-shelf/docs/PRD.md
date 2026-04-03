# PRD: Shelf — Obsidian Project Dashboard Plugin

**Date**: 2026-04-03
**Status**: Draft
**Author**: Ryan Suematsu
**Package**: `@yoshisada/shelf`

## Background

Claude Code pipelines produce valuable project state — progress logs, status changes, issues, blockers, decisions — but this information lives scattered across git commits, GitHub issues, and terminal output. There's no persistent, human-readable dashboard that shows the current state of all projects at a glance.

Obsidian is already the central knowledge base. An MCP server (`obsidian-mcp`) already provides scoped read/write vault access. The missing piece is a Claude Code plugin that automatically pushes project updates to Obsidian after every significant work session.

## Problem

- After a pipeline run, project status only exists in git history and terminal output
- No single place to see "what's the current state of all my projects?"
- Feedback requires opening a terminal — no way to leave notes for Claude from Obsidian
- Issues tracked in GitHub and `.kiln/issues/` are not reflected in the project dashboard
- Progress history is lost unless manually documented

## Goals

- Automatically update Obsidian project files after pipeline runs
- Read and process feedback left by the user in Obsidian at session start
- Sync GitHub issues and `.kiln/issues/` into Obsidian issue notes
- Provide manual update and scaffolding commands
- Support multiple projects in a single vault with a consistent structure

## Non-Goals

- Replacing GitHub Issues as the canonical issue tracker
- Real-time sync (updates happen at command invocation, not continuously)
- Multi-user collaboration (single developer, multiple AI agents)
- Obsidian community plugin development (this is a Claude Code plugin)
- Hook integration with kiln (deferred — will be added later)

## Target User

Solo developer using Claude Code with Obsidian as their knowledge base, who has the `obsidian-mcp` server configured with write access.

## Tags

Projects use Obsidian's native `#tag` system with namespaced tags to categorize their tech stack. Tags are stored in the dashboard's frontmatter `tags` array (Obsidian automatically maps these to `#` tags for search, graph view, and tag pane).

**Frontmatter format**:
```yaml
tags:
  - language/typescript
  - framework/react
  - product/claude-code
  - infra/docker
```

These render as `#language/typescript`, `#framework/react`, etc. in Obsidian and are searchable, clickable, and visible in the tag pane as a nested hierarchy.

**Namespaces**:

| Namespace | Purpose | Examples |
|-----------|---------|----------|
| `language/` | Programming languages | `#language/typescript`, `#language/python`, `#language/bash` |
| `framework/` | Frameworks and libraries | `#framework/react`, `#framework/express`, `#framework/playwright` |
| `product/` | Products and platforms | `#product/claude-code`, `#product/obsidian`, `#product/github` |
| `infra/` | Infrastructure and tooling | `#infra/docker`, `#infra/github-actions`, `#infra/npm` |

Tags enable cross-project queries in Obsidian via Dataview:
```dataview
TABLE status, next_step
FROM #language/typescript
```

Or filter by multiple tags:
```dataview
TABLE status, next_step
FROM #product/claude-code AND #language/typescript
```

## Obsidian Vault Structure

```
projects/
  {project-slug}/
    {project-slug}.md         ← dashboard (frontmatter + tags + dataview queries)
    docs/
      about.md                ← overview, architecture, tech stack
      *.md                    ← additional docs, design notes
    progress/
      YYYY-MM.md              ← monthly progress log (append-only)
    releases/
      vX.Y.Z.md              ← release notes per version
    issues/
      {slug}.md               ← one file per issue (frontmatter: status, severity, source)
    decisions/
      YYYY-MM-DD-{slug}.md   ← decision records
  templates/
    project-template.md       ← scaffolding template
```

## Artifact Types

Each subdirectory serves a distinct purpose. Shelf commands must classify information correctly when writing to Obsidian.

| Type | Question it answers | Format | Mutability |
|------|-------------------|--------|------------|
| **Progress** (`progress/`) | What happened? | Monthly append-only log (`YYYY-MM.md`) | Append only |
| **Decision** (`decisions/`) | Why was this chosen? | One file per decision (`YYYY-MM-DD-{slug}.md`) | Immutable |
| **Issue** (`issues/`) | What's wrong or needed? | One file per issue (`{slug}.md`) | Updated (open → closed) |
| **Doc** (`docs/`) | What is this thing? | One file per topic | Updated as things change |
| **Release** (`releases/`) | What shipped? | One file per version (`vX.Y.Z.md`) | Immutable |

**Rule of thumb**: If it records *what happened* → progress. If it explains *why* → decision. If it needs *action* → issue. If it describes *what something is* → doc. If it marks *what shipped* → release.

Full artifact type guide with edge cases: see `docs/artifact-types.md` in the Obsidian project.

## Plugin Structure

```
plugin-shelf/
  .claude-plugin/
    plugin.json               ← plugin manifest
  docs/
    PRD.md                    ← this file
  skills/
    shelf-create/
      SKILL.md                ← scaffold new project in Obsidian
    shelf-update/
      SKILL.md                ← push progress, status, next steps
    shelf-sync/
      SKILL.md                ← GitHub/backlog → Obsidian issue sync
    shelf-feedback/
      SKILL.md                ← read and process feedback from Obsidian
    shelf-status/
      SKILL.md                ← quick project status view (read-only)
    shelf-release/
      SKILL.md                ← record a release with changelog
  agents/                     ← (none initially)
  hooks/                      ← (deferred — kiln integration later)
```

---

## Commands

### 1. `/shelf-create` — Scaffold a New Project

**Purpose**: Create the full Obsidian project structure from a template so a new repo has a dashboard from day one.

**Functional Requirements**:

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

**Inputs**: Optional project name (defaults to current repo name)
**Outputs**: Fully scaffolded project directory in Obsidian vault

**Plan**:
1. Resolve project slug from arg or `git remote` origin
2. Read `projects/` directory via `mcp__obsidian-projects__list_files` to check for duplicates
3. Auto-detect tech stack by scanning repo files (package.json → `language/typescript`, `framework/react`; Cargo.toml → `language/rust`; etc.) and merge with any `--tags` argument
4. Create each directory and file via `mcp__obsidian-projects__create_file`
5. Populate dashboard frontmatter from git metadata (repo URL, description) and detected tags
6. Confirm creation to user with link to the project file

---

### 2. `/shelf-update` — Push Progress Update

**Purpose**: Record what just happened in a work session — progress entry, status change, next steps, human-needed items, and any decisions made.

**Functional Requirements**:

| ID | Requirement |
|----|-------------|
| FR-007 | Append a progress entry to `progress/YYYY-MM.md` with: date, summary, key outcomes, links (PR, commit, etc.) |
| FR-008 | Create the monthly progress file if it doesn't exist yet |
| FR-009 | Update dashboard frontmatter: `status`, `next_step`, `last_updated` |
| FR-010 | Update `## Human Needed` section with checkbox items (`- [ ]`) requiring user action. Completed items (`- [x]`) are preserved but not re-added. |
| FR-011 | Accept arguments for summary, status, and next_step — or prompt interactively if none given |
| FR-012 | Read current dashboard state before updating to avoid clobbering existing content |
| FR-031 | If a decision was made during the session, create a decision record in `decisions/YYYY-MM-DD-{slug}.md` with context, options considered, decision, and rationale |
| FR-032 | Accept `--decision` flag to explicitly indicate a decision was made (or detect from conversation context — e.g. "we chose X over Y") |
| FR-033 | Reference the decision in the progress entry so the two are linked |

**Inputs**: Optional `--summary`, `--status`, `--next-step`, `--decision` flags (or interactive)
**Outputs**: Updated dashboard frontmatter + new progress entry + optional decision record in Obsidian

**Plan**:
1. Resolve project slug from current repo
2. Read current dashboard file via MCP to get existing frontmatter and Human Needed section
3. If no args provided, analyze recent git log and conversation context; ask user for summary
4. Read or create `progress/YYYY-MM.md`
5. Append timestamped progress entry
6. If a decision was made, create `decisions/YYYY-MM-DD-{slug}.md` and reference it in the progress entry
7. Update dashboard frontmatter via MCP (`update_file`)
8. Update Human Needed section if applicable
9. Confirm update to user

---

### 3. `/shelf-sync` — Sync Issues from GitHub and Backlog

**Purpose**: Pull open GitHub issues and `.kiln/issues/` backlog items into Obsidian issue notes so the dashboard reflects all known work.

**Functional Requirements**:

| ID | Requirement |
|----|-------------|
| FR-013 | Read open GitHub issues via `gh issue list` and create/update corresponding Obsidian issue notes in `issues/` |
| FR-014 | Read `.kiln/issues/` directory and create/update corresponding Obsidian issue notes |
| FR-015 | Issue notes include frontmatter: `type: issue`, `status`, `severity`, `source` (GitHub #N or backlog path), `last_synced` |
| FR-016 | Closed GitHub issues update the corresponding Obsidian note to `status: closed` |
| FR-017 | Skip issues that haven't changed since last sync (compare `last_synced` timestamp) |
| FR-018 | Generate a human-readable slug for each issue filename from the issue title |

**Inputs**: None (syncs all sources automatically)
**Outputs**: Created/updated issue notes in Obsidian, sync summary printed to user

**Plan**:
1. Resolve project slug from current repo
2. Run `gh issue list --json number,title,state,labels,body,updatedAt` to get GitHub issues
3. Read `.kiln/issues/` directory for backlog items
4. Read existing Obsidian `issues/` directory to find already-synced notes
5. For each issue: create new note or update existing (compare timestamps to skip unchanged)
6. Mark closed issues as `status: closed`
7. Print sync summary: N created, N updated, N closed, N unchanged

---

### 4. `/shelf-feedback` — Read and Process Feedback

**Purpose**: At session start, check if the user left feedback in the Obsidian project dashboard and surface it to Claude for action.

**Functional Requirements**:

| ID | Requirement |
|----|-------------|
| FR-019 | Read the project dashboard from Obsidian and extract the `## Feedback` section |
| FR-020 | If feedback items exist, display them and suggest actions (fix requests, scope changes, notes) |
| FR-021 | After processing, move feedback items to `## Feedback Log` with timestamp |
| FR-022 | If no project file exists for the current repo, suggest running `/shelf-create` |
| FR-023 | If no feedback exists, report "no feedback" and continue |

**Inputs**: None
**Outputs**: Feedback items displayed to user, processed items archived to Feedback Log

**Plan**:
1. Resolve project slug from current repo
2. Read dashboard file via MCP
3. Parse `## Feedback` section (everything between `## Feedback` and the next `##`)
4. If empty, report "no feedback" and return
5. Display feedback items to user with suggested actions
6. Move items to `## Feedback Log` with `[YYYY-MM-DD HH:MM]` prefix
7. Update file via MCP

---

### 5. `/shelf-status` — Quick Project Status View

**Purpose**: Read-only view of the current project state from Obsidian — status, next step, recent progress, open issues, human-needed items. No writes.

**Functional Requirements**:

| ID | Requirement |
|----|-------------|
| FR-024 | Read dashboard frontmatter and display: status, next_step, last_updated, blockers |
| FR-025 | Read the most recent progress entry (latest in `progress/YYYY-MM.md`) and display it |
| FR-026 | Count open issues from `issues/` directory and display summary |
| FR-027 | Display `## Human Needed` items if any exist |
| FR-028 | If no project file exists, suggest `/shelf-create` |

**Inputs**: None
**Outputs**: Formatted status summary printed to user

**Plan**:
1. Resolve project slug from current repo
2. Read dashboard file via MCP — extract frontmatter and Human Needed section
3. List and read latest progress file
4. List issues directory and count by status
5. Format and display summary

---

### 6. `/shelf-release` — Record a Release

**Purpose**: Create a release note in Obsidian when a version is published. Captures what shipped, linking changes to the version number.

**Functional Requirements**:

| ID | Requirement |
|----|-------------|
| FR-034 | Create a release note at `releases/v{version}.md` with frontmatter: `type: release`, `version`, `date`, `summary` |
| FR-035 | Auto-detect version from `VERSION` file, `package.json`, or git tags — or accept as argument |
| FR-036 | Generate changelog from git log between the previous release tag and current (commits, PRs merged) |
| FR-037 | Accept `--summary` flag for a human-readable one-liner, or prompt if not given |
| FR-038 | Check if release note already exists for this version — warn and abort if duplicate |
| FR-039 | Append a progress entry noting the release was published |

**Inputs**: Optional `--version`, `--summary` flags
**Outputs**: Release note in Obsidian + progress entry

**Plan**:
1. Resolve project slug from current repo
2. Detect version from `VERSION`, `package.json`, or `--version` arg
3. Check `releases/` for existing note with this version — abort if duplicate
4. Run `git log` between previous tag and HEAD to build changelog
5. Create `releases/v{version}.md` via MCP with frontmatter and changelog
6. Append progress entry noting the release
7. Confirm to user

---

## Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NFR-001 | All vault writes go through Obsidian MCP tools — no direct filesystem access |
| NFR-002 | Plugin must work with any Obsidian MCP server (not hardcoded to a specific vault path) |
| NFR-003 | The `projects/` base path should be configurable (default: `@second-brain/projects`) |
| NFR-004 | Plugin must degrade gracefully if MCP server is unavailable — warning, not error |
| NFR-005 | No credentials or secrets stored in Obsidian notes |

## Success Criteria

- `/shelf-create` scaffolds the full directory structure and populates dashboard + about.md
- `/shelf-update` appends a progress entry and updates frontmatter within one command
- `/shelf-sync` creates issue notes matching all open GitHub issues
- `/shelf-feedback` reads and archives feedback from Obsidian
- `/shelf-status` displays a useful summary without modifying anything
- `/shelf-release` creates a release note with auto-generated changelog from git history
- All commands degrade gracefully (warning, not error) if MCP server is unreachable

## Open Questions

- Should shelf also track non-code projects (design docs, research, learning)?
- Should release notes be auto-generated from git tags, or manually triggered via a future `/shelf-release` command?
- How should conflicts be handled if the user edits a file in Obsidian while shelf is updating it?
- Should there be a `/shelf-dashboard` that generates a cross-project summary note?

## Deferred Work

- **Hook integration with kiln**: Auto-trigger `/shelf-update` after `/build-prd`, `/fix`, `/qa-pass`
- **CLAUDE.md integration**: Auto-run `/shelf-feedback` at session start
