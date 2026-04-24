#!/usr/bin/env bash
# tap-emit.sh — Emit one TAP v14 test-result line (with optional YAML diagnostic).
#
# Satisfies: FR-004 (TAP v14 grammar), NFR-003 (deterministic stdout — no
#            UUIDs, no timestamps in the `ok`/`not ok` lines)
# Contract:  contracts/interfaces.md §7.3 + §2 (TAP grammar)
#
# Usage:
#   tap-emit.sh <test-number> <test-name> <status> [<diagnostic-yaml-file>]
#
# Args:
#   <test-number>             1-indexed positive integer
#   <test-name>               directory basename; must not contain newlines
#   <status>                  one of: pass | fail | skip
#   <diagnostic-yaml-file>    OPTIONAL (required when status=fail). Absolute
#                             path to a file containing the YAML diagnostic
#                             BODY without `---`/`...` delimiters and without
#                             leading indent; this script adds them.
#
# Stdout: exactly one TAP line (pass/skip) OR one TAP line plus an indented
#         YAML block (fail). Nothing else. Per NFR-003, the `ok`/`not ok`
#         line itself contains no UUIDs or timestamps.
# Stderr: diagnostics only.
# Exit:   0 on valid invocation, 2 on arg error.
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "tap-emit.sh: expected 3 or 4 args (test-number test-name status [diag-file]), got $#" >&2
  exit 2
fi

test_number=$1
test_name=$2
status=$3
diag_file=${4:-}

# Arg validation.
if ! [[ $test_number =~ ^[1-9][0-9]*$ ]]; then
  echo "tap-emit.sh: test-number must be a positive integer, got: $test_number" >&2
  exit 2
fi
if [[ $test_name == *$'\n'* ]]; then
  echo "tap-emit.sh: test-name must not contain newlines" >&2
  exit 2
fi
case $status in
  pass|fail|skip) ;;
  *) echo "tap-emit.sh: status must be pass|fail|skip, got: $status" >&2; exit 2 ;;
esac

# Emit the line.
case $status in
  pass)
    # contracts §2: `ok <N> - <test-name>`
    printf 'ok %s - %s\n' "$test_number" "$test_name"
    ;;
  skip)
    # contracts §2: `ok <N> - <test-name> # SKIP <reason>`
    # Reason = first line of diagnostic file (if provided) or "no reason given"
    reason="no reason given"
    if [[ -n $diag_file && -f $diag_file ]]; then
      # Read first non-empty line as reason. Strip trailing \r just in case.
      reason=$(awk 'NF { sub(/\r$/,""); print; exit }' "$diag_file")
      [[ -z $reason ]] && reason="no reason given"
    fi
    printf 'ok %s - %s # SKIP %s\n' "$test_number" "$test_name" "$reason"
    ;;
  fail)
    # contracts §2: `not ok <N> - <test-name>` followed by indented YAML block
    printf 'not ok %s - %s\n' "$test_number" "$test_name"
    if [[ -n $diag_file ]]; then
      if [[ ! -f $diag_file ]]; then
        echo "tap-emit.sh: diag-file does not exist: $diag_file" >&2
        exit 2
      fi
      # Delimiters + 2-space indent per contracts §2.
      printf '  ---\n'
      # Indent every line of the diag file by 2 spaces. Use `sed` for stability.
      sed 's/^/  /' "$diag_file"
      printf '  ...\n'
    else
      # `fail` without a diag file is allowed but produces no YAML block.
      # Emit empty delimiters so parsers don't choke.
      printf '  ---\n  classification: "fail"\n  ...\n'
    fi
    ;;
esac

exit 0
