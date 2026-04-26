#!/usr/bin/env bash
# T085 — FR-022/FR-023/FR-028.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
grep -qE 'Vision Sync' "$preview" || { echo "FAIL: ## Vision Sync section missing" >&2; cat "$preview" >&2; exit 1; }
# Either insert proposed for ## Product OR vision content surfaced in Proposed Diff.
grep -qE '## Product|insert.*Product|product-section-stale|product-undefined' "$preview" \
  || { echo "FAIL: Product section sync not proposed" >&2; cat "$preview" >&2; exit 1; }
echo "PASS: vision → ## Product sync proposed per FR-022/FR-023/FR-028" >&2
exit 0
