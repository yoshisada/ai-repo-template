#!/usr/bin/env bash
# detect-un-promoted.sh — Classify candidate issue/feedback source paths as
# `promoted` or `un-promoted` for the distill gate.
#
# FR-004 / workflow-governance FR-004: /kiln:kiln-distill MUST refuse to
# bundle raw issues/feedback that have not been promoted to roadmap items.
#
# Contract: specs/workflow-governance/contracts/interfaces.md §1 (Module 1)
#
# Usage:
#   bash detect-un-promoted.sh <source-path> [<source-path> ...]
#
# Stdout (NDJSON, one per input):
#   {"path": "<path>", "status": "promoted|un-promoted", "roadmap_item": "<path|null>"}
#
# Exit codes (per contract):
#   0 success
#   2 usage error (no arguments)
#   3 unrecoverable scan error (frontmatter parse failure) — stderr names the
#     offending path; NO stdout is emitted.
#
# Classification rule (contract §1):
#   status == "promoted"  iff  frontmatter.status == "promoted"
#                         AND  frontmatter.roadmap_item is a real file
#                         AND  roadmap_item's frontmatter.promoted_from ==
#                              this input's repo-relative path.
#   Otherwise un-promoted.
set -euo pipefail
LC_ALL=C
export LC_ALL

if [[ $# -eq 0 ]]; then
  echo "detect-un-promoted: usage: detect-un-promoted.sh <source-path> [<source-path> ...]" >&2
  exit 2
fi

# Read one frontmatter field from a markdown file (simple scalar lookup).
# Returns empty string when missing. Handles "key: value" and quoted values.
read_fm_scalar() {
  local file=$1 key=$2
  awk -v k="$key" '
    /^---[[:space:]]*$/ { fm++; next }
    fm == 1 {
      # Match `key:` at line start, capture the rest.
      if (match($0, "^" k ":[[:space:]]*")) {
        v = substr($0, RSTART + RLENGTH)
        sub(/[[:space:]]+$/, "", v)
        # strip surrounding quotes
        gsub(/^"|"$/, "", v)
        gsub(/^'\''|'\''$/, "", v)
        print v
        exit
      }
    }
    fm >= 2 { exit }
  ' "$file"
}

emit() {
  # emit <path> <status> <roadmap-item-or-empty>
  local path=$1 status=$2 ri=${3-}
  local ri_json
  if [[ -z "$ri" ]]; then
    ri_json=null
  else
    local esc
    esc=${ri//\\/\\\\}
    esc=${esc//\"/\\\"}
    ri_json="\"$esc\""
  fi
  local path_esc
  path_esc=${path//\\/\\\\}
  path_esc=${path_esc//\"/\\\"}
  printf '{"path":"%s","status":"%s","roadmap_item":%s}\n' \
    "$path_esc" "$status" "$ri_json"
}

for input in "$@"; do
  if [[ ! -f "$input" ]]; then
    echo "detect-un-promoted: input not found: $input" >&2
    exit 3
  fi

  # First line MUST be the frontmatter opener for us to classify. A source
  # with no frontmatter is un-promoted by definition (promote-source.sh
  # would refuse with exit 4 until the user adds frontmatter).
  first=$(head -n1 "$input")
  if [[ "$first" != "---" ]]; then
    emit "$input" "un-promoted" ""
    continue
  fi

  status=$(read_fm_scalar "$input" status)
  roadmap_item=$(read_fm_scalar "$input" roadmap_item)

  # Fast-path: if status isn't "promoted", it's un-promoted regardless.
  if [[ "$status" != "promoted" ]]; then
    emit "$input" "un-promoted" ""
    continue
  fi

  # status == promoted — verify the back-reference actually resolves.
  if [[ -z "$roadmap_item" ]] || [[ ! -f "$roadmap_item" ]]; then
    # Status says promoted but the back-reference is missing. Treat as
    # un-promoted so the user is nudged to fix it; surface the missing
    # roadmap_item on stderr for visibility.
    echo "detect-un-promoted: $input has status: promoted but roadmap_item ($roadmap_item) is missing — classifying as un-promoted" >&2
    emit "$input" "un-promoted" ""
    continue
  fi

  promoted_from=$(read_fm_scalar "$roadmap_item" promoted_from)
  if [[ "$promoted_from" != "$input" ]]; then
    # Reciprocal link broken — treat as un-promoted so the user resolves the
    # inconsistency.
    echo "detect-un-promoted: $input says roadmap_item=$roadmap_item but that item's promoted_from ($promoted_from) does not match — classifying as un-promoted" >&2
    emit "$input" "un-promoted" ""
    continue
  fi

  emit "$input" "promoted" "$roadmap_item"
done
