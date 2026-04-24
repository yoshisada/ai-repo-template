#!/usr/bin/env bash
# update-phase-status.sh — atomic phase status + item registration + state cascade
#
# FR-020 / PRD FR-020: only one phase may be in-progress at a time
# FR-021 / PRD FR-021: --cascade-items flips planned → in-phase on phase activation
# FR-006 / PRD FR-006: phase body carries auto-maintained `## Items` list
# Contract: specs/structured-roadmap/contracts/interfaces.md §2.6
#
# Usage:   update-phase-status.sh <phase-name> <new-status> [--cascade-items]
#          update-phase-status.sh <phase-name> register <item-id>
# Output:  stdout = JSON {"ok":..., "old_status":..., "new_status":..., "items_transitioned":N}
# Exit:    0 on success; 2 if phase missing;
#          5 if attempting to start while another is in-progress (FR-020)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASES_DIR="${PHASES_DIR:-.kiln/roadmap/phases}"
ITEMS_DIR="${ITEMS_DIR:-.kiln/roadmap/items}"

PHASE_NAME="${1:-}"
ACTION="${2:-}"
MAYBE="${3:-}"

emit() {
  # $1 ok  $2 old_status  $3 new_status  $4 items_transitioned
  printf '{"ok":%s,"old_status":"%s","new_status":"%s","items_transitioned":%s}\n' \
    "$1" "$2" "$3" "$4"
}

if [ -z "$PHASE_NAME" ] || [ -z "$ACTION" ]; then
  echo "usage: update-phase-status.sh <phase> <planned|in-progress|complete|register> [..]" >&2
  exit 64
fi

PHASE_FILE="$PHASES_DIR/$PHASE_NAME.md"
if [ ! -f "$PHASE_FILE" ]; then
  emit false "" "$ACTION" 0; exit 2
fi

# ---------- branch: register <item-id> ----------
if [ "$ACTION" = "register" ]; then
  ITEM_ID="$MAYBE"
  if [ -z "$ITEM_ID" ]; then
    emit false "" "register" 0; exit 64
  fi
  # Rewrite the `## Items` section from list-items.sh --phase <name>, preserving
  # the preamble above it. If no `## Items` heading exists, append one.
  TMP="$(mktemp "${PHASE_FILE}.XXXXXX.tmp")"
  trap 'rm -f "$TMP"' EXIT
  awk -v phase="$PHASE_NAME" '
    BEGIN { in_items = 0; done = 0 }
    /^## Items[[:space:]]*$/ {
      print
      in_items = 1
      done = 1
      next
    }
    in_items == 1 && /^## / && !/^## Items/ {
      # section after Items — stop consuming list
      in_items = 0
      print
      next
    }
    in_items == 1 { next }
    { print }
    END {
      if (done == 0) {
        print ""
        print "## Items"
      }
    }
  ' "$PHASE_FILE" > "$TMP"

  # Re-emit item list from list-items.sh --phase <name>
  ITEM_PATHS="$(bash "$SCRIPT_DIR/list-items.sh" --phase "$PHASE_NAME" 2>/dev/null || true)"
  {
    cat "$TMP"
    if [ -n "$ITEM_PATHS" ]; then
      echo ""
      while IFS= read -r p; do
        [ -z "$p" ] && continue
        id="$(basename "$p" .md)"
        echo "- $id"
      done <<<"$ITEM_PATHS"
    fi
  } > "${TMP}.2"

  mv "${TMP}.2" "$PHASE_FILE"
  rm -f "$TMP"
  trap - EXIT

  OLD_STATUS="$(awk '/^status:[[:space:]]*/ { s=$0; sub(/^status:[[:space:]]*/,"",s); gsub(/[[:space:]]+$/,"",s); print s; exit }' "$PHASE_FILE")"
  emit true "$OLD_STATUS" "$OLD_STATUS" 0
  exit 0
fi

# ---------- branch: status transition ----------
NEW_STATUS="$ACTION"
CASCADE=0
if [ "$MAYBE" = "--cascade-items" ]; then
  CASCADE=1
fi

case "$NEW_STATUS" in
  planned|in-progress|complete) : ;;
  *) emit false "" "$NEW_STATUS" 0; exit 64 ;;
esac

OLD_STATUS="$(awk '
  /^---[[:space:]]*$/ { fm++; next }
  fm == 1 && /^status:[[:space:]]*/ {
    s = $0; sub(/^status:[[:space:]]*/, "", s); gsub(/[[:space:]]+$/, "", s); gsub(/^"|"$/, "", s);
    print s; exit
  }
' "$PHASE_FILE")"

# FR-020 single-in-progress guard
if [ "$NEW_STATUS" = "in-progress" ]; then
  OTHER_IN_PROGRESS=""
  for f in "$PHASES_DIR"/*.md; do
    [ -f "$f" ] || continue
    [ "$(basename "$f" .md)" = "$PHASE_NAME" ] && continue
    s="$(awk '
      /^---[[:space:]]*$/ { fm++; next }
      fm == 1 && /^status:[[:space:]]*/ { v=$0; sub(/^status:[[:space:]]*/,"",v); gsub(/[[:space:]]+$/,"",v); print v; exit }
    ' "$f")"
    if [ "$s" = "in-progress" ]; then
      OTHER_IN_PROGRESS="$(basename "$f" .md)"; break
    fi
  done
  if [ -n "$OTHER_IN_PROGRESS" ]; then
    printf '{"ok":false,"old_status":"%s","new_status":"%s","items_transitioned":0,"error":"another phase in-progress: %s (FR-020 single-in-progress)"}\n' \
      "$OLD_STATUS" "$NEW_STATUS" "$OTHER_IN_PROGRESS"
    exit 5
  fi
fi

TODAY="$(date -u +%Y-%m-%d)"
TMP="$(mktemp "${PHASE_FILE}.XXXXXX.tmp")"
trap 'rm -f "$TMP"' EXIT

awk -v new="$NEW_STATUS" -v today="$TODAY" '
  BEGIN { fm = 0; saw_status=0; saw_started=0; saw_completed=0 }
  /^---[[:space:]]*$/ {
    fm++
    if (fm == 2) {
      # close of frontmatter — if new is in-progress and no started, add it
      if (new == "in-progress" && saw_started == 0) print "started: " today
      if (new == "complete"    && saw_completed == 0) print "completed: " today
    }
    print; next
  }
  fm == 1 && /^status:[[:space:]]*/ {
    print "status: " new
    saw_status = 1
    next
  }
  fm == 1 && /^started:[[:space:]]*/ {
    saw_started = 1
    if (new == "in-progress") { print "started: " today; next }
    print; next
  }
  fm == 1 && /^completed:[[:space:]]*/ {
    saw_completed = 1
    if (new == "complete") { print "completed: " today; next }
    print; next
  }
  { print }
' "$PHASE_FILE" > "$TMP"

mv "$TMP" "$PHASE_FILE"
trap - EXIT

# Cascade items if requested
ITEMS_TRANSITIONED=0
if [ "$CASCADE" -eq 1 ] && [ "$NEW_STATUS" = "in-progress" ] && [ -d "$ITEMS_DIR" ]; then
  PLANNED="$(bash "$SCRIPT_DIR/list-items.sh" --phase "$PHASE_NAME" --state planned 2>/dev/null || true)"
  if [ -n "$PLANNED" ]; then
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      bash "$SCRIPT_DIR/update-item-state.sh" "$p" "in-phase" >/dev/null 2>&1 && \
        ITEMS_TRANSITIONED=$((ITEMS_TRANSITIONED + 1))
    done <<<"$PLANNED"
  fi
fi

emit true "$OLD_STATUS" "$NEW_STATUS" "$ITEMS_TRANSITIONED"
