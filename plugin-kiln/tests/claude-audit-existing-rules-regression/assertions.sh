#!/usr/bin/env bash
# T075 — SC-010. Pre-existing rules continue to fire after reframe.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
grep -qE 'recent-changes-overflow' "$preview" || { echo "FAIL: recent-changes-overflow regression" >&2; cat "$preview" >&2; exit 1; }
echo "PASS: existing rules continue to fire — no regression per SC-010" >&2
exit 0
