#!/usr/bin/env bash
# unique-filename.sh
# FR-015
#
# Given a directory, a date, and a base slug, returns a filename that does not
# collide with any existing file in the directory. Appends "-2", "-3", ... to
# the slug portion until a free slot is found. Never creates the file.
#
# Invocation:
#   bash unique-filename.sh <dir> <date> <slug>
#
# stdout: collision-free basename (e.g., "2026-04-20-auth-bug-3.md").
# stderr: silent on success; one line on failure.
# exit:
#   0 — basename emitted.
#   1 — dir missing, or suffix counter exceeded 999.

set -u
LC_ALL=C
export LC_ALL

dir="${1:-}"
date="${2:-}"
slug="${3:-}"

if [ -z "$dir" ] || [ -z "$date" ] || [ -z "$slug" ]; then
  printf 'unique-filename: <dir> <date> <slug> required\n' >&2
  exit 1
fi

if [ ! -d "$dir" ]; then
  printf 'unique-filename: dir %s does not exist\n' "$dir" >&2
  exit 1
fi

base="${date}-${slug}"
candidate="${base}.md"
if [ ! -e "${dir}/${candidate}" ]; then
  printf '%s\n' "$candidate"
  exit 0
fi

n=2
while [ "$n" -le 999 ]; do
  candidate="${base}-${n}.md"
  if [ ! -e "${dir}/${candidate}" ]; then
    printf '%s\n' "$candidate"
    exit 0
  fi
  n=$((n + 1))
done

printf 'unique-filename: suffix counter exceeded 999 for %s/%s\n' "$dir" "$base" >&2
exit 1
