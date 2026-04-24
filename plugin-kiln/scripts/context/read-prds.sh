#!/usr/bin/env bash
# read-prds.sh — scan docs/features/<date>-<slug>/PRD.md and emit a JSON array.
#
# FR-001 (prds[] field of ProjectContextSnapshot)
# FR-002 (missing-dir defensiveness — empty array, not crash)
# NFR-001 (<2 s on 50-PRD repo — single-awk + single-jq pass)
#
# Contract: specs/coach-driven-capture-ergonomics/contracts/interfaces.md
#   → Module: plugin-kiln/scripts/context/ → read-prds.sh
#
# Output shape per PRD:
#   { "path": "...", "slug": "...", "date": "...", "title": "...", "theme": "..." }
# Collection sorted ASC by path (NFR-002).
set -euo pipefail
export LC_ALL=C   # deterministic sort across macOS + Linux (NFR-002)

REPO_ROOT="${1:-}"
if [[ -z "$REPO_ROOT" ]]; then
  echo "usage: read-prds.sh <repo-root>" >&2
  exit 2
fi

FEATURES_DIR="$REPO_ROOT/docs/features"

if [[ ! -d "$FEATURES_DIR" ]]; then
  echo "[]"   # FR-002
  exit 0
fi

mapfile -t PRD_PATHS < <(find "$FEATURES_DIR" -mindepth 2 -maxdepth 2 -type f -name 'PRD.md' 2>/dev/null | sort)

if [[ "${#PRD_PATHS[@]}" -eq 0 ]]; then
  echo "[]"
  exit 0
fi

# Single awk pass emits one TSV line per PRD:
#   rel-path \t slug \t date \t title \t theme
# A single `jq -R -s` folds the TSV into JSON.
PRD_TSV="$(awk -v ROOT="$REPO_ROOT/" '
  function reset() { title=""; theme=""; in_fm=0; seen_open=0 }
  function emit() {
    rel = FILENAME
    sub("^" ROOT, "", rel)
    # dir = .../<date>-<slug>/PRD.md
    dir = rel
    sub(/\/PRD\.md$/, "", dir)
    sub(/.*\//, "", dir)
    date_part = substr(dir, 1, 10)
    slug_part = substr(dir, 12)
    print rel "\t" slug_part "\t" date_part "\t" title "\t" theme
  }
  FNR == 1 { if (file_cnt++) emit(); reset() }
  {
    # Title = first "# " line anywhere in the file (body).
    if (title == "" && $0 ~ /^# /) {
      title = $0
      sub(/^# /, "", title)
    }
    # Frontmatter framing for theme extraction.
    if ($0 ~ /^---[[:space:]]*$/) {
      if (!seen_open) { seen_open = 1; in_fm = 1; next }
      else if (in_fm) { in_fm = 0; next }
    }
    if (in_fm && theme == "" && $0 ~ /^theme:[[:space:]]/) {
      theme = $0
      sub(/^theme:[[:space:]]*/, "", theme)
      gsub(/^["\x27]|["\x27][[:space:]]*$/, "", theme)
      sub(/[[:space:]]+$/, "", theme)
    }
  }
  END { if (file_cnt > 0) emit() }
' "${PRD_PATHS[@]}")"

printf '%s\n' "$PRD_TSV" | jq -R -s '
  split("\n")
  | map(select(length > 0))
  | map(
      split("\t") as $f
      | {
          path:  $f[0],
          slug:  $f[1],
          date:  $f[2],
          title: $f[3],
          theme: (if $f[4] == "" then null else $f[4] end)
        }
    )
'
