#!/usr/bin/env bash
# T081 — FR-026 product-slot-missing.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
grep -qE 'product-slot-missing' "$preview" || { echo "FAIL: product-slot-missing did not fire" >&2; cat "$preview" >&2; exit 1; }
grep -qE 'Vision\.md Coverage' "$preview" || { echo "FAIL: Vision.md Coverage sub-section not rendered" >&2; cat "$preview" >&2; exit 1; }
echo "PASS: product-slot-missing fired + rendered under Vision.md Coverage per FR-026" >&2
exit 0
