#!/usr/bin/env bash
# T074 — FR-007. hook-claim-mismatch fires on orphan claim only.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
grep -qE 'hook-claim-mismatch' "$preview" || { echo "FAIL: hook-claim-mismatch did not fire" >&2; cat "$preview" >&2; exit 1; }
grep -qE 'correction-candidate' "$preview" || { echo "FAIL: correction-candidate action missing" >&2; exit 1; }
echo "PASS: hook-claim-mismatch fired with correction-candidate per FR-007" >&2
exit 0
