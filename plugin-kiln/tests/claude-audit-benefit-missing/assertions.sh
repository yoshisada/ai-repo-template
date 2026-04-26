#!/usr/bin/env bash
# T072 — FR-005. benefit-missing fires only on rationale-less section.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
grep -qE 'benefit-missing' "$preview" || { echo "FAIL: benefit-missing did not fire" >&2; cat "$preview" >&2; exit 1; }
grep -qE 'expand-candidate' "$preview" || { echo "FAIL: expand-candidate action missing" >&2; exit 1; }
echo "PASS: benefit-missing fired with expand-candidate per FR-005" >&2
exit 0
