---
name: kiln-cleanup
description: Remove stale QA artifacts from .kiln/qa/. Supports --dry-run for preview.
---

# Kiln Cleanup — Purge Stale QA Artifacts

Removes accumulated QA artifacts (test results, reports, videos, traces, screenshots) from `.kiln/qa/` to reclaim disk space. Supports `--dry-run` to preview what would be removed without deleting anything.

## User Input

```text
$ARGUMENTS
```

## Step 1: Parse Arguments — FR-013

Parse user input for flags:
- `--dry-run` or `dry-run` → Preview mode (list files without deleting)
- Default (no args) → Delete mode (remove artifacts)

## Step 2: Scan QA Artifacts — FR-013

Scan the following directories under `.kiln/qa/` for files:

```bash
# Count files and total size in each artifact directory
for dir in test-results playwright-report videos traces screenshots results; do
  target=".kiln/qa/$dir"
  if [ -d "$target" ]; then
    count=$(find "$target" -type f 2>/dev/null | wc -l | tr -d ' ')
    size=$(du -sh "$target" 2>/dev/null | cut -f1)
    echo "$target: $count files, $size"
  fi
done
```

If no `.kiln/qa/` directory exists, report "No QA artifacts directory found. Nothing to clean." and stop.

If no files are found in any subdirectory, report "QA artifacts directory is already clean. Nothing to remove." and stop.

Display a summary table:

```
## QA Artifact Scan

| Directory | Files | Size |
|-----------|-------|------|
| .kiln/qa/test-results/ | 12 | 4.2M |
| .kiln/qa/playwright-report/ | 8 | 1.1M |
| .kiln/qa/videos/ | 3 | 28M |
| .kiln/qa/traces/ | 5 | 12M |
| .kiln/qa/screenshots/ | 20 | 8.5M |
| .kiln/qa/results/ | 4 | 256K |
| **Total** | **52** | **54M** |
```

## Step 2.5: Scan Backlog Issues for Archival — FR-009

Scan `.kiln/issues/` for issue files with `status: prd-created` or `status: completed` in their frontmatter:

```bash
echo "=== ISSUE ARCHIVAL SCAN ==="
ARCHIVE_COUNT=0
if [ -d ".kiln/issues" ]; then
  for file in .kiln/issues/*.md; do
    [ -f "$file" ] || continue
    STATUS=$(grep -m1 '^status:' "$file" 2>/dev/null | sed 's/status:\s*//' | tr -d ' ')
    if [ "$STATUS" = "prd-created" ] || [ "$STATUS" = "completed" ]; then
      ARCHIVE_COUNT=$((ARCHIVE_COUNT + 1))
      echo "ARCHIVE: $(basename "$file") — status: $STATUS"
    fi
  done
fi
echo "Total issues to archive: $ARCHIVE_COUNT"
```

If no archivable issues are found, report "No completed or prd-created issues to archive." and continue to Step 3.

Display a summary table:

```
## Issue Archival Scan

| File | Status | Action |
|------|--------|--------|
| 2026-03-30-missing-feature.md | prd-created | Archive |
| 2026-03-31-bug-fix.md | completed | Archive |
| **Total** | | **N issues** |
```

### Dry-Run Mode (Issue Archival)

If `--dry-run` was specified, display the scan results and note:

```
Would archive N issues from .kiln/issues/ to .kiln/issues/completed/:
- 2026-03-30-missing-feature.md (prd-created)
- 2026-03-31-bug-fix.md (completed)

No files were moved. Run without --dry-run to archive.
```

### Delete Mode (Issue Archival)

Create `.kiln/issues/completed/` if it does not exist, then move matching issues:

```bash
mkdir -p .kiln/issues/completed
for file in .kiln/issues/*.md; do
  [ -f "$file" ] || continue
  STATUS=$(grep -m1 '^status:' "$file" 2>/dev/null | sed 's/status:\s*//' | tr -d ' ')
  if [ "$STATUS" = "prd-created" ] || [ "$STATUS" = "completed" ]; then
    mv "$file" .kiln/issues/completed/
    echo "Archived: $(basename "$file")"
  fi
done
```

Display results:

```
## Issue Archival — Complete

Archived N issues to .kiln/issues/completed/:
- 2026-03-30-missing-feature.md (prd-created)
- 2026-03-31-bug-fix.md (completed)
```

## Step 3: Purge or Preview — FR-013

### Dry-Run Mode

If `--dry-run` was specified, display the scan results from Step 2 and stop:

```
## Kiln Cleanup — Dry Run

Would remove 52 files (54M) from .kiln/qa/:
- .kiln/qa/test-results/ — 12 files (4.2M)
- .kiln/qa/playwright-report/ — 8 files (1.1M)
- .kiln/qa/videos/ — 3 files (28M)
- .kiln/qa/traces/ — 5 files (12M)
- .kiln/qa/screenshots/ — 20 files (8.5M)
- .kiln/qa/results/ — 4 files (256K)

No files were deleted. Run without --dry-run to purge.
```

### Delete Mode

Remove all files from the artifact directories (preserve the directory structure):

```bash
for dir in test-results playwright-report videos traces screenshots results; do
  target=".kiln/qa/$dir"
  if [ -d "$target" ]; then
    find "$target" -type f -delete 2>/dev/null
  fi
done
```

Display results:

```
## Kiln Cleanup — Complete

Removed 52 files (54M) from .kiln/qa/:
- .kiln/qa/test-results/ — 12 files removed
- .kiln/qa/playwright-report/ — 8 files removed
- .kiln/qa/videos/ — 3 files removed
- .kiln/qa/traces/ — 5 files removed
- .kiln/qa/screenshots/ — 20 files removed
- .kiln/qa/results/ — 4 files removed

Directory structure preserved. QA artifacts purged.
```

## Rules

- NEVER delete the directory structure itself — only files within artifact directories
- NEVER touch `.kiln/qa/tests/` or `.kiln/qa/config/` — these contain test source code and configuration, not artifacts
- Always show a summary of what was (or would be) removed
- Operations MUST be idempotent — running cleanup twice produces the same result
- If `.kiln/qa/` does not exist, report gracefully and stop (do not fail)
