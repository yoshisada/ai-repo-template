#!/usr/bin/env bash
# vision-forward-decision.sh — per-suggestion confirm-never-silent prompt.
#
# FR-012 / vision-tooling FR-012: for each suggestion, three actions are
# offered: accept (caller invokes /kiln:kiln-roadmap --promote hand-off),
# decline (caller invokes vision-forward-decline-write.sh), skip (no record).
#
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme C —
#           vision-forward-decision.sh"
#
# Usage: vision-forward-decision.sh
#   stdin = ONE suggestion block (4 lines: title:, tag:, evidence:, body:).
#   stdout = single line `accept|decline|skip`.
#   stderr = the rendered prompt.
# Exit:  0 always (user chose).
#        2 stdin malformed (not a 4-line block in the right shape).
set -u
LC_ALL=C
export LC_ALL

# Read the four lines.
read_line() {
  local var="$1"
  IFS= read -r "$var" || return 1
  return 0
}

read_line L1 || { echo "vision-forward-decision: missing title line" >&2; exit 2; }
read_line L2 || { echo "vision-forward-decision: missing tag line" >&2; exit 2; }
read_line L3 || { echo "vision-forward-decision: missing evidence line" >&2; exit 2; }
read_line L4 || { echo "vision-forward-decision: missing body line" >&2; exit 2; }

case "$L1" in title:*) ;; *) echo "vision-forward-decision: malformed title line" >&2; exit 2 ;; esac
case "$L2" in tag:*)   ;; *) echo "vision-forward-decision: malformed tag line" >&2; exit 2 ;; esac
case "$L3" in evidence:*) ;; *) echo "vision-forward-decision: malformed evidence line" >&2; exit 2 ;; esac
case "$L4" in body:*)  ;; *) echo "vision-forward-decision: malformed body line" >&2; exit 2 ;; esac

# Render the prompt to stderr (per contract).
{
  printf '\n'
  printf '  %s\n' "$L1"
  printf '  %s\n' "$L2"
  printf '  %s\n' "$L3"
  printf '  %s\n' "$L4"
  printf '[a]ccept / [d]ecline / [s]kip: '
} >&2

# Read a single line of choice. If stdin runs out, default to skip
# (confirm-never-silent: empty input is treated as the safest no-op).
CHOICE=""
if IFS= read -r CHOICE; then
  :
fi

# Normalize.
CHOICE_NORM=$(printf '%s' "$CHOICE" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

case "$CHOICE_NORM" in
  a|accept)  printf 'accept\n' ;;
  d|decline) printf 'decline\n' ;;
  s|skip|"") printf 'skip\n' ;;
  *)         printf 'skip\n' ;;
esac
exit 0
