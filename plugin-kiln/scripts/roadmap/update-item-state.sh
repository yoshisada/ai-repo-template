#!/usr/bin/env bash
# update-item-state.sh — atomic item frontmatter state transition (+ optional status)
#
# FR-021 / PRD FR-021: state transitions planned → in-phase → distilled → specced → shipped
# FR-002 (escalation-audit): optional --status <value> flag — atomically rewrites BOTH
#   `state:` and `status:` in ONE awk + tempfile + mv cycle.
# Contract: specs/structured-roadmap/contracts/interfaces.md §2.5
#           specs/escalation-audit/contracts/interfaces.md §A.1
#
# Usage (existing, preserved unchanged):
#   update-item-state.sh <path-to-item.md> <new-state>
#
# Usage (NEW — FR-002):
#   update-item-state.sh <path-to-item.md> <new-state> --status <new-status>
#
# Semantics:
#   - <new-state> MUST be one of: planned | in-phase | distilled | specced | shipped.
#   - --status <value>, when supplied, atomically rewrites BOTH `state:` and `status:` in
#     the SAME tempfile + mv cycle. <value> is propagated verbatim (no enum validation in v1
#     — the caller is the authority for status vocabulary).
#   - When --status is omitted, behavior is byte-identical to the pre-FR-002 script.
#
# Output: stdout = JSON
#   {"ok": true|false, "old_state": "<s>", "new_state": "<s>",
#    "old_status": "<s>|null", "new_status": "<s>|null"}
# Exit:    0 on success; 2 if file missing; 3 write failure; 4 invalid state.

set -u

PATH_ARG="${1:-}"
NEW_STATE="${2:-}"

# FR-002: parse optional --status <value> from remaining args without disturbing the
# existing positional contract. Unknown flags are tolerated (forward-compat).
NEW_STATUS=""
HAS_STATUS=0
if [ "$#" -ge 2 ]; then
  shift 2
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --status)
        # FR-002: --status flag captures the next arg as the new status value.
        shift
        NEW_STATUS="${1:-}"
        HAS_STATUS=1
        ;;
      *)
        : # ignore unknown args (forward-compat)
        ;;
    esac
    shift || true
  done
fi

emit() {
  # FR-002: extended JSON shape — old_status / new_status emitted as JSON null when --status absent.
  local ok="$1" old="$2" new="$3" old_status="$4" new_status="$5"
  local o n os ns
  o="${old//\"/\\\"}"
  n="${new//\"/\\\"}"
  if [ "$HAS_STATUS" = "1" ]; then
    os="\"${old_status//\"/\\\"}\""
    ns="\"${new_status//\"/\\\"}\""
  else
    os="null"
    ns="null"
  fi
  printf '{"ok":%s,"old_state":"%s","new_state":"%s","old_status":%s,"new_status":%s}\n' \
    "$ok" "$o" "$n" "$os" "$ns"
}

case "$NEW_STATE" in
  planned|in-phase|distilled|specced|shipped) : ;;
  *) emit false "" "$NEW_STATE" "" "$NEW_STATUS"; exit 4 ;;
esac

if [ ! -f "$PATH_ARG" ]; then
  emit false "" "$NEW_STATE" "" "$NEW_STATUS"; exit 2
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

# FR-002: extract current status line within frontmatter (only used when --status supplied,
# but we compute unconditionally for diagnostic clarity — costs one awk pass).
OLD_STATUS="$(awk '
  /^---[[:space:]]*$/ { fm++; next }
  fm == 1 && /^status:[[:space:]]*/ {
    s = $0
    sub(/^status:[[:space:]]*/, "", s)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
    gsub(/^"|"$/, "", s)
    print s
    exit
  }
' "$PATH_ARG")"

# Atomic rewrite: write to temp, mv into place.
# Pre-FR-002 behavior: touch ONLY the state: line.
# FR-002 behavior: ONE awk pass rewrites BOTH state: and status: lines into ONE tempfile.
TMP="$(mktemp "${PATH_ARG}.XXXXXX.tmp")"
trap 'rm -f "$TMP"' EXIT

awk -v new_state="$NEW_STATE" -v new_status="$NEW_STATUS" -v has_status="$HAS_STATUS" '
  BEGIN { fm = 0; touched_state = 0; touched_status = 0 }
  /^---[[:space:]]*$/ { fm++; print; next }
  fm == 1 && /^state:[[:space:]]*/ && touched_state == 0 {
    print "state: " new_state
    touched_state = 1
    next
  }
  # FR-002: rewrite the status: line in the SAME awk pass when --status supplied.
  fm == 1 && /^status:[[:space:]]*/ && touched_status == 0 && has_status == 1 {
    print "status: " new_status
    touched_status = 1
    next
  }
  { print }
' "$PATH_ARG" > "$TMP"

if [ ! -s "$TMP" ]; then
  emit false "$OLD_STATE" "$NEW_STATE" "$OLD_STATUS" "$NEW_STATUS"; exit 3
fi

mv "$TMP" "$PATH_ARG"
trap - EXIT

emit true "$OLD_STATE" "$NEW_STATE" "$OLD_STATUS" "$NEW_STATUS"
