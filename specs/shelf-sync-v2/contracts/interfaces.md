# Shelf Sync v2 — Interface Contracts

**Feature**: Shelf Sync v2
**Date**: 2026-04-03

This plugin has no compiled code — deliverables are Markdown templates and SKILL.md files. These contracts define the template variable schemas and tag derivation algorithm that all templates and skills MUST follow.

## Template Variable Schema

Every template uses `{variable}` placeholders. These are the canonical variable names and their sources.

### Shared Variables (all templates)

| Variable | Type | Source | Description |
|----------|------|--------|-------------|
| `{slug}` | string | `.shelf-config` or git remote | Project slug (kebab-case) |
| `{base_path}` | string | `.shelf-config` or default `projects` | Vault base path |
| `{date}` | string | Current date | ISO format `YYYY-MM-DD` |
| `{timestamp}` | string | Current time | ISO 8601 `YYYY-MM-DDTHH:MM:SSZ` |

### Issue Template Variables (`issue.md`)

| Variable | Type | Source | Description |
|----------|------|--------|-------------|
| `{title}` | string | Issue title | Note heading |
| `{status}` | enum | `open`, `closed` | Current issue status |
| `{severity}` | enum | tags.md `severity/*` values | Issue severity level |
| `{source}` | string | `GitHub #N` or `backlog:filename` | Origin reference |
| `{github_number}` | number\|null | GitHub issue number | Null for backlog items |
| `{type_tag}` | string | tags.md `type/*` value | Issue type tag |
| `{source_tag}` | string | tags.md `source/*` value | Source tag |
| `{severity_tag}` | string | tags.md `severity/*` value | Severity tag |
| `{category_tag}` | string | tags.md `category/*` value | Category tag |
| `{body}` | string | Issue body text | Main content |
| `{sync_footer}` | string | Generated | Attribution line |
| `{last_synced}` | string | Current time | ISO 8601 timestamp |

### Doc Template Variables (`doc.md`)

| Variable | Type | Source | Description |
|----------|------|--------|-------------|
| `{title}` | string | PRD title | Doc note heading |
| `{summary}` | string | PRD Problem Statement (1-2 sentences) | Brief description |
| `{fr_count}` | number | Count of `FR-*` in PRD | Functional requirement count |
| `{nfr_count}` | number | Count of `NFR-*` in PRD | Non-functional requirement count |
| `{doc_status}` | string | PRD Status field | e.g., `Draft`, `Approved` |
| `{doc_type_tag}` | string | tags.md `doc/*` value | Document type tag |
| `{status_tag}` | string | tags.md `status/*` value | Status tag |
| `{category_tag}` | string | tags.md `category/*` value | Category tag |
| `{prd_path}` | string | Relative path to PRD | Source file reference |

### Progress Template Variables (`progress.md`)

| Variable | Type | Source | Description |
|----------|------|--------|-------------|
| `{month}` | string | Current month `YYYY-MM` | File-level month |
| `{summary}` | string | User input or inferred | Session summary |
| `{outcomes}` | string | Bulleted list | Key outcomes |
| `{links}` | string | PR/commit references | Related links |
| `{decision_link}` | string\|null | Decision file path | Optional decision reference |

### Release Template Variables (`release.md`)

| Variable | Type | Source | Description |
|----------|------|--------|-------------|
| `{version}` | string | VERSION file or user input | Release version |
| `{summary}` | string | User input | One-liner description |
| `{changelog}` | string | Git log entries | Formatted changelog |

### Decision Template Variables (`decision.md`)

| Variable | Type | Source | Description |
|----------|------|--------|-------------|
| `{title}` | string | Decision text | Decision heading |
| `{context}` | string | Conversation context | Why this came up |
| `{options}` | string | Options considered | Alternatives |
| `{decision}` | string | The decision made | What was decided |
| `{rationale}` | string | Reasoning | Why this option |

### Dashboard Template Variables (`dashboard.md`)

| Variable | Type | Source | Description |
|----------|------|--------|-------------|
| `{repo_url}` | string | `git remote get-url origin` | Repository URL |
| `{tags_yaml}` | string | Tech detection output | YAML-formatted tag list |
| `{description}` | string | package.json or user input | Project description |

## Tag Derivation Algorithm

All shelf skills MUST follow this algorithm when assigning tags to notes.

### Step 1: Read Taxonomy

Read `plugin-shelf/tags.md` and parse namespaces. Each namespace heading (`## Name`) contains valid values as `- namespace/value` list items.

### Step 2: Derive Tags by Note Type

**Issue notes** — derive 4 tags:
1. `source/*` — Map origin: GitHub issues -> `source/github`, `.kiln/issues/` -> `source/backlog`, retrospective -> `source/retro`, user-reported -> `source/manual`
2. `severity/*` — Map severity: from issue metadata or labels. Default: `severity/medium`
3. `type/*` — Map type: from issue labels or frontmatter `type` field. Default: `type/improvement`
4. `category/*` — Infer from content: if mentions skills -> `category/skills`, agents -> `category/agents`, hooks -> `category/hooks`, templates -> `category/templates`, scaffold -> `category/scaffold`, else -> `category/workflow`

**Doc notes** — derive 3 tags:
1. `doc/*` — Map doc type: PRD -> `doc/prd`, spec -> `doc/spec`, plan -> `doc/plan`, overview -> `doc/overview`, decision -> `doc/decision`
2. `status/*` — Map status: from PRD Status field. `Draft` -> `status/open`, `Approved` -> `status/implemented`, else -> `status/in-progress`
3. `category/*` — Same inference as issue notes

**Progress notes** — derive 1 tag:
1. `status/*` — Always `status/in-progress`

**Release notes** — derive 1 tag:
1. `status/*` — Always `status/implemented`

**Decision notes** — derive 1 tag:
1. `status/*` — From frontmatter: `accepted` -> `status/implemented`, else -> `status/open`

**Dashboard notes** — tags are tech stack tags (e.g., `language/typescript`, `framework/react`), not from the standard namespaces.

### Step 3: Validate

Every tag value MUST exist in `plugin-shelf/tags.md`. If a derived tag does not exist in the taxonomy, fall back to the namespace default or omit the tag with a warning.

## Template Resolution Order

When a skill needs a template, it MUST resolve in this order:

1. Check `.shelf/templates/{name}.md` in the repo root (user override)
2. Fall back to `plugin-shelf/templates/{name}.md` (plugin default)

The skill instructions describe this as: "Read the template file. First check if `.shelf/templates/{name}.md` exists in the repo. If it does, use that. Otherwise, use `plugin-shelf/templates/{name}.md`."

## Sync Summary Format

The enhanced sync summary MUST include all counters:

```
Sync complete for '{slug}'.

  Issues:  {N} created, {N} updated, {N} closed, {N} skipped
  Docs:    {N} created, {N} updated, {N} skipped
  Tags:    {+N added, -N removed | unchanged}
  {if errors: "Errors:  {N} failed (see warnings above)"}

Sources:
  - GitHub: {N} issues ({N} open, {N} closed)
  - Backlog: {N} items from .kiln/issues/
  - Docs: {N} PRDs from docs/features/
```

## Tech Stack Detection Table

Used by both `/shelf-create` and `/shelf-sync` (FR-014). This is the canonical lookup:

| File | Tags |
|------|------|
| `package.json` | Parse deps for: `language/javascript` or `language/typescript`, `framework/react`, `framework/next`, `framework/vue`, `framework/express`, `framework/fastify` |
| `tsconfig.json` | `language/typescript` |
| `Cargo.toml` | `language/rust` |
| `pyproject.toml` or `requirements.txt` | `language/python` |
| `go.mod` | `language/go` |
| `Gemfile` | `language/ruby` |
| `Dockerfile` or `docker-compose.yml` | `infra/docker` |
| `.github/workflows/` | `infra/github-actions` |
