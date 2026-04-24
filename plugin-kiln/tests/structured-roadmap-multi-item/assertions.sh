#!/usr/bin/env bash
# US9 — multi-item detection: two items from one "and also" input.
# FR-018a / PRD FR-018a.
set -euo pipefail

ITEMS_DIR=".kiln/roadmap/items"
shopt -s nullglob
user_items=()
for f in "$ITEMS_DIR"/*.md; do
  b=$(basename "$f" .md)
  case "$b" in
    *-too-many-tokens|*-unauditable-buggy-code|*-too-much-setup) continue ;;
    *) user_items+=("$f") ;;
  esac
done

if [ "${#user_items[@]}" -lt 2 ]; then
  echo "FAIL: expected ≥2 items from 'and also' input, got ${#user_items[@]}" >&2
  ls "$ITEMS_DIR" >&2
  exit 1
fi

# Both (first two) items should share phase:unsorted
for f in "${user_items[@]:0:2}"; do
  grep -qE '^phase:[[:space:]]*unsorted$' "$f" || {
    echo "FAIL: item $f not at phase:unsorted (FR-018 --quick default)" >&2
    exit 1
  }
  grep -qE '^kind:[[:space:]]*feature$' "$f" || {
    echo "FAIL: item $f not kind:feature" >&2
    exit 1
  }
done

echo "PASS: 2 items split from 'and also' input" >&2
exit 0
