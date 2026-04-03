# Shelf Sync v2 — Feature Specification

**Feature**: Shelf Sync v2 — Templates, Tags, Docs & Lifecycle
**PRD**: docs/features/2026-04-03-shelf-sync-v2/PRD.md
**Date**: 2026-04-03
**Status**: Draft

## Overview

Shelf Sync v2 upgrades the shelf plugin from hardcoded note formats to a template-driven system, adds backlinks and tags to every note, closes archived issues automatically, syncs PRD summaries as doc notes, and refreshes tech stack tags during sync.

## User Stories

### US-001: Consistent note formatting
As a developer, I want shelf notes to have consistent formatting and tags so Obsidian's dataview queries and graph view work properly across all note types.

**Acceptance criteria:**
- All 6 template files exist in `plugin-shelf/templates/`
- Every note created by shelf skills uses the appropriate template
- Tags on notes match the canonical taxonomy in `plugin-shelf/tags.md`
- Graph view shows backlinks from every note to the project dashboard

### US-002: Automatic issue lifecycle
As a developer, I want `/shelf-sync` to automatically close Obsidian issue notes when I archive backlog items, so I don't have to manually update both systems.

**Acceptance criteria:**
- When a backlog source file moves from `.kiln/issues/` to `.kiln/issues/completed/`, the corresponding Obsidian note is updated to `status: closed`
- Closed count appears in sync summary

### US-003: Docs sync
As a developer, I want my Obsidian project's docs section to show PRD summaries so I can browse feature history without switching to the repo.

**Acceptance criteria:**
- `/shelf-sync` scans `docs/features/*/PRD.md` and creates summary doc notes
- Doc notes include title, summary, FR/NFR counts, status, backlink, and tags
- Unchanged docs are skipped; sync summary reports docs created/updated/skipped

### US-004: Tech stack tag refresh
As a developer, I want tech stack tags to stay current as my project evolves, without re-running `/shelf-create`.

**Acceptance criteria:**
- `/shelf-sync` re-detects tech stack using the same logic as `/shelf-create` Step 3
- Dashboard tags are updated if they differ from detected tags
- Sync summary reports tags added/removed/unchanged

### US-005: Template customization
As a team lead, I want to customize note templates for my team's Obsidian workflow by overriding plugin defaults in the repo.

**Acceptance criteria:**
- Placing a custom `issue.md` in `.shelf/templates/` overrides the plugin default
- Skills check `.shelf/templates/{name}.md` before falling back to `plugin-shelf/templates/{name}.md`

## Functional Requirements

### FR-001: Create template files
Create template files in `plugin-shelf/templates/` for each Obsidian note type: `issue.md`, `doc.md`, `progress.md`, `release.md`, `decision.md`, `dashboard.md`.

**Maps to**: US-001
**Validates**: Template files exist and are valid Markdown

### FR-002: Template schema
Each template MUST include full frontmatter schema with all required fields, `project: "[[{slug}]]"` backlink, `tags:` field with comments showing valid values, and `{variable}` placeholders for dynamic content.

**Maps to**: US-001
**Validates**: Each template has frontmatter with project backlink, tags field, and placeholders

### FR-003: Skills use templates
All shelf skills that create Obsidian notes MUST read and use the appropriate template from `plugin-shelf/templates/` instead of hardcoding note formats in SKILL.md instructions.

**Maps to**: US-001
**Validates**: Each skill's SKILL.md references templates instead of inline note formats

### FR-004: User template override
Skills MUST check for user-customized templates at `.shelf/templates/{name}.md` in the repo root before falling back to the plugin default template.

**Maps to**: US-005
**Validates**: Override path checked first; plugin default used as fallback

### FR-005: Backlink on every note
Every Obsidian note created or updated by shelf skills MUST include `project: "[[{slug}]]"` in frontmatter as a backlink to the project dashboard.

**Maps to**: US-001
**Validates**: All templates and generated notes contain project backlink

### FR-006: Issue tags
Every issue note MUST include `tags:` in frontmatter with values derived from: source (`source/*`), severity (`severity/*`), type (`type/*`), and category (`category/*`) — using the canonical taxonomy in `plugin-shelf/tags.md`.

**Maps to**: US-001
**Validates**: Issue notes contain tags from all 4 required namespaces

### FR-007: Doc tags
Every doc note MUST include `tags:` with values derived from: doc type (`doc/*`), status (`status/*`), and category (`category/*`).

**Maps to**: US-003
**Validates**: Doc notes contain tags from all 3 required namespaces

### FR-008: Tag taxonomy enforcement
All tag values MUST come from the canonical taxonomy in `plugin-shelf/tags.md`. Skills MUST NOT invent tags outside these namespaces.

**Maps to**: US-001
**Validates**: All tags in generated notes exist in tags.md

### FR-009: Close archived issues
During sync, for each existing Obsidian issue note with `source: "backlog:*"`, check if the source file exists in `.kiln/issues/`. If not found there but found in `.kiln/issues/completed/`, update the Obsidian note to `status: closed`.

**Maps to**: US-002
**Validates**: Archived backlog items produce closed Obsidian notes

### FR-010: Closed note counter
Track closed notes in the sync summary counter: "Closed: N notes marked closed".

**Maps to**: US-002
**Validates**: Sync summary includes closed count

### FR-011: Scan and sync docs
`/shelf-sync` MUST scan `docs/features/*/PRD.md` for feature PRDs and create or update summary doc notes at `{base_path}/{slug}/docs/{feature-slug}.md`.

**Maps to**: US-003
**Validates**: Doc notes created for each PRD found

### FR-012: Doc note content
Doc notes MUST include: title, 1-2 sentence summary (from Problem Statement section), FR/NFR counts, status, backlink, and tags. Content is a summary, not the full PRD text.

**Maps to**: US-003
**Validates**: Doc notes contain all required fields

### FR-013: Skip unchanged docs
Skip unchanged docs during sync (compare content or modification time). Report in sync summary: "Docs: N created, N updated, N skipped".

**Maps to**: US-003
**Validates**: Unchanged docs not rewritten; summary shows doc counters

### FR-014: Re-detect tech stack
During sync, re-run tech stack detection (same logic as `/shelf-create` Step 3 — scan package.json, tsconfig.json, Cargo.toml, etc.).

**Maps to**: US-004
**Validates**: Tech detection runs during sync

### FR-015: Update dashboard tags
Compare detected tags with current dashboard `tags` frontmatter. If different, update the dashboard with the new tag set.

**Maps to**: US-004
**Validates**: Dashboard tags updated when detection differs

### FR-016: Report tag changes
Report tag changes in sync summary: "Tags: +N added, -N removed" or "Tags: unchanged".

**Maps to**: US-004
**Validates**: Sync summary includes tag change report

## Non-Functional Requirements

### NFR-001: Valid Markdown
Templates must be valid Markdown files parseable by any Markdown editor. No custom syntax beyond `{variable}` placeholders.

### NFR-002: Taxonomy decoupling
Tag taxonomy changes in `plugin-shelf/tags.md` must not require changes to template files — templates reference the taxonomy by namespace, not by enumerating every value.

### NFR-003: Graceful degradation
All MCP writes must be gracefully degradable — if MCP fails for one note, warn and continue with the rest.

### NFR-004: User override priority
User-customized templates at `.shelf/templates/` take priority over plugin defaults, enabling per-repo customization without modifying the plugin.

### NFR-005: Idempotent sync
Sync must remain idempotent — running it twice produces the same result.

## Success Criteria

1. All 6 template files exist in `plugin-shelf/templates/`
2. Running `/shelf-sync` produces notes with backlinks, tags, closed archived issues, synced docs, and updated tech tags — all in one pass
3. Sync summary shows all counters: issues (created/updated/closed/skipped), docs (created/updated/skipped), tags (added/removed/unchanged)
4. Placing a custom `issue.md` in `.shelf/templates/` overrides the plugin default
5. Tag values on all notes match the taxonomy in `plugin-shelf/tags.md`
