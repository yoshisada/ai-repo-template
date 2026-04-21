#!/usr/bin/env bash
# strip-credentials.sh
# FR-026
#
# Reads arbitrary text on stdin and removes any full-line match against a
# line in .kiln/qa/.env.test. Comments and blank lines in the env file are
# skipped so they don't accidentally strip legitimate content.
#
# Invocation: bash strip-credentials.sh
# stdin: arbitrary text.
# stdout: filtered text (same as stdin when no env file / no match).
# stderr: silent on success.
# exit:
#   0 — always on no-file or successful filter.
#   1 — .kiln/qa/.env.test present but unreadable.

set -u
LC_ALL=C
export LC_ALL

env_file=".kiln/qa/.env.test"

if [ ! -e "$env_file" ]; then
  # No credentials to strip — passthrough.
  cat
  exit 0
fi

if [ ! -r "$env_file" ]; then
  printf 'strip-credentials: %s is not readable\n' "$env_file" >&2
  exit 1
fi

# Build a filter file containing only non-blank, non-comment lines. Each line
# becomes a verbatim full-line pattern for `grep -F -x -v -f`.
tmp_filter=$(mktemp)
trap 'rm -f "$tmp_filter"' EXIT

grep -E -v '^[[:space:]]*(#|$)' "$env_file" > "$tmp_filter" || true

if [ ! -s "$tmp_filter" ]; then
  # Env file had only comments/blanks — nothing to strip.
  cat
  exit 0
fi

grep -F -x -v -f "$tmp_filter" || true
exit 0
