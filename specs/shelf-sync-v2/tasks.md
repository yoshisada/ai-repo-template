# Shelf Sync v2 — Task Breakdown

**Feature**: Shelf Sync v2
**Plan**: specs/shelf-sync-v2/plan.md
**Contracts**: specs/shelf-sync-v2/contracts/interfaces.md
**Date**: 2026-04-03

## Phase 1: Templates (FR-001, FR-002, FR-005, FR-006, FR-007, FR-008)

### Task 1.1: Create issue.md template
- [X] Create `plugin-shelf/templates/issue.md`
- Frontmatter: type, status, severity, source, github_number, project backlink, tags (source/*, severity/*, type/*, category/*), last_synced
- Body: title heading, body content, sync footer
- All tag fields reference namespaces from `plugin-shelf/tags.md`, not hardcoded values
- **FRs**: FR-001, FR-002, FR-005, FR-006, FR-008
- **File**: `plugin-shelf/templates/issue.md` (create)

### Task 1.2: Create doc.md template
- [X] Create `plugin-shelf/templates/doc.md`
- Frontmatter: type, title, summary, fr_count, nfr_count, status, project backlink, tags (doc/*, status/*, category/*), prd_path
- Body: title heading, summary, requirements counts, source link
- **FRs**: FR-001, FR-002, FR-005, FR-007, FR-008
- **File**: `plugin-shelf/templates/doc.md` (create)

### Task 1.3: Create progress.md template
- [X] Create `plugin-shelf/templates/progress.md`
- Frontmatter header for monthly file, entry format with date heading, summary, outcomes, links, optional decision link, project backlink, tags (status/*)
- **FRs**: FR-001, FR-002, FR-005
- **File**: `plugin-shelf/templates/progress.md` (create)

### Task 1.4: Create release.md template
- [X] Create `plugin-shelf/templates/release.md`
- Frontmatter: type, version, date, summary, project backlink, tags (status/*)
- Body: version heading, summary, changelog section
- **FRs**: FR-001, FR-002, FR-005
- **File**: `plugin-shelf/templates/release.md` (create)

### Task 1.5: Create decision.md template
- [X] Create `plugin-shelf/templates/decision.md`
- Frontmatter: type, date, status, project backlink, tags (status/*)
- Body: title heading, context, options considered, decision, rationale sections
- **FRs**: FR-001, FR-002, FR-005
- **File**: `plugin-shelf/templates/decision.md` (create)

### Task 1.6: Create dashboard.md template
- [X] Create `plugin-shelf/templates/dashboard.md`
- Frontmatter: type, status, repo, tags (tech stack tags), next_step, last_updated, project backlink
- Body: slug heading, sections for Human Needed, Feedback, Feedback Log
- **FRs**: FR-001, FR-002, FR-005
- **File**: `plugin-shelf/templates/dashboard.md` (create)

## Phase 2: Skill Updates — Template Adoption (FR-003, FR-004)

### Task 2.1: Update shelf-create to use templates
- [X] Modify `plugin-shelf/skills/shelf-create/SKILL.md`
- Add template resolution step: check `.shelf/templates/dashboard.md` then `plugin-shelf/templates/dashboard.md`
- Replace hardcoded dashboard format in Step 6 with template reference
- Replace hardcoded about.md format in Step 7 with template-aware format
- Add backlink and tags to created notes
- **FRs**: FR-003, FR-004, FR-005
- **File**: `plugin-shelf/skills/shelf-create/SKILL.md` (modify)
- **Depends on**: Task 1.6

### Task 2.2: Update shelf-update to use templates
- [X] Modify `plugin-shelf/skills/shelf-update/SKILL.md`
- Add template resolution for progress and decision templates
- Replace hardcoded progress entry format in Step 5 with template reference
- Replace hardcoded decision format in Step 6 with template reference
- Add backlink and tags to created notes
- **FRs**: FR-003, FR-004, FR-005
- **File**: `plugin-shelf/skills/shelf-update/SKILL.md` (modify)
- **Depends on**: Tasks 1.3, 1.5

### Task 2.3: Update shelf-release to use templates
- [X] Modify `plugin-shelf/skills/shelf-release/SKILL.md`
- Add template resolution for release template
- Replace hardcoded release note format in Step 6 with template reference
- Add backlink and tags to created notes
- **FRs**: FR-003, FR-004, FR-005
- **File**: `plugin-shelf/skills/shelf-release/SKILL.md` (modify)
- **Depends on**: Task 1.4

### Task 2.4: Update shelf-feedback to use templates
- [X] Modify `plugin-shelf/skills/shelf-feedback/SKILL.md`
- Shelf-feedback modifies the dashboard but doesn't create new note types — update to preserve backlinks and tags when rewriting the dashboard
- Reference dashboard template format for consistency
- **FRs**: FR-003, FR-005
- **File**: `plugin-shelf/skills/shelf-feedback/SKILL.md` (modify)
- **Depends on**: Task 1.6

### Task 2.5: Update shelf-status to reference template format
- [X] Modify `plugin-shelf/skills/shelf-status/SKILL.md`
- Shelf-status is read-only — update parsing logic to be aware of new frontmatter fields (project backlink, tags) so it can display them
- No template writes needed
- **FRs**: FR-003
- **File**: `plugin-shelf/skills/shelf-status/SKILL.md` (modify)
- **Depends on**: Phase 1

### Task 2.6: Update shelf-sync for template adoption
- [X] Modify `plugin-shelf/skills/shelf-sync/SKILL.md`
- Add template resolution step for issue template
- Replace hardcoded issue note format in Step 8 with template reference
- Add user override check (`.shelf/templates/issue.md` first)
- Add backlink and tags to issue notes using tag derivation algorithm from contracts
- **FRs**: FR-003, FR-004, FR-005, FR-006, FR-008
- **File**: `plugin-shelf/skills/shelf-sync/SKILL.md` (modify)
- **Depends on**: Task 1.1

## Phase 3: Shelf-Sync Enhancements (FR-009 through FR-016)

### Task 3.1: Add issue lifecycle management to shelf-sync
- [ ] Modify `plugin-shelf/skills/shelf-sync/SKILL.md`
- Add new step after issue sync: for each Obsidian issue note with `source: "backlog:*"`, check if source file exists in `.kiln/issues/`. If not there but in `.kiln/issues/completed/`, update note to `status: closed`
- Add `closed` counter to sync summary
- **FRs**: FR-009, FR-010
- **File**: `plugin-shelf/skills/shelf-sync/SKILL.md` (modify)
- **Depends on**: Task 2.6

### Task 3.2: Add docs sync to shelf-sync
- [ ] Modify `plugin-shelf/skills/shelf-sync/SKILL.md`
- Add new step: scan `docs/features/*/PRD.md`
- For each PRD: extract title, Problem Statement summary (1-2 sentences), count FR-*/NFR-* occurrences, read Status field
- Create/update doc note at `{base_path}/{slug}/docs/{feature-slug}.md` using doc.md template
- Skip unchanged docs (compare content)
- Add doc counters to sync summary: "Docs: N created, N updated, N skipped"
- **FRs**: FR-011, FR-012, FR-013
- **File**: `plugin-shelf/skills/shelf-sync/SKILL.md` (modify)
- **Depends on**: Task 1.2, Task 2.6

### Task 3.3: Add tech tag refresh to shelf-sync
- [ ] Modify `plugin-shelf/skills/shelf-sync/SKILL.md`
- Add new step: re-run tech stack detection (same lookup table as shelf-create Step 3)
- Read current dashboard tags from frontmatter
- Compare detected vs current; if different, update dashboard with new tags
- Add tag change counters to sync summary: "Tags: +N added, -N removed" or "Tags: unchanged"
- **FRs**: FR-014, FR-015, FR-016
- **File**: `plugin-shelf/skills/shelf-sync/SKILL.md` (modify)
- **Depends on**: Task 2.6

### Task 3.4: Update shelf-sync summary format
- [ ] Modify `plugin-shelf/skills/shelf-sync/SKILL.md`
- Rewrite the Report Results step to include all counters per the contracts sync summary format
- Issues: created/updated/closed/skipped
- Docs: created/updated/skipped
- Tags: +N added, -N removed / unchanged
- Sources: GitHub count, Backlog count, Docs count
- **FRs**: FR-010, FR-013, FR-016
- **File**: `plugin-shelf/skills/shelf-sync/SKILL.md` (modify)
- **Depends on**: Tasks 3.1, 3.2, 3.3

## Phase 4: Tags Taxonomy Update (FR-008)

### Task 4.1: Update tags.md with any missing values
- [ ] Review `plugin-shelf/tags.md` for completeness against all template tag references
- Add `language/*` and `framework/*` and `infra/*` namespaces for tech stack tags (used by dashboard template)
- Ensure all namespaces referenced in contracts are present
- **FRs**: FR-008
- **File**: `plugin-shelf/tags.md` (modify)
- **Depends on**: Phase 1

## Summary

| Phase | Tasks | Files Created | Files Modified |
|-------|-------|---------------|----------------|
| 1 — Templates | 6 | 6 | 0 |
| 2 — Skill updates | 6 | 0 | 6 |
| 3 — Sync enhancements | 4 | 0 | 1 (shelf-sync) |
| 4 — Tags update | 1 | 0 | 1 (tags.md) |
| **Total** | **17** | **6** | **7** |
