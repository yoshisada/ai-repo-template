#!/usr/bin/env bash
# read-plugins.sh — scan plugin-*/.claude-plugin/plugin.json and emit a JSON array.
#
# FR-001 (plugins[] field of ProjectContextSnapshot)
# FR-002 (missing-dir defensiveness — empty array, not crash)
#
# Contract: specs/coach-driven-capture-ergonomics/contracts/interfaces.md
#   → Module: plugin-kiln/scripts/context/ → read-plugins.sh
#
# Output shape per plugin:
#   { "path": "...", "name": "...", "version": "..." }
# Collection sorted ASC by name (NFR-002).
set -euo pipefail
export LC_ALL=C

REPO_ROOT="${1:-}"
if [[ -z "$REPO_ROOT" ]]; then
  echo "usage: read-plugins.sh <repo-root>" >&2
  exit 2
fi

# Look for plugin-*/.claude-plugin/plugin.json. Globbing, not find, keeps it fast.
shopt -s nullglob
MANIFESTS=( "$REPO_ROOT"/plugin-*/.claude-plugin/plugin.json )
shopt -u nullglob

if [[ "${#MANIFESTS[@]}" -eq 0 ]]; then
  echo "[]"
  exit 0
fi

declare -a JSON_ENTRIES=()

for abs in "${MANIFESTS[@]}"; do
  rel="${abs#$REPO_ROOT/}"
  # Defensive parse — malformed JSON should not abort the whole scan (FR-002).
  if ! name="$(jq -r '.name // empty' "$abs" 2>/dev/null)"; then
    echo "warn: skipping malformed plugin manifest $rel" >&2
    continue
  fi
  version="$(jq -r '.version // empty' "$abs" 2>/dev/null || echo "")"

  entry="$(jq -n \
    --arg path    "$rel" \
    --arg name    "$name" \
    --arg version "$version" \
    '{ path: $path, name: $name, version: $version }')"
  JSON_ENTRIES+=("$entry")
done

# Sort ASC by `.name` (NFR-002).
printf '%s\n' "${JSON_ENTRIES[@]}" | jq -s 'sort_by(.name)'
