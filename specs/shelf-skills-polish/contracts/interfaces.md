# Interface Contracts: Shelf Skills Polish

## 1. Workflow JSON Files

### 1.1 shelf-create.json (`plugin-shelf/workflows/shelf-create.json`)

```json
{
  "name": "shelf-create",
  "version": "1.0.0",
  "steps": [
    {
      "id": "read-shelf-config",
      "type": "command",
      "command": "<bash: read .shelf-config or derive defaults from git remote>",
      "output": ".wheel/outputs/read-shelf-config.txt"
    },
    {
      "id": "detect-repo-progress",
      "type": "command",
      "command": "<bash: count specs, code dirs, tests, commits, issues, VERSION, .kiln/>",
      "output": ".wheel/outputs/detect-repo-progress.txt"
    },
    {
      "id": "detect-tech-stack",
      "type": "command",
      "command": "<bash: ls config files, parse package.json deps>",
      "output": ".wheel/outputs/detect-tech-stack.txt"
    },
    {
      "id": "get-repo-metadata",
      "type": "command",
      "command": "<bash: git remote URL, package.json description>",
      "output": ".wheel/outputs/get-repo-metadata.txt"
    },
    {
      "id": "resolve-vault-path",
      "type": "agent",
      "instruction": "<navigate from vault root via list_files('/'), verify/create base_path>",
      "context_from": ["read-shelf-config"],
      "output": ".wheel/outputs/resolve-vault-path.txt"
    },
    {
      "id": "check-duplicate",
      "type": "agent",
      "instruction": "<list files at target project path, abort if project exists>",
      "context_from": ["read-shelf-config", "resolve-vault-path"],
      "output": ".wheel/outputs/check-duplicate.txt"
    },
    {
      "id": "create-project",
      "type": "agent",
      "instruction": "<create dashboard + about + directories using templates, set status from progress signals>",
      "context_from": ["read-shelf-config", "detect-repo-progress", "detect-tech-stack", "get-repo-metadata", "resolve-vault-path", "check-duplicate"],
      "output": ".wheel/outputs/create-project-result.md"
    },
    {
      "id": "write-shelf-config",
      "type": "command",
      "command": "<bash: write .shelf-config file if it doesn't already exist>",
      "output": ".wheel/outputs/write-shelf-config-result.txt",
      "terminal": true
    }
  ]
}
```

**Step contracts**:

- **read-shelf-config**: Output format — `base_path=<value>`, `slug=<value>`, `dashboard_path=<value>`, one per line. Falls back to git remote defaults if `.shelf-config` missing.
- **detect-repo-progress**: Output format — key=value pairs: `spec_count=N`, `code_dirs=<comma-list>`, `test_file_count=N`, `version=<value>`, `commit_count=N`, `open_issues=N`, `kiln_present=yes|no`, `prd_count=N`. Used by `create-project` to set initial status.
- **detect-tech-stack**: Same output format as `shelf-full-sync` step `detect-tech-stack`. Lists detected config files and parsed dependencies.
- **get-repo-metadata**: Output format — `repo_url=<value>`, `description=<value>`.
- **resolve-vault-path**: Agent must call `mcp__obsidian-projects__list_files({ directory: "/" })`, navigate to base_path, create directories if missing. Output: confirmed vault base path.
- **check-duplicate**: Agent must call `mcp__obsidian-projects__list_files({ path: "<base_path>/<slug>" })`. If files returned: write "DUPLICATE: project exists" and the workflow should not proceed to create-project. If empty/not found: write "OK: no existing project".
- **create-project**: Agent reads template files from `plugin-shelf/templates/`, renders with context data, creates via MCP. Must set initial status based on progress signals per FR-006. Creates: dashboard, about.md, progress/.gitkeep, releases/.gitkeep, issues/.gitkeep, decisions/.gitkeep.
- **write-shelf-config**: Writes `.shelf-config` only if it doesn't already exist. Reads slug and base_path from read-shelf-config output.

### 1.2 shelf-repair.json (`plugin-shelf/workflows/shelf-repair.json`)

```json
{
  "name": "shelf-repair",
  "version": "1.0.0",
  "steps": [
    {
      "id": "read-shelf-config",
      "type": "command",
      "command": "<bash: read .shelf-config or derive defaults>",
      "output": ".wheel/outputs/read-shelf-config.txt"
    },
    {
      "id": "read-current-template",
      "type": "command",
      "command": "<bash: cat plugin-shelf/templates/dashboard.md>",
      "output": ".wheel/outputs/read-current-template.txt"
    },
    {
      "id": "read-existing-dashboard",
      "type": "agent",
      "instruction": "<read current dashboard from Obsidian via MCP, extract all sections>",
      "context_from": ["read-shelf-config"],
      "output": ".wheel/outputs/read-existing-dashboard.md"
    },
    {
      "id": "generate-diff-report",
      "type": "agent",
      "instruction": "<compare dashboard to template, report structural differences, flag non-canonical status>",
      "context_from": ["read-shelf-config", "read-current-template", "read-existing-dashboard"],
      "output": ".wheel/outputs/shelf-repair-diff.md"
    },
    {
      "id": "apply-repairs",
      "type": "agent",
      "instruction": "<apply template structure, preserve user content, normalize status labels>",
      "context_from": ["read-shelf-config", "read-current-template", "read-existing-dashboard", "generate-diff-report"],
      "output": ".wheel/outputs/shelf-repair-result.md"
    },
    {
      "id": "verify-repair",
      "type": "agent",
      "instruction": "<re-read dashboard, confirm it matches template structure>",
      "context_from": ["read-shelf-config", "apply-repairs"],
      "output": ".wheel/outputs/shelf-repair-verify.md",
      "terminal": true
    }
  ]
}
```

**Step contracts**:

- **read-current-template**: Output is the raw content of `plugin-shelf/templates/dashboard.md`.
- **read-existing-dashboard**: Agent reads dashboard via `mcp__obsidian-projects__read_file`. Output includes full content with sections labeled.
- **generate-diff-report**: Output format — Markdown with sections: `## Status`, `## Structural Changes`, `## Content Preserved`, `## Non-Canonical Labels Found`. Lists each change with before/after.
- **apply-repairs**: Agent rebuilds dashboard with template structure. Preserves: `## Human Needed` items, `## Feedback` content, `## Feedback Log` content, all progress entries. Normalizes status using canonical mapping from `status-labels.md`. Updates via `mcp__obsidian-projects__update_file`.
- **verify-repair**: Agent re-reads dashboard and confirms structure matches. Reports pass/fail.

### 1.3 shelf-full-sync.json Summary Step (appended to existing workflow)

```json
{
  "id": "generate-sync-summary",
  "type": "command",
  "command": "<bash: read all prior outputs, extract counts, format summary>",
  "output": ".wheel/outputs/shelf-full-sync-summary.md"
}
```

The existing `push-progress-update` step loses its `"terminal": true` flag. The new `generate-sync-summary` step becomes the terminal step.

**Output format**:
```markdown
# Shelf Full Sync Summary

**Date**: YYYY-MM-DD HH:MM:SS
**Project**: <slug>

## Issues
- Created: N
- Updated: N
- Closed: N
- Skipped: N

## Docs
- Created: N
- Updated: N
- Skipped: N

## Tags
- Added: N
- Removed: N
- Status: changed|unchanged

## Progress
- Entry appended: yes|no

## Errors
- Count: N
```

## 2. Configuration File

### 2.1 status-labels.md (`plugin-shelf/status-labels.md`)

Markdown file with a table defining canonical statuses. Format:

```markdown
# Canonical Project Status Labels

| Status | Description | Non-Canonical Equivalents |
|--------|-------------|--------------------------|
| idea | ... | concept, planned, not started |
| active | ... | in-progress, in progress, wip, doing |
| paused | ... | on hold, hold, waiting |
| blocked | ... | stuck, needs help |
| completed | ... | done, finished, shipped |
| archived | ... | deprecated, abandoned, inactive |
```

Skills reference this file by reading it and using the table for validation and normalization.

## 3. Skill Files

### 3.1 shelf-create/SKILL.md (rewritten — FR-007)

The skill becomes a thin wrapper:

```markdown
---
name: shelf-create
description: Scaffold a new project in Obsidian via wheel workflow.
---

# shelf-create — Scaffold New Project in Obsidian

## User Input
$ARGUMENTS

## Steps
1. Parse user input for project name override
2. Run: /wheel-run shelf:shelf-create
3. Report results from workflow output
```

The full logic moves to the workflow. The skill validates input, launches the workflow, and reports results.

### 3.2 shelf-repair/SKILL.md (new)

```markdown
---
name: shelf-repair
description: Re-apply current templates to an existing Obsidian project. Preserves user content, normalizes status labels.
---

# shelf-repair — Repair Existing Project

## User Input
$ARGUMENTS

## Steps
1. Validate project exists (check .shelf-config)
2. Run: /wheel-run shelf:shelf-repair
3. Report diff and results from workflow output
```

### 3.3 Existing Skills Updates (shelf-update, shelf-status, shelf-sync)

Each skill receives a new section referencing canonical status labels:

```markdown
## Status Label Validation (FR-013)

Before setting or displaying a project status, read the canonical status list from `plugin-shelf/status-labels.md`.

- If the status is in the canonical list: use it as-is
- If the status matches a non-canonical equivalent: normalize to the canonical value and warn the user
- If the status is unrecognized: warn "Unknown status '{value}' — canonical values are: idea, active, paused, blocked, completed, archived"
```

This section is added to `shelf-update` (which sets status), `shelf-status` (which displays status), and `shelf-sync` (which may encounter status values during sync).

## 4. Dependencies Between Artifacts

```
status-labels.md (standalone, no deps)
    ↓ referenced by
shelf-create.json → shelf-create/SKILL.md (thin wrapper)
shelf-repair.json → shelf-repair/SKILL.md (thin wrapper)
shelf-full-sync.json (modified, standalone)
shelf-update/SKILL.md (modified, refs status-labels.md)
shelf-status/SKILL.md (modified, refs status-labels.md)
shelf-sync/SKILL.md (modified, refs status-labels.md)
```
