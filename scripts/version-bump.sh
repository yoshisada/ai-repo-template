#!/bin/bash
# Manually bump a version segment: release, feature, or pr.
# Resets all lower segments to 0.
#
# Usage: version-bump.sh <release|feature|pr>
#
# Examples:
#   ./scripts/version-bump.sh release   # 001.003.002.017 → 002.000.000.000
#   ./scripts/version-bump.sh feature   # 001.003.002.017 → 001.004.000.000
#   ./scripts/version-bump.sh pr        # 001.003.002.017 → 001.003.003.000

set -euo pipefail

SEGMENT="${1:-}"

if [[ -z "$SEGMENT" ]] || [[ "$SEGMENT" != "release" && "$SEGMENT" != "feature" && "$SEGMENT" != "pr" ]]; then
  echo "Usage: version-bump.sh <release|feature|pr>"
  echo ""
  echo "  release  — increment 1st segment, reset all others"
  echo "  feature  — increment 2nd segment, reset 3rd and 4th"
  echo "  pr       — increment 3rd segment, reset 4th"
  exit 1
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
VERSION_FILE="$PROJECT_DIR/VERSION"
PKG_FILE="$PROJECT_DIR/plugin-kiln/package.json"
LOCK_DIR="$PROJECT_DIR/.version.lock"

# Stale lock cleanup
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

# Acquire lock
LOCK_ATTEMPTS=0
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
  sleep 0.01
  LOCK_ATTEMPTS=$((LOCK_ATTEMPTS + 1))
  if [[ "$LOCK_ATTEMPTS" -gt 100 ]]; then
    echo "Error: Could not acquire version lock" >&2
    exit 1
  fi
done
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

# Read current version
if [[ -f "$VERSION_FILE" ]]; then
  CURRENT=$(head -1 "$VERSION_FILE" | tr -d '[:space:]')
else
  CURRENT="000.000.000.000"
fi

# Parse segments
IFS='.' read -r SEG1 SEG2 SEG3 SEG4 <<< "$CURRENT"
SEG1=$((10#${SEG1:-0}))
SEG2=$((10#${SEG2:-0}))
SEG3=$((10#${SEG3:-0}))
SEG4=$((10#${SEG4:-0}))

# Bump the target segment, reset lower segments
case "$SEGMENT" in
  release)
    SEG1=$((SEG1 + 1))
    SEG2=0
    SEG3=0
    SEG4=0
    ;;
  feature)
    SEG2=$((SEG2 + 1))
    SEG3=0
    SEG4=0
    ;;
  pr)
    SEG3=$((SEG3 + 1))
    SEG4=0
    ;;
esac

# Format with zero-padding
NEW_VERSION=$(printf "%03d.%03d.%03d.%03d" "$SEG1" "$SEG2" "$SEG3" "$SEG4")

echo "$CURRENT → $NEW_VERSION ($SEGMENT bump)"

# Write VERSION file
echo "$NEW_VERSION" > "$VERSION_FILE"

# Sync to plugin-kiln/package.json
if [[ -f "$PKG_FILE" ]] && command -v jq &>/dev/null; then
  TMP_PKG=$(mktemp)
  if jq --arg v "$NEW_VERSION" '.version = $v' "$PKG_FILE" > "$TMP_PKG" 2>/dev/null; then
    mv "$TMP_PKG" "$PKG_FILE"
  else
    rm -f "$TMP_PKG"
  fi
fi

# Sync to plugin-kiln/.claude-plugin/plugin.json
PLUGIN_JSON="$PROJECT_DIR/plugin-kiln/.claude-plugin/plugin.json"
if [[ -f "$PLUGIN_JSON" ]] && command -v jq &>/dev/null; then
  TMP_PLUGIN=$(mktemp)
  if jq --arg v "$NEW_VERSION" '.version = $v' "$PLUGIN_JSON" > "$TMP_PLUGIN" 2>/dev/null; then
    mv "$TMP_PLUGIN" "$PLUGIN_JSON"
  else
    rm -f "$TMP_PLUGIN"
  fi
fi

echo "VERSION: $NEW_VERSION"
echo "Synced to: plugin-kiln/package.json, plugin-kiln/.claude-plugin/plugin.json"
