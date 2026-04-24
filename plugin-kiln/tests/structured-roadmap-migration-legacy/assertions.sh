#!/usr/bin/env bash
# US8 — legacy migration idempotency.
# FR-028 / PRD FR-028: parse bullets → items with kind:feature, phase:unsorted; archive legacy.
set -euo pipefail

ITEMS_DIR=".kiln/roadmap/items"

# Legacy archived
if [ ! -f ".kiln/roadmap.legacy.md" ]; then
  echo "FAIL: .kiln/roadmap.legacy.md not created (legacy should be renamed, not deleted)" >&2
  ls .kiln >&2 || true
  exit 1
fi

if [ -f ".kiln/roadmap.md" ]; then
  echo "FAIL: .kiln/roadmap.md still exists (should have been renamed to .legacy)" >&2
  exit 1
fi

# Count migrated items — exclude seed critiques
shopt -s nullglob
migrated_count=0
for f in "$ITEMS_DIR"/*.md; do
  b=$(basename "$f" .md)
  case "$b" in
    *-too-many-tokens|*-unauditable-buggy-code|*-too-much-setup) continue ;;
  esac
  if grep -qE '^phase:[[:space:]]*unsorted$' "$f"; then
    migrated_count=$((migrated_count + 1))
  fi
done

if [ "$migrated_count" -ne 3 ]; then
  echo "FAIL: expected 3 migrated items, got $migrated_count" >&2
  ls "$ITEMS_DIR" >&2 || true
  exit 1
fi

# Every migrated item must have kind:feature per FR-028
for f in "$ITEMS_DIR"/*.md; do
  b=$(basename "$f" .md)
  case "$b" in
    *-too-many-tokens|*-unauditable-buggy-code|*-too-much-setup) continue ;;
  esac
  if grep -qE '^phase:[[:space:]]*unsorted$' "$f"; then
    grep -qE '^kind:[[:space:]]*feature$' "$f" || { echo "FAIL: migrated item not kind:feature: $f" >&2; exit 1; }
  fi
done

echo "PASS: migration yielded 3 items at phase:unsorted; legacy archived" >&2
exit 0
