#!/usr/bin/env bash
# migrate-legacy-roadmap.sh — one-shot migration of .kiln/roadmap.md → items
#
# FR-028 / PRD FR-028: parse bullets under `## ` theme groups into kind:feature items
# Contract: specs/structured-roadmap/contracts/interfaces.md §2.7
#
# Usage:   migrate-legacy-roadmap.sh
# Output:  stdout = JSON {"migrated": <int>, "skipped": <bool>, "reason": <string>}
# Exit:    0 always (idempotent — skipped=true on no-op)

set -u

ROOT="${ROOT:-.}"
LEGACY="$ROOT/.kiln/roadmap.md"
ARCHIVE="$ROOT/.kiln/roadmap.legacy.md"
ITEMS_DIR="$ROOT/.kiln/roadmap/items"

emit() {
  # $1=migrated  $2=skipped  $3=reason
  local r="${3//\"/\\\"}"
  printf '{"migrated":%d,"skipped":%s,"reason":"%s"}\n' "$1" "$2" "$r"
}

if [ -f "$ARCHIVE" ]; then
  emit 0 true "already migrated (.kiln/roadmap.legacy.md exists)"
  exit 0
fi

if [ ! -f "$LEGACY" ]; then
  emit 0 true "no legacy .kiln/roadmap.md to migrate"
  exit 0
fi

mkdir -p "$ITEMS_DIR"

TODAY="$(date -u +%Y-%m-%d)"
MIGRATED=0

# Walk the legacy file: track current `## ` theme heading, emit one item per `- ` bullet.
CURRENT_THEME=""
while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ ^##[[:space:]]+(.+)$ ]]; then
    CURRENT_THEME="${BASH_REMATCH[1]}"
    continue
  fi
  if [[ "$line" =~ ^-[[:space:]]+(.+)$ ]]; then
    BULLET="${BASH_REMATCH[1]}"
    # Slugify: lowercase, alnum+dash, max 40 chars
    slug="$(printf '%s' "$BULLET" \
      | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' \
      | cut -c1-40 \
      | sed -E 's/-+$//')"
    [ -z "$slug" ] && slug="unsorted-item"
    ID="${TODAY}-${slug}"
    TARGET="$ITEMS_DIR/${ID}.md"
    # If duplicate, append counter
    i=2
    while [ -f "$TARGET" ]; do
      ID="${TODAY}-${slug}-${i}"
      TARGET="$ITEMS_DIR/${ID}.md"
      i=$((i + 1))
    done
    # Title: first 80 chars of bullet (escape `"` for YAML)
    title="${BULLET//\"/\\\"}"
    cat > "$TARGET" <<EOF
---
id: ${ID}
title: "${title}"
kind: feature
date: ${TODAY}
status: open
phase: unsorted
state: planned
blast_radius: feature
review_cost: moderate
context_cost: unknown (migrated from legacy roadmap)
---

# ${BULLET}

_Migrated from \`.kiln/roadmap.md\` theme: **${CURRENT_THEME:-General}**. Run \`/kiln:kiln-roadmap --reclassify\` to promote._
EOF
    MIGRATED=$((MIGRATED + 1))
  fi
done < "$LEGACY"

# Rename legacy file (preserves byte-identical content)
mv "$LEGACY" "$ARCHIVE"

emit "$MIGRATED" false "migrated $MIGRATED bullets; legacy archived at .kiln/roadmap.legacy.md"
