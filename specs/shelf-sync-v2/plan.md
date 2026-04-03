# Shelf Sync v2 — Implementation Plan

**Feature**: Shelf Sync v2 — Templates, Tags, Docs & Lifecycle
**Spec**: specs/shelf-sync-v2/spec.md
**Date**: 2026-04-03

## Technical Approach

This is a Markdown-only plugin — no compiled code. All deliverables are template files and SKILL.md updates. The implementation creates 6 template files that define the canonical note format for each Obsidian note type, then updates all 6 shelf skill definitions to reference these templates instead of hardcoding note formats. The shelf-sync skill receives the largest changes: issue lifecycle management, docs sync, and tech tag refresh.

## Architecture

### Template System

Templates live in `plugin-shelf/templates/` and use `{variable}` placeholders. Each template defines:
- Full YAML frontmatter with all required fields
- `project: "[[{slug}]]"` backlink (FR-005)
- `tags:` field with namespace comments referencing `plugin-shelf/tags.md` (FR-006, FR-007, FR-008)
- Body content with placeholders

Skills resolve templates by checking `.shelf/templates/{name}.md` first (user override, FR-004), then falling back to `plugin-shelf/templates/{name}.md` (plugin default).

### Tag Derivation

Tags are derived at note-creation time, not stored in templates as fixed values. The template includes `tags:` with comment annotations showing which namespaces to populate. The skill reads `plugin-shelf/tags.md` to know valid values, then selects the appropriate tag from each namespace based on the note's metadata.

**Issue notes** get tags from: `source/*`, `severity/*`, `type/*`, `category/*`
**Doc notes** get tags from: `doc/*`, `status/*`, `category/*`
**Progress/release/decision/dashboard notes** get tags from: `status/*` and contextually appropriate namespaces

### Sync Enhancements (shelf-sync)

The sync skill gains 3 new phases inserted into its existing flow:

1. **Issue lifecycle** (FR-009, FR-010): After syncing issues, check each backlog-sourced note. If the source file is in `.kiln/issues/completed/` instead of `.kiln/issues/`, set `status: closed`.

2. **Docs sync** (FR-011, FR-012, FR-013): New phase scanning `docs/features/*/PRD.md`. For each PRD, extract title + Problem Statement summary + FR/NFR counts. Create or update a doc note using the `doc.md` template. Skip unchanged docs.

3. **Tech tag refresh** (FR-014, FR-015, FR-016): Re-run tech stack detection (same logic as shelf-create Step 3). Compare with dashboard frontmatter tags. Update if different.

## Phases

### Phase 1: Templates (FR-001, FR-002, FR-005, FR-006, FR-007, FR-008)
Create all 6 template files in `plugin-shelf/templates/`.

**Files created:**
- `plugin-shelf/templates/issue.md`
- `plugin-shelf/templates/doc.md`
- `plugin-shelf/templates/progress.md`
- `plugin-shelf/templates/release.md`
- `plugin-shelf/templates/decision.md`
- `plugin-shelf/templates/dashboard.md`

### Phase 2: Skill updates — template adoption (FR-003, FR-004)
Update all 6 shelf skill SKILL.md files to reference templates instead of hardcoding note formats. Add template resolution logic (check user override path first).

**Files modified:**
- `plugin-shelf/skills/shelf-create/SKILL.md`
- `plugin-shelf/skills/shelf-sync/SKILL.md`
- `plugin-shelf/skills/shelf-update/SKILL.md`
- `plugin-shelf/skills/shelf-release/SKILL.md`
- `plugin-shelf/skills/shelf-feedback/SKILL.md`
- `plugin-shelf/skills/shelf-status/SKILL.md` (read-only skill — only needs awareness of template format for parsing, no template writes)

### Phase 3: Shelf-sync enhancements (FR-009 through FR-016)
Add issue lifecycle management, docs sync, and tech tag refresh to the shelf-sync SKILL.md.

**Files modified:**
- `plugin-shelf/skills/shelf-sync/SKILL.md` (major rewrite — adds 3 new step blocks)

### Phase 4: Tags taxonomy update
Update `plugin-shelf/tags.md` to ensure it covers all namespaces referenced by the new templates and skill logic. Add any missing tag values discovered during template creation.

**Files modified:**
- `plugin-shelf/tags.md`

## File Inventory

| File | Action | Phase | FRs |
|------|--------|-------|-----|
| `plugin-shelf/templates/issue.md` | Create | 1 | FR-001, FR-002, FR-005, FR-006 |
| `plugin-shelf/templates/doc.md` | Create | 1 | FR-001, FR-002, FR-005, FR-007 |
| `plugin-shelf/templates/progress.md` | Create | 1 | FR-001, FR-002, FR-005 |
| `plugin-shelf/templates/release.md` | Create | 1 | FR-001, FR-002, FR-005 |
| `plugin-shelf/templates/decision.md` | Create | 1 | FR-001, FR-002, FR-005 |
| `plugin-shelf/templates/dashboard.md` | Create | 1 | FR-001, FR-002, FR-005 |
| `plugin-shelf/skills/shelf-create/SKILL.md` | Modify | 2 | FR-003, FR-004 |
| `plugin-shelf/skills/shelf-sync/SKILL.md` | Modify | 2, 3 | FR-003, FR-004, FR-009–FR-016 |
| `plugin-shelf/skills/shelf-update/SKILL.md` | Modify | 2 | FR-003, FR-004 |
| `plugin-shelf/skills/shelf-release/SKILL.md` | Modify | 2 | FR-003, FR-004 |
| `plugin-shelf/skills/shelf-feedback/SKILL.md` | Modify | 2 | FR-003, FR-004 |
| `plugin-shelf/skills/shelf-status/SKILL.md` | Modify | 2 | FR-003 |
| `plugin-shelf/tags.md` | Modify | 4 | FR-008 |

## Risks & Mitigations

1. **Template variable conflicts**: `{variable}` could appear in normal Markdown. Mitigated by limiting placeholders to frontmatter and structured body sections only.
2. **PRD summary extraction**: Summarizing a PRD requires picking the right section. Plan specifies using the "Problem Statement" section, falling back to "Background" first paragraph.
3. **Tech detection drift**: Detection logic is duplicated between shelf-create and shelf-sync. Both reference the same lookup table in their SKILL.md instructions, so they stay in sync by definition.

## Constraints

- No new dependencies — all Markdown, Bash inline in SKILL.md
- No compiled code — this is a plugin of skill/agent definitions
- Templates use only `{variable}` placeholder syntax, no templating engine
- All Obsidian writes go through MCP, never direct filesystem
