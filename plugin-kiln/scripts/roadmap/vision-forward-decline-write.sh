#!/usr/bin/env bash
# vision-forward-decline-write.sh — write a `kind: non-goal` declined-record.
#
# FR-013 / FR-022 / vision-tooling FR-013/FR-022: declined-suggestion files go
# to .kiln/roadmap/items/declined/<date>-<slug>-considered-and-declined.md
# (separate subdir, NOT the main item list — OQ-2 resolution).
#
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme C —
#           vision-forward-decline-write.sh"
#
# Usage:   vision-forward-decline-write.sh <title> <tag> <body> <evidence>
# Stdout:  single line `declined: <repo-relative-path>`.
# Exit:    0 success.
#          1 usage error.
#          2 slug-collision after retry exhaustion (-1..-9 suffixes).
#          3 filesystem error.
# Side-effects: creates .kiln/roadmap/items/declined/ if missing, writes ONE
#               new file. No other I/O.
set -u
LC_ALL=C
export LC_ALL

if [ "$#" -ne 4 ]; then
  echo "vision-forward-decline-write: usage: vision-forward-decline-write.sh <title> <tag> <body> <evidence>" >&2
  exit 1
fi

TITLE="$1"
TAG="$2"
BODY="$3"
EVIDENCE="$4"

[ -n "$TITLE" ]    || { echo "vision-forward-decline-write: empty title" >&2; exit 1; }
[ -n "$TAG" ]      || { echo "vision-forward-decline-write: empty tag" >&2; exit 1; }
[ -n "$EVIDENCE" ] || { echo "vision-forward-decline-write: empty evidence" >&2; exit 1; }

DECLINED_DIR="${DECLINED_DIR:-.kiln/roadmap/items/declined}"
mkdir -p "$DECLINED_DIR" 2>/dev/null || { echo "vision-forward-decline-write: cannot create $DECLINED_DIR" >&2; exit 3; }

# Slugify title: lowercase, alnum + hyphens only, collapse hyphens, trim.
slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-60
}

DATE=$(date -u +%Y-%m-%d)
SLUG=$(slugify "$TITLE")
[ -z "$SLUG" ] && SLUG="declined"

BASE="${DATE}-${SLUG}-considered-and-declined"
TARGET="${DECLINED_DIR}/${BASE}.md"

# Slug-collision retry up to -9.
attempt=0
while [ -e "$TARGET" ] && [ "$attempt" -lt 9 ]; do
  attempt=$((attempt + 1))
  TARGET="${DECLINED_DIR}/${BASE}-${attempt}.md"
done

if [ -e "$TARGET" ]; then
  echo "vision-forward-decline-write: slug collision exhausted for ${BASE}" >&2
  exit 2
fi

# YAML-escape values that could contain `:` or quotes — wrap in double quotes
# and escape internal `"` as `\"`.
yaml_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

TITLE_E=$(yaml_escape "$TITLE")
TAG_E=$(yaml_escape "$TAG")
EV_E=$(yaml_escape "$EVIDENCE")

TMP=$(mktemp "${TARGET}.XXXXXX") || { echo "vision-forward-decline-write: mktemp failed" >&2; exit 3; }

{
  printf -- '---\n'
  printf 'title: "%s"\n' "$TITLE_E"
  printf 'tag: "%s"\n' "$TAG_E"
  printf 'kind: non-goal\n'
  printf 'state: declined\n'
  printf 'declined_date: %s\n' "$DATE"
  printf 'evidence: "%s"\n' "$EV_E"
  printf -- '---\n'
  printf '\n'
  printf '%s\n' "$BODY"
} > "$TMP" || { rm -f "$TMP"; echo "vision-forward-decline-write: temp-write failed" >&2; exit 3; }

mv "$TMP" "$TARGET" || { rm -f "$TMP"; echo "vision-forward-decline-write: mv failed" >&2; exit 3; }

printf 'declined: %s\n' "$TARGET"
