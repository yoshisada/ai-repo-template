#!/usr/bin/env bash
# vision-forward-dedup-load.sh — load the declined-set as <title>\t<tag> lines.
#
# FR-013 / vision-tooling FR-013: declined suggestions persist on disk so the
# next forward pass deduplicates against them. Dedup key MUST be
# `suggestion title + tag`. Persistence file = .kiln/roadmap/items/declined/*.md
# per declined entry (FR-022).
#
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme C —
#           vision-forward-dedup-load.sh"
#
# Usage:   vision-forward-dedup-load.sh
# Stdout:  zero or more lines `<title>\t<tag>`, sorted by title ASC. Empty
#          stdout when .kiln/roadmap/items/declined/ is missing or empty.
# Exit:    0 always.
# Side-effects: none.
set -u
LC_ALL=C
export LC_ALL

DECLINED_DIR="${DECLINED_DIR:-.kiln/roadmap/items/declined}"

[ -d "$DECLINED_DIR" ] || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_FM="$SCRIPT_DIR/parse-item-frontmatter.sh"

# Find each declined record's frontmatter; emit `<title>\t<tag>` per record.
# We accept either the canonical `tag:` field (forward-pass shape) or the
# `kind:` field (when only `kind: non-goal` was set). Title is always taken
# from `title:` if present, else derived from the filename slug.
TMP_OUT=$(mktemp); trap 'rm -f "$TMP_OUT"' EXIT

find "$DECLINED_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
  [ -z "$f" ] && continue
  if [ -f "$PARSE_FM" ]; then
    fm_json=$(bash "$PARSE_FM" "$f" 2>/dev/null) || fm_json=""
  else
    fm_json=""
  fi
  title=""
  tag=""
  if [ -n "$fm_json" ] && command -v jq >/dev/null 2>&1; then
    title=$(printf '%s' "$fm_json" | jq -r '.title // empty' 2>/dev/null)
    tag=$(printf '%s' "$fm_json" | jq -r '.tag // empty' 2>/dev/null)
    if [ -z "$tag" ]; then
      kind=$(printf '%s' "$fm_json" | jq -r '.kind // empty' 2>/dev/null)
      [ -n "$kind" ] && tag="$kind"
    fi
  fi
  if [ -z "$title" ]; then
    # Derive from filename: strip leading date + trailing -considered-and-declined.
    base=$(basename "$f" .md)
    title=$(printf '%s' "$base" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//; s/-considered-and-declined(-[0-9]+)?$//')
  fi
  [ -z "$tag" ] && tag="non-goal"
  printf '%s\t%s\n' "$title" "$tag" >> "$TMP_OUT"
done

[ -s "$TMP_OUT" ] || exit 0
LC_ALL=C sort "$TMP_OUT"
