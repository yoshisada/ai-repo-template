#!/usr/bin/env bash
# T080 — FR-027 product-section-stale.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
grep -qE 'product-section-stale' "$preview" || { echo "FAIL: product-section-stale did not fire" >&2; cat "$preview" >&2; exit 1; }
grep -qE 'sync-candidate' "$preview" || { echo "FAIL: sync-candidate action missing" >&2; exit 1; }
echo "PASS: product-section-stale fired with sync-candidate per FR-027" >&2
exit 0
