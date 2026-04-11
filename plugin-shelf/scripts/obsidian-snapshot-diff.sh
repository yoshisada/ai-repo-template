#!/usr/bin/env bash
# obsidian-snapshot-diff.sh
# Contract: specs/shelf-sync-efficiency/contracts/interfaces.md §8.2
#
# Reads two snapshot JSONs produced by obsidian-snapshot-capture.sh and
# prints a human-readable diff. Exit 0 if identical, 1 if any differences,
# 2 on error.
#
# Usage: obsidian-snapshot-diff.sh <baseline.json> <candidate.json>

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <baseline.json> <candidate.json>" >&2
  exit 2
fi

baseline=$1
candidate=$2

for f in "$baseline" "$candidate"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: file not found: $f" >&2
    exit 2
  fi
  if ! jq -e 'type == "array"' "$f" >/dev/null 2>&1; then
    echo "ERROR: not a JSON array: $f" >&2
    exit 2
  fi
done

diff_report=$(jq -n \
  --slurpfile a "$baseline" \
  --slurpfile b "$candidate" '
    def by_path(xs): xs | map({key: .path, value: .}) | from_entries;
    ($a[0] // []) as $base |
    ($b[0] // []) as $cand |
    by_path($base) as $bmap |
    by_path($cand) as $cmap |
    {
      added:   ((($cmap | keys) - ($bmap | keys)) | sort),
      removed: ((($bmap | keys) - ($cmap | keys)) | sort),
      changed: [
        ($bmap | keys[]) as $k |
        select($cmap[$k] != null and $bmap[$k] != $cmap[$k]) |
        {
          path: $k,
          frontmatter_diff: (
            if $bmap[$k].frontmatter == $cmap[$k].frontmatter then null
            else {
              before: $bmap[$k].frontmatter,
              after:  $cmap[$k].frontmatter
            } end
          ),
          body_changed: ($bmap[$k].body_sha256 != $cmap[$k].body_sha256)
        }
      ] | sort_by(.path)
    }
')

added=$(echo "$diff_report" | jq -r '.added | length')
removed=$(echo "$diff_report" | jq -r '.removed | length')
changed=$(echo "$diff_report" | jq -r '.changed | length')

if [ "$added" -eq 0 ] && [ "$removed" -eq 0 ] && [ "$changed" -eq 0 ]; then
  echo "Snapshots identical."
  exit 0
fi

echo "Snapshots differ:"
echo "  added:   $added"
echo "  removed: $removed"
echo "  changed: $changed"
echo

if [ "$added" -gt 0 ]; then
  echo "## Added"
  echo "$diff_report" | jq -r '.added[] | "  + \(.)"'
  echo
fi

if [ "$removed" -gt 0 ]; then
  echo "## Removed"
  echo "$diff_report" | jq -r '.removed[] | "  - \(.)"'
  echo
fi

if [ "$changed" -gt 0 ]; then
  echo "## Changed"
  echo "$diff_report" | jq -r '
    .changed[] |
    "  ~ \(.path)" +
    (if .body_changed then "  [body]" else "" end) +
    (if .frontmatter_diff != null then "  [frontmatter]" else "" end)
  '
  echo
  echo "## Frontmatter diffs"
  echo "$diff_report" | jq '.changed[] | select(.frontmatter_diff != null) | {path, frontmatter_diff}'
fi

exit 1
