#!/usr/bin/env bash
# render-row.sh — render a single Theme D scorecard row in pipe-delimited shape.
#
# FR-016: Each row is `| <signal-id> | <current-value> | <target> | <status> | <evidence> |`.
# Pipes inside argument values are escaped to `\|` so the column shape is preserved.
#
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme D — render-row.sh".
#
# Usage:
#   render-row.sh <signal-id> <current-value> <target> <status> <evidence>
#
# Exit:
#   0 — valid row emitted on stdout.
#   2 — <status> not in {on-track, at-risk, unmeasurable}.

set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "render-row: usage: render-row.sh <signal-id> <current-value> <target> <status> <evidence>" >&2
  exit 1
fi

SIGNAL_ID="$1"
CURRENT_VALUE="$2"
TARGET="$3"
STATUS="$4"
EVIDENCE="$5"

# FR-016: validate <status> against the closed enum.
case "$STATUS" in
  on-track|at-risk|unmeasurable) ;;
  *)
    echo "render-row: unknown status '$STATUS' (allowed: on-track, at-risk, unmeasurable)" >&2
    exit 2
    ;;
esac

# FR-016: escape embedded pipes to keep the column shape intact.
escape_pipe() {
  # shellcheck disable=SC2001
  printf '%s' "$1" | sed 's/|/\\|/g'
}

printf '| %s | %s | %s | %s | %s |\n' \
  "$(escape_pipe "$SIGNAL_ID")" \
  "$(escape_pipe "$CURRENT_VALUE")" \
  "$(escape_pipe "$TARGET")" \
  "$(escape_pipe "$STATUS")" \
  "$(escape_pipe "$EVIDENCE")"
