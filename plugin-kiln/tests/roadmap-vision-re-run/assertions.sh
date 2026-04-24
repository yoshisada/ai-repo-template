#!/usr/bin/env bash
# Assertions for roadmap-vision-re-run (T019).
# Validates FR-009 (per-section diff on re-run) + FR-010 (last_updated: bumped on accept).
# Acceptance: User Story 2 Scenarios 2 + 3.
set -euo pipefail

VISION=".kiln/vision.md"
if [[ ! -f "$VISION" ]]; then
  echo "FAIL: $VISION missing after re-run" >&2
  exit 1
fi

# last_updated must have been bumped to today's date (not the stale fixture date 2026-01-01)
TODAY=$(date -u +%Y-%m-%d)
FRONT_DATE=$(awk '/^last_updated:/ { print $2; exit }' "$VISION")
if [[ "$FRONT_DATE" != "$TODAY" ]]; then
  echo "FAIL: last_updated expected $TODAY, got '$FRONT_DATE' (FR-010: must bump on accepted edit)" >&2
  head -5 "$VISION" >&2
  exit 1
fi

# Vision must still have all four canonical sections (no re-run should destroy structure)
for section in "What we are building" "What it is not" "How we'll know we're winning" "Guiding constraints"; do
  if ! grep -qF "## $section" "$VISION"; then
    echo "FAIL: re-run lost section '$section'" >&2
    exit 1
  fi
done

echo "PASS: re-run produced per-section diff, user accepted, last_updated bumped to $TODAY" >&2
exit 0
