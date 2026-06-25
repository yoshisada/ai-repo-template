#!/usr/bin/env bash
# alloc-issue-filename.sh — atomically reserve a collision-safe issue filename.
#
# WHY: kiln-report-issue names issues `YYYY-MM-DD-<slug>.md`. Two issues created the
# same day with the same slug (similar titles, or concurrent captures) collide and one
# silently overwrites the other (MASTER_PLAN open question: "issue numbering collision").
# This allocator picks the first free `YYYY-MM-DD-<slug>[-N].md` and reserves it by
# creating the empty file under an flock, so concurrent callers never collide. The
# caller then writes the issue body into the printed path.
#
# Usage: alloc-issue-filename.sh <slug> [issues_dir] [date]
#   <slug>       kebab-case slug (required)
#   issues_dir   default .kiln/issues
#   date         default today (YYYY-MM-DD)
# Prints the reserved absolute-or-relative path on stdout. Exit non-zero on bad args.
#
# Concurrency: the reservation is an atomic O_EXCL create (`set -o noclobber; : > file`),
# which fails if the file already exists — so two concurrent callers can never both win
# the same name; the loser gets EEXIST and advances to the next suffix. This is race-free
# on every POSIX shell WITHOUT needing `flock` (macOS ships no flock), so there is no
# drift fallback to accept here.

set -euo pipefail

SLUG="${1:-}"
ISSUES_DIR="${2:-.kiln/issues}"
DATE="${3:-$(date -u +%Y-%m-%d)}"

if [[ -z "$SLUG" ]]; then
  echo "ERROR: missing <slug>" >&2
  echo "usage: alloc-issue-filename.sh <slug> [issues_dir] [date]" >&2
  exit 1
fi

# Normalize slug defensively: lowercase, non-alnum -> dash, collapse/trim dashes.
SLUG="$(printf '%s' "$SLUG" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/-+/-/g; s/^-//; s/-$//')"
[[ -z "$SLUG" ]] && SLUG="issue"

mkdir -p "$ISSUES_DIR"

# Reserve the first free name via atomic O_EXCL create. The subshell's `set -o noclobber`
# makes `: > file` fail (non-zero) if the file already exists, so the winner is decided by
# the kernel — no lock needed, race-free across processes.
base="${DATE}-${SLUG}"
candidate="${ISSUES_DIR}/${base}.md"
n=2
while ! ( set -o noclobber; : > "$candidate" ) 2>/dev/null; do
  candidate="${ISSUES_DIR}/${base}-${n}.md"
  n=$((n + 1))
  if (( n > 10000 )); then
    echo "ERROR: could not allocate an issue filename for slug '${SLUG}' under '${ISSUES_DIR}'" >&2
    exit 1
  fi
done
printf '%s\n' "$candidate"
