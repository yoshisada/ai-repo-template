# Feature PRD: Shelf Sync v2 — Templates, Tags, Docs & Lifecycle

**Date**: 2026-04-03
**Status**: Draft
**Parent PRD**: docs/features/2026-04-03-shelf/PRD.md

## Background

The shelf plugin's first release (v0.1) shipped 6 skills that sync project data to Obsidian. In practice, several gaps emerged immediately:

1. **Note formats are hardcoded** in each SKILL.md — no reusable templates, no consistency guarantees, and no way for users to customize the format.
2. **Backlinks and tags are missing** — Obsidian notes don't link back to the project dashboard or carry tags, making the graph view and dataview queries less useful.
3. **Issue lifecycle is incomplete** — when backlog items are archived locally, their Obsidian counterparts stay `status: open` until manually fixed.
4. **Docs don't sync** — the `docs/` section of the Obsidian dashboard is always empty because no skill pushes documentation notes.
5. **Tech stack tags go stale** — tags are set once during `/shelf-create` and never updated as the repo evolves.

A tag taxonomy file (`plugin-shelf/tags.md`) was added as a quick fix, but it's not yet referenced by the skill definitions or enforced via templates.

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [Shelf plugin needs explicit templates for each Obsidian note type](.kiln/issues/2026-04-03-shelf-note-templates.md) | — | improvement | high |
| 2 | [Shelf notes need backlinks to project dashboard and consistent tags](.kiln/issues/2026-04-03-shelf-notes-backlinks-tags.md) | — | improvement | high |
| 3 | [shelf-sync should close Obsidian notes for archived backlog issues](.kiln/issues/2026-04-03-shelf-sync-close-archived-issues.md) | — | improvement | medium |
| 4 | [Add docs sync to shelf-sync — push PRD summaries to Obsidian](.kiln/issues/2026-04-03-shelf-sync-docs.md) | — | feature-request | medium |
| 5 | [shelf-sync should update project tech stack tags during sync](.kiln/issues/2026-04-03-shelf-sync-update-tech-tags.md) | — | improvement | medium |

## Problem Statement

Shelf skills generate Obsidian notes with inconsistent formats, no backlinks, no tags, and incomplete lifecycle management. This makes the Obsidian project dashboard less useful than it should be — notes don't connect to each other, the docs section is always empty, archived issues appear open, and tech stack tags go stale. Every session requires manual cleanup that the plugin should handle automatically.

## Goals

- Every Obsidian note created by shelf skills uses a template from `plugin-shelf/templates/`
- Every note includes a `project: "[[{slug}]]"` backlink and tags from the canonical taxonomy
- `/shelf-sync` automatically closes Obsidian notes when their backlog source is archived
- `/shelf-sync` syncs docs (PRD summaries) to Obsidian alongside issues
- `/shelf-sync` re-detects and updates tech stack tags on the project dashboard
- Users can override templates by placing customized versions in `.shelf/templates/` in their repo

## Non-Goals

- Full-text sync of PRD/spec content to Obsidian (summaries only)
- Bi-directional sync (Obsidian → repo) — shelf is write-only to Obsidian
- Syncing non-shelf artifacts (git history, test results, CI status)
- Template rendering engine — templates are Markdown with `{variable}` placeholders, not a full templating language

## Requirements

### Functional Requirements

**FR-001** (from: shelf-note-templates.md): Create template files in `plugin-shelf/templates/` for each Obsidian note type: `issue.md`, `doc.md`, `progress.md`, `release.md`, `decision.md`, `dashboard.md`.

**FR-002** (from: shelf-note-templates.md): Each template MUST include full frontmatter schema with all required fields, `project: "[[{slug}]]"` backlink, `tags:` field with comments showing valid values, and `{variable}` placeholders for dynamic content.

**FR-003** (from: shelf-note-templates.md): All shelf skills that create Obsidian notes MUST read and use the appropriate template from `plugin-shelf/templates/` instead of hardcoding note formats in SKILL.md instructions.

**FR-004** (from: shelf-note-templates.md): Skills MUST check for user-customized templates at `.shelf/templates/{name}.md` in the repo root before falling back to the plugin default template.

**FR-005** (from: shelf-notes-backlinks-tags.md): Every Obsidian note created or updated by shelf skills MUST include `project: "[[{slug}]]"` in frontmatter as a backlink to the project dashboard.

**FR-006** (from: shelf-notes-backlinks-tags.md): Every issue note MUST include `tags:` in frontmatter with values derived from: source (`source/*`), severity (`severity/*`), type (`type/*`), and category (`category/*`) — using the canonical taxonomy in `plugin-shelf/tags.md`.

**FR-007** (from: shelf-notes-backlinks-tags.md): Every doc note MUST include `tags:` with values derived from: doc type (`doc/*`), status (`status/*`), and category (`category/*`).

**FR-008** (from: shelf-notes-backlinks-tags.md): All tag values MUST come from the canonical taxonomy in `plugin-shelf/tags.md`. Skills MUST NOT invent tags outside these namespaces.

**FR-009** (from: shelf-sync-close-archived-issues.md): During sync, for each existing Obsidian issue note with `source: "backlog:*"`, check if the source file exists in `.kiln/issues/`. If not found there but found in `.kiln/issues/completed/`, update the Obsidian note to `status: closed`.

**FR-010** (from: shelf-sync-close-archived-issues.md): Track closed notes in the sync summary counter: "Closed: N notes marked closed".

**FR-011** (from: shelf-sync-docs.md): `/shelf-sync` MUST scan `docs/features/*/PRD.md` for feature PRDs and create or update summary doc notes at `{base_path}/{slug}/docs/{feature-slug}.md`.

**FR-012** (from: shelf-sync-docs.md): Doc notes MUST include: title, 1-2 sentence summary, FR/NFR counts, status, backlink, and tags. Content is a summary, not the full PRD text.

**FR-013** (from: shelf-sync-docs.md): Skip unchanged docs during sync (compare content or modification time). Report in sync summary: "Docs: N created, N updated, N skipped".

**FR-014** (from: shelf-sync-update-tech-tags.md): During sync, re-run tech stack detection (same logic as `/shelf-create` Step 4 — scan package.json, tsconfig.json, Cargo.toml, etc.).

**FR-015** (from: shelf-sync-update-tech-tags.md): Compare detected tags with current dashboard `tags` frontmatter. If different, update the dashboard with the new tag set.

**FR-016** (from: shelf-sync-update-tech-tags.md): Report tag changes in sync summary: "Tags: +N added, -N removed" or "Tags: unchanged".

### Non-Functional Requirements

**NFR-001**: Templates must be valid Markdown files parseable by any Markdown editor. No custom syntax beyond `{variable}` placeholders.

**NFR-002**: Tag taxonomy changes in `plugin-shelf/tags.md` must not require changes to template files — templates reference the taxonomy by namespace, not by enumerating every value.

**NFR-003**: All MCP writes must be gracefully degradable — if MCP fails for one note, warn and continue with the rest.

**NFR-004**: User-customized templates at `.shelf/templates/` take priority over plugin defaults, enabling per-repo customization without modifying the plugin.

**NFR-005**: Sync must remain idempotent — running it twice produces the same result.

## User Stories

**US-001**: As a developer, I want shelf notes to have consistent formatting and tags so Obsidian's dataview queries and graph view work properly across all note types.

**US-002**: As a developer, I want `/shelf-sync` to automatically close Obsidian issue notes when I archive backlog items, so I don't have to manually update both systems.

**US-003**: As a developer, I want my Obsidian project's docs section to show PRD summaries so I can browse feature history without switching to the repo.

**US-004**: As a developer, I want tech stack tags to stay current as my project evolves, without re-running `/shelf-create`.

**US-005**: As a team lead, I want to customize note templates for my team's Obsidian workflow by overriding plugin defaults in the repo.

## Success Criteria

- All 6 template files exist in `plugin-shelf/templates/`
- Running `/shelf-sync` on this repo produces notes with backlinks, tags, closed archived issues, synced docs, and updated tech tags — all in one pass
- The sync summary shows all 5 counters: issues (created/updated/closed/skipped), docs (created/updated/skipped), tags (added/removed/unchanged)
- Placing a custom `issue.md` in `.shelf/templates/` overrides the plugin default
- Tag values on all notes match the taxonomy in `plugin-shelf/tags.md`

## Tech Stack

- Markdown (skill definitions + template files)
- Bash (inline shell in skills for tech detection, file scanning)
- Obsidian MCP (vault writes)
- No new dependencies

## Risks & Open Questions

1. **Template variable syntax**: `{variable}` is simple but could conflict with Markdown content. Low risk since frontmatter is YAML and body content rarely uses bare braces.
2. **Doc summary extraction**: Extracting a 1-2 sentence summary from a PRD requires reading the file and picking the right section. The skill instructions need to specify which section to summarize (Background? Problem Statement?).
3. **Tech detection accuracy**: The detection logic may miss frameworks not in the lookup table. This is acceptable — users can add custom tags manually.
