#!/usr/bin/env bash
# extract-signal-h.sh — Signal (h): external feedback gets filtered.
#
# Vision signal (h): signals that match real use land on the roadmap;
# hypothetical "wouldn't it be cool" asks don't.
#
# Heuristic (V1, deterministic): count declined-records under
# `.kiln/roadmap/items/declined/*.md` AND `.kiln/feedback/*.md` files. Each
# declined-record is direct evidence of an explicit "no" — the exact filter
# behaviour the signal points at. We report `<declined>/<feedback>` as the
# row's current_value and tag `on-track` when at least one decline exists,
# else `at-risk` to surface that no filtering has happened.
#
# FR-018: each extractor is invocable in isolation. Read-only.
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme D — extract-signal-<a..h>.sh".

set -euo pipefail

SIGNAL_ID="(h)"
TARGET=">=1 declined-record cross-referenced with .kiln/feedback/"

REPO_ROOT="${KILN_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"

if [[ -z "$REPO_ROOT" ]]; then
  printf '%s\t-\t-\tunmeasurable\tno repo root\n' "$SIGNAL_ID"
  exit 4
fi

DECLINED_DIR="$REPO_ROOT/.kiln/roadmap/items/declined"
FEEDBACK_DIR="$REPO_ROOT/.kiln/feedback"

if [[ ! -d "$DECLINED_DIR" && ! -d "$FEEDBACK_DIR" ]]; then
  printf '%s\t-\t-\tunmeasurable\tneither declined/ nor feedback/ present\n' "$SIGNAL_ID"
  exit 4
fi

DECLINED=0
if [[ -d "$DECLINED_DIR" ]]; then
  while IFS= read -r -d '' f; do
    DECLINED=$((DECLINED + 1))
  done < <(find "$DECLINED_DIR" -maxdepth 1 -name '*.md' -print0 2>/dev/null || true)
fi

FEEDBACK=0
if [[ -d "$FEEDBACK_DIR" ]]; then
  while IFS= read -r -d '' f; do
    FEEDBACK=$((FEEDBACK + 1))
  done < <(find "$FEEDBACK_DIR" -maxdepth 1 -name '*.md' -print0 2>/dev/null || true)
fi

if (( DECLINED >= 1 )); then
  STATUS="on-track"
else
  STATUS="at-risk"
fi

EVIDENCE=".kiln/roadmap/items/declined/ + .kiln/feedback/ counts"
printf '%s\t%s declined / %s feedback\t%s\t%s\t%s\n' \
  "$SIGNAL_ID" "$DECLINED" "$FEEDBACK" "$TARGET" "$STATUS" "$EVIDENCE"
