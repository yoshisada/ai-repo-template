---
name: kiln-doctor
description: Validate project structure against the kiln manifest and migrate legacy paths. Diagnose mode reports issues; fix mode applies corrections with confirmation. Use to upgrade from speckit-harness or verify .kiln/ directory health.
---

# Kiln Doctor — Validate and Migrate Project State

Checks the current project against the expected kiln directory structure and reports any missing directories, legacy paths, or misplaced files. Can automatically fix issues when confirmed.

## User Input

```text
$ARGUMENTS
```

## Step 1: Determine Mode

Parse user input for mode:
- `--fix` or `fix` → Fix mode (diagnose then fix)
- Default (no args or `--diagnose` or `diagnose`) → Diagnose mode (report only)

## Step 2: Load Manifest

Read the manifest from the plugin templates directory. The manifest is located at the plugin's `templates/kiln-manifest.json` path. To find it:

```bash
# The manifest is shipped with the kiln plugin
# Look for it relative to the plugin installation
find . -path "*/kiln/templates/kiln-manifest.json" -o -path "*/node_modules/@yoshisada/kiln/templates/kiln-manifest.json" 2>/dev/null | head -1
```

If the manifest cannot be found, use this built-in default:

```json
{
  "version": "1.0.0",
  "directories": {
    ".kiln": { "required": true, "tracked": true },
    ".kiln/workflows": { "required": true, "tracked": true },
    ".kiln/agents": { "required": true, "tracked": false },
    ".kiln/issues": { "required": true, "tracked": true },
    ".kiln/qa": { "required": true, "tracked": false },
    ".kiln/logs": { "required": true, "tracked": false }
  },
  "migrations": {
    "docs/backlog/": ".kiln/issues/",
    "qa-results/": ".kiln/qa/"
  }
}
```

## Step 3: Diagnose

Check the project against the manifest:

### 3a: Directory Structure Check

For each directory in `manifest.directories`:
- Check if the directory exists
- Report status: `OK`, `MISSING`

### 3b: Legacy Path Detection

For each entry in `manifest.migrations` (old_path → new_path):
- Check if the old path exists AND contains files
- If old path has files: report as `LEGACY` — needs migration
- If old path is empty or missing: report as `OK` — no migration needed
- If BOTH old and new paths have files: report as `CONFLICT` — manual merge needed

### 3c: Report

Display results as a table:

```
## Kiln Doctor — Diagnosis

| Check | Status | Details |
|-------|--------|---------|
| .kiln/ | OK | Directory exists |
| .kiln/workflows/ | MISSING | Directory not found |
| .kiln/agents/ | OK | Directory exists |
| .kiln/issues/ | OK | Directory exists |
| .kiln/qa/ | MISSING | Directory not found |
| .kiln/logs/ | OK | Directory exists |
| docs/backlog/ → .kiln/issues/ | LEGACY | 3 files to migrate |
| qa-results/ → .kiln/qa/ | OK | No legacy files |

Summary: 2 issues found (2 MISSING, 0 LEGACY, 0 CONFLICT)
```

If mode is **diagnose**: stop here and report.
If mode is **fix**: proceed to Step 4.

## Step 4: Fix (only in fix mode)

For each issue found in diagnosis:

### Missing Directories

```bash
mkdir -p <directory>
```

Report: `Created <directory>`

### Legacy Paths (no conflict)

For each legacy path with files to migrate:

1. Show the user what will happen:
   ```
   Migrate docs/backlog/ → .kiln/issues/
   Files to move: 3
   - 2026-03-30-missing-dockerfile.md
   - 2026-03-31-qa-version-verification.md
   - 2026-03-31-dot-directory-for-storage.md
   ```

2. Ask: "Proceed with this migration? (yes/no)"

3. If confirmed:
   ```bash
   mkdir -p <new_path>
   cp -r <old_path>/* <new_path>/
   ```
   Report: `Migrated N files from <old_path> to <new_path>`

   Note: Do NOT delete the old directory — leave it for the user to clean up after verifying the migration.

### Conflicts (both paths have files)

Report the conflict and do NOT auto-fix:
```
CONFLICT: Both docs/backlog/ and .kiln/issues/ contain files.
Manual merge required. Review both directories and consolidate.
```

## Step 5: Summary

```
## Kiln Doctor — Summary

| Action | Count |
|--------|-------|
| Directories created | N |
| Files migrated | N |
| Conflicts (manual) | N |
| Already OK | N |

Project health: [HEALTHY / NEEDS ATTENTION / CONFLICTS FOUND]
```

If all checks pass and no fixes were needed:
```
Project health: HEALTHY — no issues found.
```

## Rules

- All operations MUST be idempotent — running doctor twice produces the same result
- NEVER delete files or directories — only create and copy
- ALWAYS ask for confirmation before migrating files in fix mode
- If the manifest file is not found, use the built-in default (do not fail)
- Legacy path detection checks for files, not just directory existence
- Report conflicts clearly — do not attempt automatic merges
