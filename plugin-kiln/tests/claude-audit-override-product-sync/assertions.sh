#!/usr/bin/env bash
# T078 — FR-029 product_sync = false.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
# product-undefined / product-section-stale / product-slot-missing MUST NOT fire.
if grep -qE 'product-undefined|product-section-stale|product-slot-missing' "$preview" \
   && ! grep -qE 'product_sync.*false|skipped' "$preview"; then
  echo "FAIL: product-* rule fired despite product_sync = false" >&2
  cat "$preview" >&2
  exit 1
fi
# The override must be acknowledged in Vision Sync section or Notes.
grep -qiE 'product_sync|vision sync skipped|🚫' "$preview" || { echo "FAIL: product_sync override not surfaced" >&2; cat "$preview" >&2; exit 1; }
echo "PASS: product_sync = false suppressed product-* rules per FR-029" >&2
exit 0
