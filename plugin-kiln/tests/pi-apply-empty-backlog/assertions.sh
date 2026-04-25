#!/usr/bin/env bash
# T028 — pi-apply-empty-backlog assertions.
# Validates: zero open retro issues → schema-stable "No open retro issues found" report.
set -euo pipefail

shopt -s nullglob
reports=( .kiln/logs/pi-apply-*.md )
[[ ${#reports[@]} -gt 0 ]] || { echo "FAIL: no report written" >&2; exit 1; }
report=$(ls -1t "${reports[@]}" | head -1)

if ! grep -qF 'No open retro issues found' "$report"; then
  echo "FAIL: empty-backlog report must include the literal 'No open retro issues found' line" >&2
  cat "$report" >&2
  exit 1
fi

# All four sections must still render (schema stability).
for section in '## Actionable PIs' '## Already-Applied PIs' '## Stale PIs (anchor not found)' '## Parse Errors'; do
  grep -qF "$section" "$report" || { echo "FAIL: section '$section' missing from empty-backlog report" >&2; exit 1; }
done

echo "PASS: empty backlog → schema-stable report with 'No open retro issues found'" >&2
exit 0
