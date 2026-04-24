#!/usr/bin/env bash
# US3 — --quick bypasses interview + follow-up.
# FR-018 / PRD FR-018: phase:unsorted, state:planned, raw body.
# FR-018c / PRD FR-018c: no follow-up loop under --quick.
set -euo pipefail

ITEMS_DIR=".kiln/roadmap/items"
shopt -s nullglob
items=( "$ITEMS_DIR"/*.md )
test_items=()
for f in "${items[@]}"; do
  b=$(basename "$f" .md)
  case "$b" in
    *-too-many-tokens|*-unauditable-buggy-code|*-too-much-setup) continue ;;
    *) test_items+=("$f") ;;
  esac
done

if [ "${#test_items[@]}" -ne 1 ]; then
  echo "FAIL: expected exactly 1 captured item, got ${#test_items[@]}" >&2
  printf '  %s\n' "${test_items[@]}" >&2
  exit 1
fi

item="${test_items[0]}"

grep -qE '^phase:[[:space:]]*unsorted$' "$item" || { echo "FAIL: phase != unsorted" >&2; exit 1; }
grep -qE '^state:[[:space:]]*planned$' "$item"  || { echo "FAIL: state != planned" >&2; exit 1; }
grep -qE '^kind:[[:space:]]*feature$' "$item"   || { echo "FAIL: kind != feature (default)" >&2; exit 1; }

# no forbidden sizing
for forbidden in human_time human_days effort_days effort_hours t_shirt_size tshirt size; do
  if grep -qE "^${forbidden}:" "$item"; then
    case "$forbidden" in
      size)
        # `size: S/M/L/XL` is forbidden; `size: <free-text>` that doesn't
        # match is technically allowed — but we don't emit `size:` at all.
        if grep -qEi '^size:[[:space:]]*(xs|s|m|l|xl|xxl)$' "$item"; then
          echo "FAIL: forbidden T-shirt size detected" >&2; exit 1
        fi
        ;;
      *) echo "FAIL: forbidden sizing key: $forbidden" >&2; exit 1 ;;
    esac
  fi
done

echo "PASS: --quick captured one item at phase:unsorted" >&2
exit 0
