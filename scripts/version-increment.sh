#!/bin/bash
# Auto-increment the 4th version segment (edit counter) on every Edit/Write
# to a code file. Always exits 0 — never blocks edits.
#
# Version format: 000.000.000.000 (release.feature.pr.edit)
# Syncs VERSION file to plugin/package.json

set -uo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only act on Edit and Write
if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

# If no file path, skip
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Skip non-code files (mirrors require-spec.sh exclusion list)
case "$FILE_PATH" in
  */docs/*|*/specs/*|*/scripts/*|*/.claude/*|*/.specify/*|\
  *CLAUDE.md|*README.md|*.yml|*.yaml|*.toml|*.gitignore|\
  */.env*|*/node_modules/*|*.json|\
  *VERSION|*version-increment.sh|*version-bump.sh|\
  *debug-log.md|*checkpoints.md|*QA-REPORT.md|\
  */.kiln/qa/*)
    exit 0
    ;;
esac

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
VERSION_FILE="$PROJECT_DIR/VERSION"
LOCK_DIR="$PROJECT_DIR/.version.lock"

# Stale lock cleanup (older than 5 seconds)
if [[ -d "$LOCK_DIR" ]]; then
  if [[ "$(uname)" == "Darwin" ]]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo "0") ))
  else
    LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_DIR" 2>/dev/null || echo "0") ))
  fi
  if [[ "$LOCK_AGE" -gt 5 ]]; then
    rmdir "$LOCK_DIR" 2>/dev/null
  fi
fi

# Acquire lock (atomic via mkdir)
LOCK_ATTEMPTS=0
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
  sleep 0.01
  LOCK_ATTEMPTS=$((LOCK_ATTEMPTS + 1))
  if [[ "$LOCK_ATTEMPTS" -gt 100 ]]; then
    # Give up after ~1 second, don't block the edit
    exit 0
  fi
done
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

# Read current version (or initialize)
if [[ -f "$VERSION_FILE" ]]; then
  CURRENT=$(head -1 "$VERSION_FILE" | tr -d '[:space:]')
else
  CURRENT="000.000.000.000"
fi

# Parse segments
IFS='.' read -r SEG1 SEG2 SEG3 SEG4 <<< "$CURRENT"

# Remove leading zeros for arithmetic, default to 0
SEG1=$((10#${SEG1:-0}))
SEG2=$((10#${SEG2:-0}))
SEG3=$((10#${SEG3:-0}))
SEG4=$((10#${SEG4:-0}))

# Increment 4th segment
SEG4=$((SEG4 + 1))

# Format with zero-padding
NEW_VERSION=$(printf "%03d.%03d.%03d.%03d" "$SEG1" "$SEG2" "$SEG3" "$SEG4")

# Write VERSION file
echo "$NEW_VERSION" > "$VERSION_FILE"

# Sync to all plugin-*/package.json and plugin-*/.claude-plugin/plugin.json
if command -v jq &>/dev/null; then
  for PKG_FILE in "$PROJECT_DIR"/plugin-*/package.json; do
    [[ -f "$PKG_FILE" ]] || continue
    TMP_PKG=$(mktemp)
    if jq --arg v "$NEW_VERSION" '.version = $v' "$PKG_FILE" > "$TMP_PKG" 2>/dev/null; then
      mv "$TMP_PKG" "$PKG_FILE"
    else
      rm -f "$TMP_PKG"
    fi
  done

  for PLUGIN_JSON in "$PROJECT_DIR"/plugin-*/.claude-plugin/plugin.json; do
    [[ -f "$PLUGIN_JSON" ]] || continue
    TMP_PLUGIN=$(mktemp)
    if jq --arg v "$NEW_VERSION" '.version = $v' "$PLUGIN_JSON" > "$TMP_PLUGIN" 2>/dev/null; then
      mv "$TMP_PLUGIN" "$PLUGIN_JSON"
    else
      rm -f "$TMP_PLUGIN"
    fi
  done
fi

# Stage version changes for inclusion in the next commit (FR-011)
git add "$VERSION_FILE" 2>/dev/null || true
git add "$PROJECT_DIR"/plugin-*/package.json 2>/dev/null || true
git add "$PROJECT_DIR"/plugin-*/.claude-plugin/plugin.json 2>/dev/null || true

# Always allow the edit
exit 0
