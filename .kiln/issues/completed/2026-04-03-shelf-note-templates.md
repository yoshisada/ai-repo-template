---
title: "Shelf plugin needs explicit templates for each Obsidian note type"
type: improvement
severity: high
category: templates
source: manual
github_issue: null
status: completedcompleted_date: 2026-04-23
pr: merged-pre-tracking
date: 2026-04-03
---

## Description

Each shelf skill currently embeds its note format inline in the SKILL.md instructions. This makes formats inconsistent across skills and hard to maintain. The plugin should have explicit template files for each type of Obsidian note it creates:

### Required templates

- `plugin-shelf/templates/issue.md` — issue note (used by shelf-sync)
- `plugin-shelf/templates/doc.md` — documentation note (used by future shelf-docs-sync)
- `plugin-shelf/templates/progress.md` — progress entry (used by shelf-update)
- `plugin-shelf/templates/release.md` — release note (used by shelf-release)
- `plugin-shelf/templates/decision.md` — decision record (future)
- `plugin-shelf/templates/dashboard.md` — project dashboard (used by shelf-create)

### Each template should include

- Full frontmatter schema with all required/optional fields
- `project: "[[{slug}]]"` backlink (mandatory on all notes)
- `tags:` field with comments showing valid values from `plugin-shelf/tags.md`
- Placeholder sections with `{variable}` markers that skills fill in
- Comments explaining which skill uses this template and when

### Tag taxonomy reference

`plugin-shelf/tags.md` already exists with the canonical tag namespaces. Templates should reference it so skills always use valid tags. If a skill needs a new tag, it should be added to tags.md first.

### Benefits

- Single source of truth for note formats
- Skills reference templates instead of hardcoding formats
- Users can customize templates by copying to `.shelf/templates/` in their repo
- Consistency across all shelf skills
prd: docs/features/2026-04-03-shelf-sync-v2/PRD.md
