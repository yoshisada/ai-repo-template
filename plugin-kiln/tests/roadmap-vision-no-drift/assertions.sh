#!/usr/bin/env bash
# Assertions for roadmap-vision-no-drift (T022).
# Validates FR-010 negative path: zero accepted edits → last_updated NOT bumped.
# Edge case from spec.md: "Vision re-run on unchanged repo state".
set -euo pipefail

VISION=".kiln/vision.md"
if [[ ! -f "$VISION" ]]; then
  echo "FAIL: $VISION was deleted (skill must never delete on no-drift)" >&2
  exit 1
fi

# last_updated must STILL be the fixture value 2026-04-24
FRONT_DATE=$(awk '/^last_updated:/ { print $2; exit }' "$VISION")
if [[ "$FRONT_DATE" != "2026-04-24" ]]; then
  echo "FAIL: last_updated was bumped from 2026-04-24 to '$FRONT_DATE' despite no accepted edits (FR-010 violation)" >&2
  head -5 "$VISION" >&2
  exit 1
fi

echo "PASS: no-drift run preserved last_updated: 2026-04-24" >&2
exit 0
