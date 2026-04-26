#!/usr/bin/env bash
# T087 — Edge Cases (vision >40 lines, no markers).
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
# Either an overlong-unmarked status line OR product-section-stale sub-signal
grep -qiE 'overlong|>[[:space:]]*40[[:space:]]*lines|claude-md-sync.*marker|markers' "$preview" \
  || { echo "FAIL: overlong-without-markers signal not surfaced" >&2; cat "$preview" >&2; exit 1; }
# MUST NOT propose mirroring the full file — line 50 should NOT appear in the diff.
if awk '/^## Proposed Diff/,/^## /' "$preview" | grep -qE 'Line 50'; then
  echo "FAIL: long file body leaked into proposed diff" >&2
  cat "$preview" >&2
  exit 1
fi
echo "PASS: vision-overlong sub-signal fired without mirroring full file per Edge Cases" >&2
exit 0
