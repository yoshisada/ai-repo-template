# Data Model: Shelf Config Artifact

**Date**: 2026-04-03

## Entities

### `.shelf-config` File

A plain-text key-value configuration file stored at the repo root.

**Fields**:

| Key | Type | Required | Description | Example |
|-----|------|----------|-------------|---------|
| `base_path` | string | Yes | Obsidian vault path prefix for project files | `@second-brain/projects` |
| `slug` | string | Yes | Project slug used in vault path construction | `plugin-shelf` |
| `dashboard_path` | string | Yes | Full resolved path to the project dashboard file | `@second-brain/projects/plugin-shelf/plugin-shelf.md` |

**Format rules**:
- One key per line
- Format: `key = value`
- Lines starting with `#` are comments
- Empty lines are ignored
- Unknown keys are ignored by consumers
- Whitespace around `=` is tolerated (trimmed during parsing)

**Example**:
```ini
# Shelf configuration — maps this repo to its Obsidian project
base_path = @second-brain/projects
slug = plugin-shelf
dashboard_path = @second-brain/projects/plugin-shelf/plugin-shelf.md
```

**Validation rules**:
- `base_path` and `slug` are required — if either is missing, the file is considered malformed
- `dashboard_path` is derived from `base_path` and `slug` but stored explicitly for convenience
- Values must not be empty strings
- No quoting required — values are taken as literal strings after trimming

**State transitions**: None — the file is static after creation. Users may manually edit it.

**Relationships**: Read by all 6 shelf skills during path resolution. Written by `shelf-create` only.
