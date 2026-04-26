#!/usr/bin/env bash
# T073 — FR-006. loop-incomplete fires when capture-surface populated but no /kiln:kiln-distill mention.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
grep -qE 'loop-incomplete' "$preview" || { echo "FAIL: loop-incomplete did not fire" >&2; cat "$preview" >&2; exit 1; }
echo "PASS: loop-incomplete fired per FR-006" >&2
exit 0
