---
title: "Shelf notes need backlinks to project dashboard and consistent tags"
type: improvement
severity: high
category: skills
source: manual
github_issue: null
status: completedcompleted_date: 2026-04-23
pr: merged-pre-tracking
date: 2026-04-03
---

## Description

Three related improvements to how shelf skills generate Obsidian notes:

### 1. Backlinks to project dashboard

Every issue note and doc note should include a `parent` or `project` field in frontmatter that links back to the main project dashboard. This enables Obsidian's backlink graph and dataview queries to navigate from any note back to the project.

Example frontmatter addition:
```yaml
project: "[[ai-repo-template]]"
```

Or as a relative path:
```yaml
parent: "@second-brain/projects/ai-repo-template/ai-repo-template.md"
```

### 2. Tags on individual notes

Issue notes and doc notes should carry relevant tags in their frontmatter to enable filtering in Obsidian. For issues, tags could be derived from:
- Issue category (e.g., `category/skills`, `category/agents`)
- Issue type (e.g., `type/bug`, `type/improvement`)
- Source (e.g., `source/github`, `source/backlog`)

For docs, tags could be derived from:
- Doc type (e.g., `doc/prd`, `doc/spec`, `doc/overview`)
- Feature area

### 3. Canonical tag taxonomy in skill definitions

The shelf plugin should maintain a canonical set of tag types — either in a shared config section referenced by all skills, or in a dedicated file like `plugin-shelf/tags.md`. This prevents tag drift across skills (e.g., one skill using `type/bug` and another using `bug`).

Proposed tag namespaces:
- `category/*` — skills, agents, hooks, templates, scaffold, workflow
- `type/*` — bug, improvement, feature-request, friction
- `severity/*` — critical, high, medium, low
- `source/*` — github, backlog, retro, manual
- `doc/*` — prd, spec, plan, overview, decision
- `status/*` — open, closed, in-progress

These should be defined once and referenced by shelf-sync, shelf-create, and any future doc-sync skill.
prd: docs/features/2026-04-03-shelf-sync-v2/PRD.md
