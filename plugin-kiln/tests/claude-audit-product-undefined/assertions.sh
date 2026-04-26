#!/usr/bin/env bash
# T079 — FR-025 / SC-007. product-undefined fires + row 1 in Signal Summary.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
grep -qE 'product-undefined' "$preview" || { echo "FAIL: product-undefined did not fire" >&2; cat "$preview" >&2; exit 1; }
# SC-007: row 1 of Signal Summary MUST be product-undefined. Find the table,
# read the first data row after the header separator, assert it contains product-undefined.
awk '/^## Signal Summary/{in_t=1; next} in_t && /^\|---/{after_sep=1; next} after_sep && /^\|/{print; exit}' "$preview" | grep -qE 'product-undefined' \
  || { echo "FAIL: product-undefined not at row 1 of Signal Summary (SC-007)" >&2; cat "$preview" >&2; exit 1; }
echo "PASS: product-undefined fired AND appears at row 1 per SC-007" >&2
exit 0
