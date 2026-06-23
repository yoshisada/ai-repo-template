#!/usr/bin/env bash
# parse-token-usage.sh — Parse token-usage totals from a stream-json transcript.
#
# Satisfies: FR-S-013 (token-parsing helper), NFR-S-008 (loud-failure on missing usage).
# Contract:  specs/research-first-foundation/contracts/interfaces.md §3.
#
# Usage:
#   parse-token-usage.sh <transcript-ndjson-path>
#
# Args:
#   <transcript-ndjson-path>   absolute path to a stream-json transcript file.
#                              The LAST envelope of type `result` carries the
#                              `usage` record.
#
# Stdout (on success): a single line, whitespace-delimited:
#   <input> <output> <cached_creation> <cached_read> <total>
#
# Stderr: diagnostics only.
#
# Exit:
#   0 — successfully parsed; stdout populated.
#   2 — `usage` record missing OR malformed; emits documented diagnostic.
#       NEVER silently substitutes zeros (NFR-S-008 anchor).
#
# Implementation notes:
# - Uses `jq` to parse stream-json envelopes. Empirical verification on
#   current Claude Code stream-json output (2026-04-25) shows the `usage`
#   record lives at top-level `.usage` on the LAST envelope of `type: result`,
#   NOT at `.message.usage`. The contract says "or equivalent path — verified
#   empirically"; this file enshrines that empirical finding.
# - Reentrant: same input → same output, byte-identical.
set -euo pipefail

if (( $# != 1 )); then
  echo "parse-token-usage.sh: expected 1 arg (transcript path), got $#" >&2
  exit 2
fi

transcript=$1

if [[ ! -f $transcript ]]; then
  echo "parse-token-usage.sh: transcript not found: $transcript" >&2
  exit 2
fi

# Find LAST envelope of type "result" and extract its `.usage` record.
# `tac` is not POSIX on macOS; use awk to track the last matching line.
last_result=$(awk '
  /"type":"result"/ { last = $0 }
  END { if (last) print last }
' "$transcript")

if [[ -z $last_result ]]; then
  echo "parse error: usage record missing in transcript: $transcript" >&2
  exit 2
fi

# Pull usage subdoc; null-coalesce nothing — we WANT loud failure on null.
# `// empty` would silently swallow; we use `// null` and check explicitly.
usage_json=$(printf '%s\n' "$last_result" | jq -c '.usage // null')

if [[ $usage_json == "null" || -z $usage_json ]]; then
  echo "parse error: usage record missing in transcript: $transcript" >&2
  exit 2
fi

# Read the four fields. `.input_tokens // null` etc — null guard.
read -r input output cached_creation cached_read < <(
  printf '%s\n' "$usage_json" | jq -r '
    [
      (.input_tokens // null),
      (.output_tokens // null),
      (.cache_creation_input_tokens // null),
      (.cache_read_input_tokens // null)
    ] | @tsv
  '
)

# Loud failure on any null — NEVER coerce to zero (NFR-S-008).
for v in "$input" "$output" "$cached_creation" "$cached_read"; do
  if [[ -z $v || $v == "null" ]]; then
    echo "parse error: usage record missing in transcript: $transcript" >&2
    exit 2
  fi
  # Sanity — must be non-negative integer.
  if ! [[ $v =~ ^[0-9]+$ ]]; then
    echo "parse error: usage field is not a non-negative integer ($v) in transcript: $transcript" >&2
    exit 2
  fi
done

total=$(( input + output + cached_creation + cached_read ))

printf '%s %s %s %s %s\n' "$input" "$output" "$cached_creation" "$cached_read" "$total"
