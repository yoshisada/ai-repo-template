# Interface Contracts: Shelf Config Artifact

**Date**: 2026-04-03
**Feature**: Shelf Config Artifact

## Contract 1: `.shelf-config` File Format

The `.shelf-config` file is a plain-text key-value file at the repo root with the following format:

```ini
# Shelf configuration — maps this repo to its Obsidian project
base_path = @second-brain/projects
slug = plugin-shelf
dashboard_path = @second-brain/projects/plugin-shelf/plugin-shelf.md
```

### Format Rules

- **Encoding**: UTF-8 plain text
- **Line format**: `key = value` (spaces around `=` are optional but recommended)
- **Comments**: Lines starting with `#` are ignored
- **Blank lines**: Ignored
- **Unknown keys**: Ignored by consumers (forward compatibility)
- **No quoting**: Values are literal strings, trimmed of leading/trailing whitespace

### Required Keys

| Key | Description | Validation |
|-----|-------------|------------|
| `base_path` | Obsidian vault path prefix | Non-empty string |
| `slug` | Project slug for vault paths | Non-empty string, no spaces |
| `dashboard_path` | Full path to project dashboard | Non-empty string, must equal `{base_path}/{slug}/{slug}.md` |

### Parsing Algorithm (for reading skills)

Each skill that reads `.shelf-config` MUST use this algorithm:

```
1. Check if .shelf-config exists in the repo root
2. If it exists:
   a. Read the file contents
   b. For each line:
      - Skip lines starting with # (comments)
      - Skip empty/whitespace-only lines
      - Split on first = to get key and value
      - Trim whitespace from both key and value
   c. Extract base_path and slug values
   d. If both base_path and slug are present and non-empty:
      → Use these values (do NOT derive from git remote)
   e. If either is missing or empty:
      → Warn user: ".shelf-config is malformed — missing {key}. Falling back to defaults."
      → Fall through to default behavior
3. If .shelf-config does not exist:
   → Use default behavior (derive slug from git remote, base_path = "projects")
```

**Priority order** (highest to lowest):
1. Explicit user argument (if provided as command argument)
2. `.shelf-config` values (if file exists and is valid)
3. Default behavior (git remote derivation + `projects` base path)

## Contract 2: shelf-create Config Writing

After successfully creating the Obsidian project (after all MCP calls succeed), `shelf-create` MUST:

```
1. Determine the confirmed slug and base_path values used during creation
2. Compute dashboard_path = {base_path}/{slug}/{slug}.md
3. Write .shelf-config to the repo root with this exact content:

   # Shelf configuration — maps this repo to its Obsidian project
   base_path = {base_path}
   slug = {slug}
   dashboard_path = {dashboard_path}

4. Report the config file creation in the Step 10 summary
```

### Confirmation Flow (FR-007)

Before writing `.shelf-config`, `shelf-create` MUST confirm with the user:

```
The following will be saved to .shelf-config:
  base_path: {base_path}
  slug: {slug}
  dashboard_path: {base_path}/{slug}/{slug}.md

Confirm? (Y/n)
```

This confirmation happens AFTER the Obsidian project is created but BEFORE writing the config file.

## Contract 3: Unified Path Resolution Steps (replacement for Steps 1-2 in all skills)

Every shelf skill currently has separate Step 1 (Resolve Project Slug) and Step 2 (Resolve Base Path). These MUST be replaced with a unified path resolution block:

### New Step 1: Resolve Project Identity

```
1. If .shelf-config exists in the repo root:
   a. Parse it (using the parsing algorithm above)
   b. If valid: set $SLUG = slug value, $BASE_PATH = base_path value
   c. If invalid: warn user, continue to step 2
2. If no valid .shelf-config:
   a. If user provided a project name argument: use it as $SLUG
   b. Otherwise: run git remote get-url origin, extract repo name as $SLUG
   c. Set $BASE_PATH = "projects" (default)
3. All vault paths use: {$BASE_PATH}/{$SLUG}/...
```

This replaces the current two-step process in all 5 reading skills (shelf-sync, shelf-update, shelf-status, shelf-feedback, shelf-release).

For `shelf-create`, the existing Step 1 (slug resolution) and Step 2 (base path resolution) remain mostly the same, but `.shelf-config` reading is updated to also extract the `slug` value (not just `base_path`). Additionally, a new step is added after project creation to write the config.

## Contract 4: Skill File Modification Map

| Skill | Change Type | Details |
|-------|-------------|---------|
| `shelf-create/SKILL.md` | Add new step | Add config writing step after Step 9 (directory structure creation), before Step 10 (report). Add confirmation prompt per FR-007. Update Step 2 to also read `slug` from config. |
| `shelf-sync/SKILL.md` | Replace Steps 1-2 | Replace with unified "Resolve Project Identity" step. Renumber subsequent steps. |
| `shelf-update/SKILL.md` | Replace Steps 1-2 | Replace with unified "Resolve Project Identity" step. Renumber subsequent steps. |
| `shelf-status/SKILL.md` | Replace Steps 1-2 | Replace with unified "Resolve Project Identity" step. Renumber subsequent steps. |
| `shelf-feedback/SKILL.md` | Replace Steps 1-2 | Replace with unified "Resolve Project Identity" step. Renumber subsequent steps. |
| `shelf-release/SKILL.md` | Replace Steps 1-2 | Replace with unified "Resolve Project Identity" step. Renumber subsequent steps. |
