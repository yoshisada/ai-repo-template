#!/usr/bin/env bash
# snapshot-diff.sh — per-fixture byte-identity comparator.
#
# Satisfies: NFR-R-8 (snapshot-diff comparator pinned), R-R-3 mitigation
# Contract:  specs/wheel-test-runner-extraction/contracts/interfaces.md §3
#
# Usage:
#   snapshot-diff.sh <mode> <baseline-path> <candidate-path>
#
# Modes:
#   bats                          — pure-deterministic bats TAP output (no exclusions)
#   verdict-report                — kiln-test verdict report; section-level body excl.
#                                   for `## Last 50 transcript envelopes` + line-level
#                                   timestamp/UUID/abs-path normalization
#   verdict-report-deterministic  — fast plugin-skill fixture verdict report; line-level
#                                   normalization only (no section-level body excl.)
#
# Exit codes:
#   0 — byte-identical (post-normalization)
#   1 — differences found (delta lines emitted to stdout)
#   2 — usage / file-not-found error (stderr diagnostic)
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: snapshot-diff.sh <mode> <baseline-path> <candidate-path>" >&2
  echo "  modes: bats | verdict-report | verdict-report-deterministic" >&2
  exit 2
fi

mode=$1
baseline=$2
candidate=$3

if [[ ! -f $baseline ]]; then
  echo "baseline not found: $baseline" >&2
  exit 2
fi
if [[ ! -f $candidate ]]; then
  echo "candidate not found: $candidate" >&2
  exit 2
fi

# Normalization function — emits to stdout the file content with
# per-mode exclusions applied. See contracts/interfaces.md §3 + §4.
normalize() {
  local file=$1
  local m=$2
  case $m in
    bats)
      # Pure-deterministic; no normalization.
      cat "$file"
      ;;
    verdict-report)
      # Section-level body exclusion for `## Last 50 transcript envelopes`.
      # Everything from that header onward is replaced with a single placeholder.
      awk '
        BEGIN { excluded = 0 }
        /^## Last 50 transcript envelopes[[:space:]]*$/ {
          print
          print "<TRANSCRIPT-BODY-EXCLUDED>"
          excluded = 1
          exit
        }
        { print }
      ' "$file" \
        | sed -E \
            -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.,][0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?/<TIMESTAMP>/g' \
            -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/<UUID>/g' \
            -e 's|/tmp/kiln-test-<UUID>(/[^[:space:]]*)?|/tmp/kiln-test-<UUID>|g' \
            -e 's|/Users/[^/]+/[^[:space:]]*|<ABS-PATH>|g'
      ;;
    verdict-report-deterministic)
      sed -E \
        -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.,][0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?/<TIMESTAMP>/g' \
        -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/<UUID>/g' \
        -e 's|/tmp/kiln-test-<UUID>(/[^[:space:]]*)?|/tmp/kiln-test-<UUID>|g' \
        -e 's|/Users/[^/]+/[^[:space:]]*|<ABS-PATH>|g' \
        "$file"
      ;;
    *)
      echo "unknown mode: $m (expected bats | verdict-report | verdict-report-deterministic)" >&2
      exit 2
      ;;
  esac
}

# Compare normalized streams via diff -u.
diff -u <(normalize "$baseline" "$mode") <(normalize "$candidate" "$mode")
