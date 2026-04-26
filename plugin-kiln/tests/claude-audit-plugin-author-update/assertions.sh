#!/usr/bin/env bash
# T088 — US6 AC#1.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
# A diff MUST be proposed touching kiln. The shelf subsection MUST NOT be modified.
grep -qE 'kiln' "$preview" || { echo "FAIL: kiln update not surfaced" >&2; cat "$preview" >&2; exit 1; }
# In Proposed Diff, no removal lines should target shelf's content.
if awk '/^## Proposed Diff/,/^## /' "$preview" | grep -qE '^\-.*shelf-sync|^\-.*Reach for shelf'; then
  echo "FAIL: shelf subsection touched (should be untouched)" >&2
  cat "$preview" >&2
  exit 1
fi
echo "PASS: only ### kiln subsection swap proposed per US6 AC#1" >&2
exit 0
