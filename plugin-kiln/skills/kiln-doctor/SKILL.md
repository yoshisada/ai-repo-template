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

### 3g: CLAUDE.md Drift Check (cheap signals only)

Run the `cost: cheap` subset of the `plugin-kiln/rubrics/claude-md-usefulness.md` rubric against the repo's `CLAUDE.md` and report a single row in the diagnosis table. Performance budget: **<2s** (cheap-greppy only, no LLM). For the full rubric — including editorial signals and a proposed diff — invoke `/kiln:kiln-claude-audit` directly.

Resolution logic for the rubric path mirrors the manifest resolution above:

```bash
# Try the plugin install paths first; fall back to source-repo layout.
RUBRIC_PATH=$(find . -path "*/kiln/rubrics/claude-md-usefulness.md" -o -path "*/node_modules/@yoshisada/kiln/rubrics/claude-md-usefulness.md" 2>/dev/null | head -1)
if [ -z "$RUBRIC_PATH" ] && [ -f "plugin-kiln/rubrics/claude-md-usefulness.md" ]; then
  RUBRIC_PATH="plugin-kiln/rubrics/claude-md-usefulness.md"
fi
```

If `RUBRIC_PATH` cannot be resolved OR `CLAUDE.md` does not exist at the repo root: emit one row with `| CLAUDE.md drift | N/A | rubric or CLAUDE.md not found — skipped |` and continue. This is NOT an error — doctor keeps running.

Otherwise, run ONLY the cheap rules (identified by `cost: cheap` in the rubric YAML-ish block):

**`load-bearing-section`** — does not count toward drift; it only protects sections from being falsely flagged by other rules.

**`stale-migration-notice`**:
```bash
if grep -q -E '^> \*\*Migration Notice\*\*|^> Old skill names|renamed from' CLAUDE.md; then
  # Check blockquote age from git log
  MIG_AGE_DAYS=$(( ( $(date +%s) - $(git log --reverse --format=%at -- CLAUDE.md | head -1) ) / 86400 ))
  MIG_MAX_AGE=60  # default; override from .kiln/claude-md-audit.config if present
  if [ -f ".kiln/claude-md-audit.config" ]; then
    OVR=$(grep -E '^migration_notice_max_age_days' .kiln/claude-md-audit.config | head -1 | sed 's/.*[=:] *//' | tr -d '[:space:]')
    [ -n "$OVR" ] && MIG_MAX_AGE="$OVR"
  fi
  if [ "$MIG_AGE_DAYS" -gt "$MIG_MAX_AGE" ]; then
    DRIFT_COUNT=$((DRIFT_COUNT + 1))
  fi
fi
```

**`recent-changes-overflow`** (claude-audit-quality FR-017 — gracefully handles absent section + reconciliation with `recent-changes-anti-pattern`):
```bash
# Pre-check: does the file have a ## Recent Changes section at all?
# When absent, treat as no drift (FR-017 — absence is not a missing-section
# coverage failure; the substance rule recent-changes-anti-pattern handles
# the "should this section exist?" question separately).
if grep -qE '^## Recent Changes$' CLAUDE.md; then
  # Count bullets under "## Recent Changes" (lines starting with "- " within the section).
  RC_COUNT=$(awk '/^## Recent Changes/{flag=1;next} /^## /{flag=0} flag && /^- /' CLAUDE.md | wc -l | tr -d ' ')
  RC_LIMIT=5
  if [ -f ".kiln/claude-md-audit.config" ]; then
    OVR=$(grep -E '^recent_changes_keep_last_n' .kiln/claude-md-audit.config | head -1 | sed 's/.*[=:] *//' | tr -d '[:space:]')
    [ -n "$OVR" ] && RC_LIMIT="$OVR"
  fi
  if [ "$RC_COUNT" -gt "$RC_LIMIT" ]; then
    DRIFT_COUNT=$((DRIFT_COUNT + 1))
  fi
fi
# When the section is absent: emit no signal, no DRIFT_COUNT increment, full stop.
# The /kiln:kiln-claude-audit skill (full rubric) is where recent-changes-anti-pattern
# fires when ## Recent Changes is present — its removal proposal supersedes this
# rule's archive-candidate proposal in the same audit (FR-017 reconciliation).
```

**`active-technologies-overflow`**:
```bash
AT_COUNT=$(awk '/^## Active Technologies/{flag=1;next} /^## /{flag=0} flag && /^- /' CLAUDE.md | wc -l | tr -d ' ')
AT_LIMIT=5
if [ -f ".kiln/claude-md-audit.config" ]; then
  OVR=$(grep -E '^active_technologies_keep_last_n' .kiln/claude-md-audit.config | head -1 | sed 's/.*[=:] *//' | tr -d '[:space:]')
  [ -n "$OVR" ] && AT_LIMIT="$OVR"
fi
if [ "$AT_COUNT" -gt "$AT_LIMIT" ]; then
  DRIFT_COUNT=$((DRIFT_COUNT + 1))
fi
```

Append ONE row to the diagnosis table (Step 3e):

- `DRIFT_COUNT == 0`: `| CLAUDE.md drift | OK | No cheap signals triggered |`
- `DRIFT_COUNT > 0`: `| CLAUDE.md drift | DRIFT | N cheap signals; run /kiln:kiln-claude-audit |`

Doctor does NOT write an audit log. That's exclusively the `/kiln:kiln-claude-audit` skill's job. Doctor's subcheck is a tripwire pointing at the dedicated skill.

### 3h: Structural hygiene drift (cheap signals only)

Run the `cost: cheap` subset of the `plugin-kiln/rubrics/structural-hygiene.md` rubric against the repo's structural state and report a single row in the diagnosis table. Performance budget: **<2s** (cheap-greppy only, no `gh`, no LLM). For the full rubric — including the editorial `merged-prd-not-archived` rule that needs `gh` — invoke `/kiln:kiln-hygiene` directly.

Resolution logic for the rubric path mirrors 3g:

```bash
RUBRIC_PATH=$(find . -path "*/kiln/rubrics/structural-hygiene.md" -o -path "*/node_modules/@yoshisada/kiln/rubrics/structural-hygiene.md" 2>/dev/null | head -1)
if [ -z "$RUBRIC_PATH" ] && [ -f "plugin-kiln/rubrics/structural-hygiene.md" ]; then
  RUBRIC_PATH="plugin-kiln/rubrics/structural-hygiene.md"
fi
```

If `RUBRIC_PATH` cannot be resolved OR `.kiln/` does not exist at the repo root: emit one row with `| Structural hygiene drift | N/A | rubric or .kiln/ not found — skipped |` and continue. This is NOT an error — doctor keeps running (parity with 3g N/A pattern).

Otherwise, run ONLY the cheap rules (identified by `cost: cheap` in the rubric YAML-ish block). Today: `orphaned-top-level-folder` + `unreferenced-kiln-artifact`. NOT `merged-prd-not-archived` (its cost is editorial — needs `gh`). New rules added to the rubric are auto-included if their `cost: cheap` YAML flag is set.

**`orphaned-top-level-folder`** (contract §6 of `specs/kiln-structural-hygiene/`):

```bash
HYGIENE_DRIFT_COUNT=0

# Manifest resolution (reuse Step 2 manifest path)
MANIFEST_DIRS=$(jq -r '.directories | keys[]' "$MANIFEST_PATH" 2>/dev/null | sed 's:^\./::; s:/*$::')
TOP_LEVEL_MANIFEST=$(echo "$MANIFEST_DIRS" | awk -F/ '{print $1}' | sort -u)

ORPHAN_MIN_AGE=30
if [ -f ".kiln/structural-hygiene.config" ]; then
  OVR=$(grep -E '^orphaned-top-level-folder\.min_age_days' .kiln/structural-hygiene.config | head -1 | sed 's/.*[=:] *//' | tr -d '[:space:]')
  [ -n "$OVR" ] && ORPHAN_MIN_AGE="$OVR"
fi

while IFS= read -r dir; do
  [ -z "$dir" ] && continue
  echo "$TOP_LEVEL_MANIFEST" | grep -Fxq "$dir" && continue
  if grep -RlF "${dir}/" plugin-*/ templates/ 2>/dev/null | head -1 | grep -q . ; then continue; fi
  find "$dir" -maxdepth 0 -type d -mtime "+$ORPHAN_MIN_AGE" | grep -q . || continue
  HYGIENE_DRIFT_COUNT=$((HYGIENE_DRIFT_COUNT + 1))
done < <(find . -maxdepth 1 -mindepth 1 -type d ! -name '.git' ! -name 'node_modules' | sed 's:^\./::')
```

**`unreferenced-kiln-artifact`** (contract §7):

```bash
UNREF_MIN_AGE=60
if [ -f ".kiln/structural-hygiene.config" ]; then
  OVR=$(grep -E '^unreferenced-kiln-artifact\.min_age_days' .kiln/structural-hygiene.config | head -1 | sed 's/.*[=:] *//' | tr -d '[:space:]')
  [ -n "$OVR" ] && UNREF_MIN_AGE="$OVR"
fi

for art_dir in .kiln/logs .kiln/qa/test-results .kiln/qa/playwright-report .kiln/qa/videos .kiln/qa/traces .kiln/qa/screenshots .kiln/qa/results .kiln/state; do
  [ -d "$art_dir" ] || continue
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    base=$(basename "$file")
    case "$base" in .gitkeep|README.md) continue ;; esac
    if compgen -G ".wheel/state_*.json" >/dev/null 2>&1; then
      if grep -lF "$base" .wheel/state_*.json 2>/dev/null | head -1 | grep -q . ; then continue; fi
    fi
    HYGIENE_DRIFT_COUNT=$((HYGIENE_DRIFT_COUNT + 1))
  done < <(find "$art_dir" -type f -mtime "+$UNREF_MIN_AGE" 2>/dev/null)
done
```

Append ONE row to the diagnosis table (Step 3e):

- `HYGIENE_DRIFT_COUNT == 0`: `| Structural hygiene drift | OK    | No cheap signals triggered |`
- `HYGIENE_DRIFT_COUNT > 0`:  `| Structural hygiene drift | DRIFT | N cheap signals; run /kiln:kiln-hygiene |`
- rubric or `.kiln/` missing: `| Structural hygiene drift | N/A   | rubric or .kiln/ not found — skipped |`

Doctor does NOT render the full hygiene preview. That is exclusively the `/kiln:kiln-hygiene` skill's job; 3h is a tripwire pointing at it. Performance contract: the 3h block alone MUST run <2 s on a real-repo fixture (SC-004 of `specs/kiln-structural-hygiene/`). Enforced by: no `gh` call here, grep surface capped at `plugin-*/` + `templates/` + `.kiln/` artifact dirs, no recursion into `node_modules/` or `.git/`.

### 4: Escalation-frequency tripwire (FR-016)

Cheap signal: when `.wheel/history/` accumulates more than 20 `awaiting_user_input == true` events in the last 7 days, suggest the maintainer run `/kiln:kiln-escalation-audit` for a full inventory. Tripwire only — this subcheck MUST NOT auto-invoke the escalation-audit skill (parity with 3g/3h's "tripwire pointing at the dedicated skill" pattern).

Threshold: `> 20` events in a rolling 7-day window. Source: `.wheel/history/*.json` files modified within the last 7 days where the JSON's `awaiting_user_input` field is `true`. Window-start floor uses `started_at` if present (preferred); file mtime is the implicit `find -mtime -7` filter.

```bash
# FR-016 — escalation-frequency tripwire (suggest /kiln:kiln-escalation-audit when pauses spike)
WINDOW_START="$(date -u -v-7d +%FT%TZ 2>/dev/null || date -u -d '7 days ago' +%FT%TZ)"
COUNT=0
if [ -d ".wheel/history" ]; then
  COUNT="$(find .wheel/history -name '*.json' -mtime -7 -print0 \
    | xargs -0 -r jq -r 'select(.awaiting_user_input == true) | .started_at' 2>/dev/null \
    | awk -v w="$WINDOW_START" '$0 >= w' | wc -l | tr -d ' ')"
fi

if [ "$COUNT" -gt 20 ]; then
  echo "4-escalation-frequency: WARN — ${COUNT} awaiting_user_input events in last 7 days"
  echo "  consider running /kiln:kiln-escalation-audit"
else
  echo "4-escalation-frequency: OK — ${COUNT} awaiting_user_input events in last 7 days"
fi
```

Append ONE row to the diagnosis table (Step 3e):

- `COUNT > 20`: `| 4-escalation-frequency | WARN | <N> awaiting_user_input events in last 7 days; consider running /kiln:kiln-escalation-audit |`
- `COUNT <= 20`: `| 4-escalation-frequency | OK   | <N> awaiting_user_input events in last 7 days |`
- `.wheel/history/` missing: `| 4-escalation-frequency | OK   | 0 awaiting_user_input events in last 7 days |` (treat absent dir as zero events; consistent with the escalation-audit skill's empty-corpus path)

**Constraints (FR-016)**:
- MUST NOT auto-invoke `/kiln:kiln-escalation-audit` — suggestion text only.
- MUST NOT mutate `.wheel/history/` or any other source.
- Performance budget: cheap (`find -mtime -7` + `jq` on at most 7 days of history files; well under 2 s on any realistic corpus). No `gh` calls; no LLM.

### 3f: Stale prd-created Issue Detection — FR-010

Scan `.kiln/issues/` for issues that were bundled into a PRD but never built:

```bash
echo "=== STALE PRD-CREATED ISSUES ==="
STALE_COUNT=0
if [ -d ".kiln/issues" ]; then
  for file in .kiln/issues/*.md; do
    [ -f "$file" ] || continue
    STATUS=$(grep -m1 '^status:' "$file" 2>/dev/null | sed 's/status:\s*//' | tr -d ' ')
    if [ "$STATUS" = "prd-created" ]; then
      STALE_COUNT=$((STALE_COUNT + 1))
      echo "STALE: $(basename "$file") — status is prd-created (bundled into PRD but never built)"
    fi
  done
fi
echo "Total stale issues: $STALE_COUNT"
```

Include each stale issue as a row in the diagnosis table (Step 3e) with status `STALE` and details showing the filename and explanation.

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
| .kiln/issues/ stale prd-created | STALE | 2 issues bundled into PRD but never built |
| CLAUDE.md drift | DRIFT | 3 cheap signals; run /kiln:kiln-claude-audit |
| Structural hygiene drift | OK    | No cheap signals triggered |
| Structural hygiene drift | DRIFT | 2 cheap signals; run /kiln:kiln-hygiene |
| Structural hygiene drift | N/A   | rubric or .kiln/ not found — skipped |
| 4-escalation-frequency | OK   | 7 awaiting_user_input events in last 7 days |
| 4-escalation-frequency | WARN | 25 awaiting_user_input events in last 7 days; consider running /kiln:kiln-escalation-audit |

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
sed -i '' "s/^version = .*/kiln:kiln-version = \"$canonical_version\"/" "$file"

# For YAML files — use sed to replace version line
sed -i '' "s/^version:.*/kiln:kiln-version: \"$canonical_version\"/" "$file"

# For .cfg files — use sed to replace version line
sed -i '' "s/^version = .*/kiln:kiln-version = $canonical_version/" "$file"
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
