#!/usr/bin/env bash
# list-items.sh — list .kiln/roadmap/items/*.md paths, optionally filtered
#
# FR-009 / PRD FR-009: optional item frontmatter — addresses, depends_on
# FR-023 / PRD FR-023: distill ingests items filtered by phase/addresses/kind
# FR-033 / spec FR-033: kiln-next surfaces state:in-phase items
# Contract: specs/structured-roadmap/contracts/interfaces.md §2.4
#
# Usage:   list-items.sh [--phase <name>] [--kind <kind>] [--addresses <id>] [--state <state>]
# Output:  stdout = newline-separated repo-relative paths, ASCII sorted
# Exit:    0 on success (empty result → exit 0 with empty stdout)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITEMS_DIR="${ITEMS_DIR:-.kiln/roadmap/items}"

FILTER_PHASE=""
FILTER_KIND=""
FILTER_ADDRESSES=""
FILTER_STATE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --phase)     FILTER_PHASE="$2";      shift 2 ;;
    --kind)      FILTER_KIND="$2";       shift 2 ;;
    --addresses) FILTER_ADDRESSES="$2";  shift 2 ;;
    --state)     FILTER_STATE="$2";      shift 2 ;;
    *) echo "list-items: unknown arg: $1" >&2; exit 64 ;;
  esac
done

[ -d "$ITEMS_DIR" ] || exit 0

if ! command -v jq >/dev/null 2>&1; then
  echo "list-items: jq not available" >&2
  exit 69
fi

# Collect candidate paths sorted ASC, then filter each by parsing its frontmatter.
# Performance: O(N) frontmatter parses per call — fine for low-hundreds scale.
CANDIDATES="$(find "$ITEMS_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)"
[ -z "$CANDIDATES" ] && exit 0

while IFS= read -r p; do
  [ -z "$p" ] && continue
  FM="$(bash "$SCRIPT_DIR/parse-item-frontmatter.sh" "$p" 2>/dev/null)"
  [ -z "$FM" ] && continue
  KEEP="$(jq -r --arg phase "$FILTER_PHASE" \
                --arg kind  "$FILTER_KIND" \
                --arg addr  "$FILTER_ADDRESSES" \
                --arg state "$FILTER_STATE" '
    . as $fm
    | (if $phase != "" and ($fm["phase"] // "") != $phase then false
       else true end) as $m1
    | (if $kind != ""  and ($fm["kind"]  // "") != $kind then false
       else true end) as $m2
    | (if $state != "" and ($fm["state"] // "") != $state then false
       else true end) as $m3
    | (if $addr != ""
       then ((($fm["addresses"] // []) | index($addr)) != null)
       else true end) as $m4
    | ($m1 and $m2 and $m3 and $m4)
  ' <<<"$FM" 2>/dev/null)"
  if [ "$KEEP" = "true" ]; then
    printf '%s\n' "$p"
  fi
done <<<"$CANDIDATES"
