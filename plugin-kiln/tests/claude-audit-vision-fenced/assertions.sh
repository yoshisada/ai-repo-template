#!/usr/bin/env bash
# T086 — FR-023 fenced region.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
# Vision Sync MUST mention "fenced" mode.
grep -qiE 'fenced' "$preview" || { echo "FAIL: fenced region not detected" >&2; cat "$preview" >&2; exit 1; }
# Content outside markers ("internal note") MUST NOT appear in the Proposed Diff.
if awk '/^## Proposed Diff/,/^## /' "$preview" | grep -qE 'internal note'; then
  echo "FAIL: content outside fenced markers leaked into proposed diff" >&2
  cat "$preview" >&2
  exit 1
fi
echo "PASS: vision-fenced region honored per FR-023" >&2
exit 0
