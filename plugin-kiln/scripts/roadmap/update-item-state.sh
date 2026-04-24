#!/usr/bin/env bash
# update-item-state.sh — atomic item frontmatter state transition
#
# FR-021 / PRD FR-021: state transitions planned → in-phase → distilled → specced → shipped
# Contract: specs/structured-roadmap/contracts/interfaces.md §2.5
#
# Usage:   update-item-state.sh <path-to-item.md> <new-state>
# Output:  stdout = JSON {"ok": true|false, "old_state": <string>, "new_state": <string>}
# Exit:    0 on success; 2 if file missing; 4 if invalid state

set -u

PATH_ARG="${1:-}"
NEW_STATE="${2:-}"

emit() {
  local ok="$1" old="$2" new="$3"
  local o="${old//\"/\\\"}"; local n="${new//\"/\\\"}"
  printf '{"ok":%s,"old_state":"%s","new_state":"%s"}\n' "$ok" "$o" "$n"
}

case "$NEW_STATE" in
  planned|in-phase|distilled|specced|shipped) : ;;
  *) emit false "" "$NEW_STATE"; exit 4 ;;
esac

if [ ! -f "$PATH_ARG" ]; then
  emit false "" "$NEW_STATE"; exit 2
fi

# Extract current state line within frontmatter
OLD_STATE="$(awk '
  /^---[[:space:]]*$/ { fm++; next }
  fm == 1 && /^state:[[:space:]]*/ {
    s = $0
    sub(/^state:[[:space:]]*/, "", s)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
    gsub(/^"|"$/, "", s)
    print s
    exit
  }
' "$PATH_ARG")"

# Atomic rewrite: write to temp, mv into place. Touch ONLY the state: line.
TMP="$(mktemp "${PATH_ARG}.XXXXXX.tmp")"
trap 'rm -f "$TMP"' EXIT

awk -v new="$NEW_STATE" '
  BEGIN { fm = 0; touched = 0 }
  /^---[[:space:]]*$/ { fm++; print; next }
  fm == 1 && /^state:[[:space:]]*/ && touched == 0 {
    print "state: " new
    touched = 1
    next
  }
  { print }
' "$PATH_ARG" > "$TMP"

if [ ! -s "$TMP" ]; then
  emit false "$OLD_STATE" "$NEW_STATE"; exit 3
fi

mv "$TMP" "$PATH_ARG"
trap - EXIT

emit true "$OLD_STATE" "$NEW_STATE"
