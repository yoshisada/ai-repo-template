#!/usr/bin/env bash
# US1 acceptance — structured-roadmap capture feature (--quick path)
#
# FR-007 / PRD FR-007: item frontmatter required keys present.
# FR-008 / PRD FR-008: AI-native sizing fields present; NO human_time / t_shirt_size / effort_days.
# FR-002 / PRD FR-002: .kiln/roadmap/{phases,items}/ created on first run.
# FR-018 / PRD FR-018: --quick lands in phase:unsorted with state:planned.
#
# spec.md US1 acceptance scenarios 1–3.
set -euo pipefail

ITEMS_DIR=".kiln/roadmap/items"

if [ ! -d "$ITEMS_DIR" ]; then
  echo "FAIL: $ITEMS_DIR not created (FR-002)" >&2
  exit 1
fi

shopt -s nullglob
items=( "$ITEMS_DIR"/*.md )
if [ "${#items[@]}" -eq 0 ]; then
  echo "FAIL: no item files created under $ITEMS_DIR" >&2
  find .kiln -type f 2>/dev/null >&2 || true
  exit 1
fi

# Find the non-seed item (seed critiques ship with the bootstrap; the test
# item is the one with kind:feature). Match on basename prefix.
item=""
for f in "${items[@]}"; do
  b=$(basename "$f" .md)
  case "$b" in
    *-too-many-tokens|*-unauditable-buggy-code|*-too-much-setup) continue ;;
    *) item="$f"; break ;;
  esac
done

if [ -z "$item" ]; then
  echo "FAIL: no non-seed item file found (US1)" >&2
  ls "$ITEMS_DIR" >&2
  exit 1
fi

# FR-007: required keys present
for key in id title kind date status phase state blast_radius review_cost context_cost; do
  if ! grep -qE "^${key}:[[:space:]]*" "$item"; then
    echo "FAIL: missing required frontmatter key: $key (FR-007)" >&2
    head -30 "$item" >&2
    exit 1
  fi
done

# FR-008: NO forbidden sizing fields
for forbidden in human_time human_days effort_days effort_hours t_shirt_size tshirt estimate_days estimate_hours pomodoros; do
  if grep -qE "^${forbidden}:" "$item"; then
    echo "FAIL: forbidden sizing key present: $forbidden (FR-008)" >&2
    exit 1
  fi
done

# FR-018 quick path: phase=unsorted
if ! grep -qE '^phase:[[:space:]]*unsorted$' "$item"; then
  echo "FAIL: --quick item should land in phase: unsorted (FR-018)" >&2
  grep -E '^phase:' "$item" >&2 || true
  exit 1
fi

if ! grep -qE '^state:[[:space:]]*planned$' "$item"; then
  echo "FAIL: --quick item should have state: planned (FR-018)" >&2
  exit 1
fi

# kind is feature by default
if ! grep -qE '^kind:[[:space:]]*feature$' "$item"; then
  echo "FAIL: --quick item default kind should be feature (FR-014a default)" >&2
  exit 1
fi

echo "PASS: US1 capture via --quick → $item" >&2
exit 0
