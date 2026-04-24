#!/usr/bin/env bash
# disambiguate-slug.sh — numeric-suffix disambiguation for multi-theme distill.
#
# FR-017 of spec `coach-driven-capture-ergonomics`: multi-theme distill emission
# MUST route colliding `<date>-<slug>` directories onto numeric suffixes so each
# PRD gets its own canonical path.
#
# Per contracts/interfaces.md §Module: plugin-kiln/scripts/distill/ →
# disambiguate-slug.sh:
#   - First occurrence of each unique slug is un-suffixed: `<date>-<slug>`.
#   - Second and subsequent occurrences append `-2`, `-3`, ...
#   - MUST check `docs/features/` for pre-existing directories with the same
#     `<date>-<slug>` prefix and skip over them when numbering (to avoid
#     clobbering committed PRDs from earlier runs).
#
# Also implements research.md §4 slug-disambiguation algorithm: when the
# FIRST occurrence of a slug collides with a pre-existing committed
# `docs/features/<date>-<slug>/` directory, the first occurrence ALSO skips to
# the numeric suffix path.
#
# Exit codes:
#   0 — success; newline-delimited disambiguated dir names on stdout.
#   2 — usage error.
#
# Determinism: no timestamps, no $RANDOM, no env-varying strings. Given the
# same inputs and the same pre-existing `docs/features/` layout, output is
# byte-identical across runs (NFR-003).

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: disambiguate-slug.sh <date> <slug-1> [<slug-2> ...]

  <date>   — YYYY-MM-DD prefix.
  <slug-N> — theme slugs in selection order (one or more).

Env:
  DISTILL_FEATURES_DIR — override for the pre-existing-directory check.
                         Defaults to "docs/features". Tests set this to a
                         fixture directory so the algorithm can be exercised
                         in isolation.
EOF
  exit 2
}

# Must have date + at least one slug.
if [[ $# -lt 2 ]]; then
  usage
fi

DATE="$1"
shift

# Cheap date-shape validation — YYYY-MM-DD, 10 chars, two hyphens.
if ! [[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "error: date must be YYYY-MM-DD, got '$DATE'" >&2
  exit 2
fi

FEATURES_DIR="${DISTILL_FEATURES_DIR:-docs/features}"

# FR-017: skip over committed directories AND collision within the same run.
# Track per-slug occurrence count: `slug_counts[slug]` = number of times we've
# already emitted a path for this slug in this invocation (0 means not yet).
# We store counts in a parallel indexed-keys array because bash 3.2 (macOS
# default) lacks associative arrays.
declare -a SEEN_KEYS=()
declare -a SEEN_VALS=()

# lookup_count <slug> — echo current count or "0" if slug not seen yet.
lookup_count() {
  local needle="$1"
  local i
  for ((i = 0; i < ${#SEEN_KEYS[@]}; i++)); do
    if [[ "${SEEN_KEYS[i]}" == "$needle" ]]; then
      echo "${SEEN_VALS[i]}"
      return 0
    fi
  done
  echo "0"
}

# set_count <slug> <count> — update or append.
set_count() {
  local slug="$1"
  local val="$2"
  local i
  for ((i = 0; i < ${#SEEN_KEYS[@]}; i++)); do
    if [[ "${SEEN_KEYS[i]}" == "$slug" ]]; then
      SEEN_VALS[i]="$val"
      return 0
    fi
  done
  SEEN_KEYS+=("$slug")
  SEEN_VALS+=("$val")
}

# next_available <slug> — find the smallest suffix N such that
# <date>-<slug>[-N] is NOT already used (either in FEATURES_DIR or earlier
# in this invocation).
# Returns the full directory name (no trailing slash) on stdout.
next_available() {
  local slug="$1"
  local count
  count=$(lookup_count "$slug")

  if [[ "$count" -eq 0 ]]; then
    # First time we've seen this slug in this run. Check for pre-existing
    # committed dir.
    if [[ -d "${FEATURES_DIR}/${DATE}-${slug}" ]]; then
      # Research.md §4: pre-existing committed dir → skip to numeric suffix.
      # Start at `-2` (per FR-017: "first occurrence is un-suffixed" is the
      # ideal case; when pre-existing blocks that, we land on -2 as the
      # next unoccupied slot). Walk forward past any -2, -3, ... that also
      # pre-exist.
      local n=2
      while [[ -d "${FEATURES_DIR}/${DATE}-${slug}-${n}" ]]; do
        n=$((n + 1))
      done
      set_count "$slug" "$n"
      echo "${DATE}-${slug}-${n}"
    else
      # Clean slot. Record count=1 meaning "un-suffixed first occurrence
      # has been consumed."
      set_count "$slug" 1
      echo "${DATE}-${slug}"
    fi
  else
    # Not the first in-run occurrence. Emit `<date>-<slug>-N` where N is
    # the next suffix AFTER any that are currently used (in-run OR
    # pre-existing on disk).
    local n=$((count + 1))
    # When count==1, n==2 — correct ("-2" is the first suffix).
    # When count>=2, n==count+1 — normal increment.
    # Also skip past pre-existing committed -N suffixes on disk.
    while [[ -d "${FEATURES_DIR}/${DATE}-${slug}-${n}" ]]; do
      n=$((n + 1))
    done
    set_count "$slug" "$n"
    echo "${DATE}-${slug}-${n}"
  fi
}

# FR-017: emit one disambiguated dir name per input slug, in input order.
for slug in "$@"; do
  if [[ -z "$slug" ]]; then
    echo "error: empty slug" >&2
    exit 2
  fi
  next_available "$slug"
done
