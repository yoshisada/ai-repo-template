#!/usr/bin/env bash
# FR-009: Parse "File / Current / Proposed / Why" blocks from a retro issue body.
# Contract: specs/workflow-governance/contracts/interfaces.md Module 3 §parse-pi-blocks.sh
#
# Input (stdin): the full issue body markdown.
# Arg 1: issue number (integer).
# Output (stdout): newline-delimited JSON, one record per block, in source order.
#
# Recognized block shape:
#   ### PI-<N>
#   **File**: <path>
#   **Current**: <text, may span multiple lines until next bold field>
#   **Proposed**: <text>
#   **Why**: <text>
#
# Blocks missing any of the four bold fields emit a parse_error record with
# line_range. Other blocks continue to parse.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "parse-pi-blocks.sh: issue number required" >&2
  echo "usage: parse-pi-blocks.sh <issue-number>" >&2
  exit 2
fi
ISSUE_NUMBER="$1"

# jq escaper — fall back to python if jq is missing (should not happen; jq is a declared dep).
json_escape() {
  # Use jq's @json filter for correctness on newlines, quotes, backslashes.
  jq -Rs . <<<"$1"
}

# Read stdin into a temp file so we can iterate line numbers deterministically.
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
cat >"$TMP"

# Ensure a trailing newline — command-substitution callers often strip it, and
# `sed -n N,Mp` + `wc -l` both under-count when the final line is unterminated,
# which truncates the last PI block's slice and drops its **Why** field.
if [[ -s "$TMP" ]] && [[ $(tail -c 1 "$TMP" | wc -l | tr -d ' ') -eq 0 ]]; then
  printf '\n' >>"$TMP"
fi

TOTAL_LINES=$(wc -l < "$TMP" | tr -d ' ')
# Collect PI header line numbers.
HEADER_LINES=$(grep -nE '^### PI-[A-Za-z0-9_-]+' "$TMP" | cut -d: -f1 || true)

if [[ -z "$HEADER_LINES" ]]; then
  # No PI blocks at all — emit nothing (contract allows empty stream).
  exit 0
fi

# Convert header lines into an array.
readarray -t HEADERS <<<"$HEADER_LINES"

# For each header, the block spans [header_line .. next_header_line - 1] (or EOF).
NUM_HEADERS=${#HEADERS[@]}
for ((i = 0; i < NUM_HEADERS; i++)); do
  START=${HEADERS[$i]}
  if (( i + 1 < NUM_HEADERS )); then
    END=$((HEADERS[$i+1] - 1))
  else
    END="$TOTAL_LINES"
  fi

  # Extract block text.
  BLOCK=$(sed -n "${START},${END}p" "$TMP")

  # PI id is everything after "### PI-" on the first line.
  PI_ID_RAW=$(printf '%s\n' "$BLOCK" | head -1 | sed -E 's/^### (PI-[A-Za-z0-9_-]+).*/\1/')
  PI_ID="${PI_ID_RAW:-PI-unknown}"

  # Extract each bold field. Fields may span multiple lines — a field ends at the
  # next **Bold**: line OR at a blank-line separator OR at the end of block.
  extract_field() {
    local field="$1"
    # Use awk to capture the value after "**Field**:" and continue grabbing lines
    # until the next "**Field**:" or end of block.
    printf '%s\n' "$BLOCK" | awk -v field="$field" '
      BEGIN { collecting = 0; buf = ""; found = 0 }
      {
        line = $0
        # Check for start of target field.
        if (match(line, "^\\*\\*" field "\\*\\*: ?")) {
          collecting = 1; found = 1
          buf = substr(line, RSTART + RLENGTH)
          next
        }
        # Check for start of ANY other bold field → stop collecting target.
        if (collecting && match(line, "^\\*\\*[A-Za-z_-]+\\*\\*: ?")) {
          collecting = 0
          next
        }
        if (collecting) {
          buf = buf "\n" line
        }
      }
      END {
        if (found) {
          # Trim trailing empty lines that are just spacing between blocks.
          sub(/[[:space:]]*$/, "", buf)
          print buf
        }
      }
    '
  }

  FILE_VAL=$(extract_field "File")
  CURRENT_VAL=$(extract_field "Current")
  PROPOSED_VAL=$(extract_field "Proposed")
  WHY_VAL=$(extract_field "Why")

  # Missing field detection — use presence-of-field-header, not just non-empty value,
  # since an intentionally empty field is still "present" per the contract.
  MISSING=""
  printf '%s\n' "$BLOCK" | grep -qE '^\*\*File\*\*: ?'     || MISSING="File"
  [[ -z "$MISSING" ]] && { printf '%s\n' "$BLOCK" | grep -qE '^\*\*Current\*\*: ?'  || MISSING="Current"; }
  [[ -z "$MISSING" ]] && { printf '%s\n' "$BLOCK" | grep -qE '^\*\*Proposed\*\*: ?' || MISSING="Proposed"; }
  [[ -z "$MISSING" ]] && { printf '%s\n' "$BLOCK" | grep -qE '^\*\*Why\*\*: ?'      || MISSING="Why"; }

  if [[ -n "$MISSING" ]]; then
    # Emit parse_error record.
    jq -n \
      --arg issue_number "$ISSUE_NUMBER" \
      --arg pi_id "$PI_ID" \
      --arg err "missing field: $MISSING" \
      --arg lr "${START}-${END}" \
      '{issue_number: ($issue_number | tonumber), pi_id: $pi_id, parse_error: $err, line_range: $lr}' \
      -c
    continue
  fi

  # Trim leading whitespace on FILE_VAL (path), leave text fields as-is.
  FILE_VAL=$(printf '%s' "$FILE_VAL" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Retro templates wrap Current/Proposed prose in matched outer double-quotes
  # (`**Current**: "..."`). Strip them so verbatim-substring matching against
  # the target file works — files contain the prose without quote wrapping.
  strip_outer_quotes() {
    local v="$1"
    if [[ "${v:0:1}" == '"' && "${v: -1}" == '"' ]]; then
      v="${v:1:${#v}-2}"
    fi
    printf '%s' "$v"
  }
  CURRENT_VAL=$(strip_outer_quotes "$CURRENT_VAL")
  PROPOSED_VAL=$(strip_outer_quotes "$PROPOSED_VAL")

  # The target anchor is the FIRST line of CURRENT that starts with "#" — that
  # is the heading the PI points at. If none, fall back to the first non-empty
  # line of CURRENT (verbatim prose substring) so the classifier can locate
  # the PI's section in the target file. The previous fallback to FILE_VAL
  # guaranteed-stale every prose-anchored PI because files don't reference
  # their own path.
  ANCHOR=$(printf '%s\n' "$CURRENT_VAL" | awk '/^#/{print; exit}')
  if [[ -z "$ANCHOR" ]]; then
    ANCHOR=$(printf '%s\n' "$CURRENT_VAL" | awk 'NF{print; exit}')
  fi
  if [[ -z "$ANCHOR" ]]; then
    ANCHOR="$FILE_VAL"
  fi

  jq -n \
    --arg issue_number "$ISSUE_NUMBER" \
    --arg pi_id "$PI_ID" \
    --arg file "$FILE_VAL" \
    --arg anchor "$ANCHOR" \
    --arg current "$CURRENT_VAL" \
    --arg proposed "$PROPOSED_VAL" \
    --arg why "$WHY_VAL" \
    '{issue_number: ($issue_number | tonumber), pi_id: $pi_id, file: $file, anchor: $anchor, current: $current, proposed: $proposed, why: $why}' \
    -c
done
