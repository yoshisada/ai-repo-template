#!/usr/bin/env bash
# vision-alignment-walk.sh — emit open roadmap-item paths for alignment check.
#
# FR-006 / vision-tooling FR-006: walk every .kiln/roadmap/items/*.md whose
# `status != shipped` AND `state != shipped`. Items lacking either field are
# treated as open. Items under .kiln/roadmap/items/declined/ are NOT auto-
# excluded — caller decides — but in practice their `kind: non-goal` +
# `state: declined` frontmatter means callers usually skip them.
#
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme B —
#           vision-alignment-walk.sh"
#
# Usage:   vision-alignment-walk.sh
# Stdout:  one repo-relative path per line, sorted ASCII-ascending.
# Exit:    0 always (empty stdout = no open items).
# Side-effects: none.
set -u
LC_ALL=C
export LC_ALL

ITEMS_DIR="${ITEMS_DIR:-.kiln/roadmap/items}"

[ -d "$ITEMS_DIR" ] || exit 0

# Walk both the top-level items dir AND the declined/ subdir. We do NOT recurse
# arbitrarily — only one level of nesting is permitted by FR-022.
collect() {
  find "$1" -maxdepth 1 -type f -name '*.md' 2>/dev/null
}

ALL_PATHS=""
TOP="$(collect "$ITEMS_DIR")"
ALL_PATHS="${TOP}"
if [ -d "$ITEMS_DIR/declined" ]; then
  DECLINED_PATHS="$(collect "$ITEMS_DIR/declined")"
  if [ -n "$DECLINED_PATHS" ]; then
    if [ -n "$ALL_PATHS" ]; then
      ALL_PATHS="${ALL_PATHS}
${DECLINED_PATHS}"
    else
      ALL_PATHS="$DECLINED_PATHS"
    fi
  fi
fi

[ -z "$ALL_PATHS" ] && exit 0

# Sort ASC and filter.
echo "$ALL_PATHS" | LC_ALL=C sort | while IFS= read -r p; do
  [ -z "$p" ] && continue
  # Extract status: and state: from YAML frontmatter (between the first pair of `---`).
  fm=$(awk '
    BEGIN { in_fm = 0; saw = 0 }
    /^---[[:space:]]*$/ {
      if (saw == 0) { saw = 1; in_fm = 1; next }
      else if (in_fm == 1) { exit 0 }
    }
    in_fm == 1 { print }
  ' "$p" 2>/dev/null)

  status_val=$(printf '%s\n' "$fm" | awk -F: '
    /^status:[[:space:]]/ { sub(/^status:[[:space:]]*/, ""); gsub(/^"|"$/,""); print; exit }
  ')
  state_val=$(printf '%s\n' "$fm" | awk -F: '
    /^state:[[:space:]]/ { sub(/^state:[[:space:]]*/, ""); gsub(/^"|"$/,""); print; exit }
  ')

  # Trim whitespace.
  status_val=$(printf '%s' "$status_val" | sed 's/[[:space:]]*$//')
  state_val=$(printf '%s' "$state_val" | sed 's/[[:space:]]*$//')

  if [ "$status_val" = "shipped" ] || [ "$state_val" = "shipped" ]; then
    continue
  fi
  printf '%s\n' "$p"
done
