#!/usr/bin/env bash
# generate-sync-summary.sh
# Contract: specs/shelf-sync-efficiency/contracts/interfaces.md §7
#
# Reads compute-work-list.json and obsidian-apply-results.json and emits
# the terminal summary markdown at .wheel/outputs/sync-summary.md
# with five sections in the required order: Issues, Docs, Tags, Progress,
# Errors. Shape MUST stay byte-compatible with v3 (FR-005/SC-006).

set -euo pipefail

OUT=".wheel/outputs/sync-summary.md"
WL=".wheel/outputs/compute-work-list.json"
AR=".wheel/outputs/obsidian-apply-results.json"

mkdir -p .wheel/outputs

if [ -f "$WL" ]; then
  slug=$(jq -r '.slug // "unknown"' "$WL")
  wl_issues=$(jq '.counts.issues' "$WL")
  wl_docs=$(jq '.counts.docs' "$WL")
else
  slug="unknown"
  wl_issues='{"create":0,"update":0,"close":0,"skip":0}'
  wl_docs='{"create":0,"update":0,"skip":0}'
fi

if [ -f "$AR" ]; then
  ar_issues=$(jq '.issues // {}' "$AR")
  ar_docs=$(jq '.docs // {}' "$AR")
  ar_dash=$(jq '.dashboard // {}' "$AR")
  ar_prog=$(jq '.progress // {}' "$AR")
  ar_errors=$(jq '.errors // []' "$AR")
else
  ar_issues='{}'
  ar_docs='{}'
  ar_dash='{}'
  ar_prog='{}'
  ar_errors='[]'
fi

i_created=$(echo "$ar_issues" | jq -r '.created // 0')
i_updated=$(echo "$ar_issues" | jq -r '.updated // 0')
i_closed=$(echo "$ar_issues" | jq -r '.closed // 0')
i_skipped=$(echo "$ar_issues" | jq -r '.skipped // 0')

# Fall back to work-list counts if apply results missing fields
if [ "$i_created$i_updated$i_closed$i_skipped" = "0000" ] && [ "$(echo "$wl_issues" | jq 'add')" != "0" ]; then
  i_created=$(echo "$wl_issues" | jq -r '.create')
  i_updated=$(echo "$wl_issues" | jq -r '.update')
  i_closed=$(echo "$wl_issues" | jq -r '.close')
  i_skipped=$(echo "$wl_issues" | jq -r '.skip')
fi

d_created=$(echo "$ar_docs" | jq -r '.created // 0')
d_updated=$(echo "$ar_docs" | jq -r '.updated // 0')
d_skipped=$(echo "$ar_docs" | jq -r '.skipped // 0')
if [ "$d_created$d_updated$d_skipped" = "000" ] && [ "$(echo "$wl_docs" | jq 'add')" != "0" ]; then
  d_created=$(echo "$wl_docs" | jq -r '.create')
  d_updated=$(echo "$wl_docs" | jq -r '.update')
  d_skipped=$(echo "$wl_docs" | jq -r '.skip')
fi

t_added=$(echo "$ar_dash" | jq -r '.tags_added // 0')
t_removed=$(echo "$ar_dash" | jq -r '.tags_removed // 0')
if [ "$t_added" = "0" ] && [ "$t_removed" = "0" ]; then
  t_status="unchanged"
else
  t_status="changed"
fi

p_appended=$(echo "$ar_prog" | jq -r 'if .appended == true then "yes" else "no" end')
err_count=$(echo "$ar_errors" | jq -r 'length')

{
  echo "# Shelf Full Sync Summary"
  echo
  echo "**Date**: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "**Project**: $slug"
  echo
  echo "## Issues"
  echo "- Created: $i_created"
  echo "- Updated: $i_updated"
  echo "- Closed: $i_closed"
  echo "- Skipped: $i_skipped"
  echo
  echo "## Docs"
  echo "- Created: $d_created"
  echo "- Updated: $d_updated"
  echo "- Skipped: $d_skipped"
  echo
  echo "## Tags"
  echo "- Added: $t_added"
  echo "- Removed: $t_removed"
  echo "- Status: $t_status"
  echo
  echo "## Progress"
  echo "- Entry appended: $p_appended"
  echo
  echo "## Errors"
  echo "- Count: $err_count"
} > "$OUT"

cat "$OUT"
