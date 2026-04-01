---
name: kiln-doctor
description: Validate project structure against the kiln manifest and migrate legacy paths. Diagnose mode reports issues; fix mode applies corrections with confirmation. Supports cleanup of stale artifacts and version-sync checking.
---

# Kiln Doctor — Validate and Migrate Project State

Checks the current project against the expected kiln directory structure and reports any missing directories, legacy paths, version mismatches, or stale artifacts. Can automatically fix issues when confirmed.

## User Input

```text
$ARGUMENTS
```

## Step 1: Determine Mode — FR-012

Parse user input for mode:
- `--fix` or `fix` → Fix mode (diagnose then fix all issues including version sync and QA cleanup)
- `--cleanup` → Cleanup mode (apply retention rules from manifest). Combine with `--dry-run` to preview.
- `--dry-run` → Dry-run modifier (preview changes without applying). Used with `--cleanup` or `--fix`.
- Default (no args or `--diagnose` or `diagnose`) → Diagnose mode (report only)

Multiple flags can be combined: `--fix --dry-run` previews all fixes without applying them.

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
  "version": "1.1.0",
  "directories": {
    ".kiln": { "required": true, "tracked": true },
    ".kiln/workflows": { "required": true, "tracked": true },
    ".kiln/agents": { "required": true, "tracked": false },
    ".kiln/issues": { "required": true, "tracked": true, "retention": { "archive_completed": true } },
    ".kiln/issues/completed": { "required": false, "tracked": true },
    ".kiln/qa": { "required": true, "tracked": false, "retention": { "purge_artifacts": true } },
    ".kiln/logs": { "required": true, "tracked": false, "retention": { "keep_last": 10 } }
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

### 3c: Retention Check — FR-011, FR-012

For each directory with a `retention` property in the manifest:

**`keep_last: N`** (e.g., `.kiln/logs`):
```bash
# Count files and check if exceeds limit
count=$(find .kiln/logs -maxdepth 1 -type f | wc -l | tr -d ' ')
limit=10  # from manifest retention.keep_last
if [ "$count" -gt "$limit" ]; then
  excess=$((count - limit))
  echo "RETENTION: .kiln/logs/ has $count files (limit: $limit, $excess excess)"
fi
```

**`archive_completed: true`** (e.g., `.kiln/issues`):
```bash
# Check for closed/done issues in top-level that should be archived
grep -rl 'status: \(closed\|done\)' .kiln/issues/*.md 2>/dev/null | head -20
```

**`purge_artifacts: true`** (e.g., `.kiln/qa`):
```bash
# Check for artifact files in QA subdirectories
for dir in test-results playwright-report videos traces screenshots results; do
  target=".kiln/qa/$dir"
  if [ -d "$target" ]; then
    count=$(find "$target" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
      size=$(du -sh "$target" 2>/dev/null | cut -f1)
      echo "ARTIFACTS: $target — $count files ($size)"
    fi
  fi
done
```

### 3d: Version Sync Check — FR-015, FR-017

Read the canonical version from the `VERSION` file:

```bash
canonical_version=$(cat VERSION 2>/dev/null | tr -d '[:space:]')
if [ -z "$canonical_version" ]; then
  echo "WARNING: VERSION file not found or empty — skipping version sync check"
fi
```

Determine which files to scan:

1. If `.kiln/version-sync.json` exists, read it — FR-017:
   ```json
   {
     "include": ["package.json", "plugin/package.json"],
     "exclude": ["package-lock.json"]
   }
   ```
   Scan files listed in `include`, skip files listed in `exclude`.

2. If `.kiln/version-sync.json` does not exist, use defaults:
   - Scan: `package.json`, `plugin/package.json`
   - Exclude: `package-lock.json`, `node_modules/`

For each file to scan:

```bash
# For JSON files (package.json, etc.)
file_version=$(jq -r '.version // empty' "$file" 2>/dev/null)

# For TOML files (pyproject.toml, Cargo.toml, etc.)
file_version=$(grep -m1 '^version' "$file" 2>/dev/null | sed 's/.*=\s*["'"'"']\([^"'"'"']*\)["'"'"'].*/\1/')

# For YAML files
file_version=$(grep -m1 '^version:' "$file" 2>/dev/null | sed 's/version:\s*//' | tr -d '"'"'"' ')

# For .cfg/setup.cfg files
file_version=$(grep -m1 '^version' "$file" 2>/dev/null | sed 's/version\s*=\s*//' | tr -d ' ')
```

Compare each extracted version against `canonical_version`. Report mismatches:

```
| package.json | MISMATCH | Has 0.5.0, expected 001.002.000.042 |
| plugin/package.json | OK | Matches VERSION |
```

### 3e: Report

Display results as a table:

```
## Kiln Doctor — Diagnosis

| Check | Status | Details |
|-------|--------|---------|
| .kiln/ | OK | Directory exists |
| .kiln/workflows/ | MISSING | Directory not found |
| .kiln/issues/ | OK | Directory exists |
| .kiln/qa/ | MISSING | Directory not found |
| .kiln/logs/ | OK | Directory exists |
| docs/backlog/ → .kiln/issues/ | LEGACY | 3 files to migrate |
| qa-results/ → .kiln/qa/ | OK | No legacy files |
| .kiln/logs/ retention | OVER_LIMIT | 15 files (limit: 10, 5 excess) |
| .kiln/issues/ archival | NEEDS_ARCHIVE | 2 closed issues in top-level |
| .kiln/qa/ artifacts | STALE | 52 files (54M) in artifact dirs |
| package.json version | MISMATCH | Has 0.5.0, expected 001.002.000.042 |
| plugin/package.json version | OK | Matches VERSION |

Summary: N issues found
```

If mode is **diagnose**: stop here and report.
If mode is **fix**: proceed to Step 4.
If mode is **cleanup**: proceed to Step 4a (retention cleanup only).

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

### Version Sync Fix — FR-016

For each version mismatch found in Step 3d:

If `--dry-run`:
```
Would update package.json version from 0.5.0 to 001.002.000.042
```

Otherwise, update the file:

```bash
# For JSON files — use jq to update version field
jq --arg v "$canonical_version" '.version = $v' "$file" > "$file.tmp" && mv "$file.tmp" "$file"

# For TOML files — use sed to replace version line
sed -i '' "s/^version = .*/version = \"$canonical_version\"/" "$file"

# For YAML files — use sed to replace version line
sed -i '' "s/^version:.*/version: \"$canonical_version\"/" "$file"

# For .cfg files — use sed to replace version line
sed -i '' "s/^version = .*/version = $canonical_version/" "$file"
```

Report: `Updated <file> version from <old> to <new>`

### QA Artifact Cleanup — FR-014

In fix mode, also purge stale QA artifacts (same behavior as `/kiln-cleanup`):

If `--dry-run`:
```
Would remove N files (SIZE) from .kiln/qa/ artifact directories
```

Otherwise:
```bash
for dir in test-results playwright-report videos traces screenshots results; do
  target=".kiln/qa/$dir"
  if [ -d "$target" ]; then
    find "$target" -type f -delete 2>/dev/null
  fi
done
```

Report: `Purged N QA artifact files (SIZE freed)`

**Note**: NEVER touch `.kiln/qa/tests/` or `.kiln/qa/config/` — these contain test source code and configuration, not artifacts.

## Step 4a: Retention Cleanup (only in cleanup mode) — FR-012

Apply retention rules from the manifest. Respect `--dry-run`.

### `keep_last: N` (e.g., `.kiln/logs`)

```bash
# List files sorted by modification time (oldest first), remove excess
files=$(ls -1t .kiln/logs/ 2>/dev/null)
count=$(echo "$files" | wc -l | tr -d ' ')
limit=10  # from manifest
if [ "$count" -gt "$limit" ]; then
  excess=$((count - limit))
  # Files to remove (oldest N)
  to_remove=$(echo "$files" | tail -n "$excess")
  if [ "$DRY_RUN" = true ]; then
    echo "Would remove $excess oldest files from .kiln/logs/"
  else
    echo "$to_remove" | while read f; do rm ".kiln/logs/$f"; done
    echo "Removed $excess oldest files from .kiln/logs/"
  fi
fi
```

### `archive_completed: true` (e.g., `.kiln/issues`)

```bash
# Move closed/done issues to completed/
mkdir -p .kiln/issues/completed
for file in .kiln/issues/*.md; do
  if grep -q 'status: \(closed\|done\)' "$file" 2>/dev/null; then
    if [ "$DRY_RUN" = true ]; then
      echo "Would archive: $(basename $file)"
    else
      mv "$file" .kiln/issues/completed/
      echo "Archived: $(basename $file)"
    fi
  fi
done
```

### `purge_artifacts: true` (e.g., `.kiln/qa`)

Same as QA Artifact Cleanup in Step 4 — purge files from artifact subdirectories.

## Step 5: Summary

```
## Kiln Doctor — Summary

| Action | Count |
|--------|-------|
| Directories created | N |
| Files migrated | N |
| Conflicts (manual) | N |
| Version files synced | N |
| QA artifacts purged | N |
| Logs trimmed | N |
| Issues archived | N |
| Already OK | N |

Project health: [HEALTHY / NEEDS ATTENTION / CONFLICTS FOUND]
```

If all checks pass and no fixes were needed:
```
Project health: HEALTHY — no issues found.
```

## Rules

- All operations MUST be idempotent — running doctor twice produces the same result
- NEVER delete files or directories outside of retention/cleanup operations
- ALWAYS ask for confirmation before migrating files in fix mode
- If the manifest file is not found, use the built-in default (do not fail)
- Legacy path detection checks for files, not just directory existence
- Report conflicts clearly — do not attempt automatic merges
- Version sync MUST respect `.kiln/version-sync.json` include/exclude lists when present — FR-017
- Version sync MUST NOT scan `package-lock.json` or `node_modules/` by default — FR-015
- QA cleanup MUST NOT touch `.kiln/qa/tests/` or `.kiln/qa/config/` — FR-014
- Retention cleanup MUST respect `--dry-run` flag — FR-012
