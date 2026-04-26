#!/usr/bin/env bash
# T071 — FR-002. Validates plugin-surface section flagged with removal-candidate.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
grep -qE 'enumeration-bloat' "$preview" || { echo "FAIL: enumeration-bloat did not fire" >&2; cat "$preview" >&2; exit 1; }
grep -qE 'removal-candidate' "$preview" || { echo "FAIL: action removal-candidate not surfaced" >&2; exit 1; }
grep -qiE 'runtime context|available skills.*agents.*commands' "$preview" || { echo "FAIL: rationale text missing" >&2; exit 1; }
echo "PASS: enumeration-bloat fired with removal-candidate + correct rationale" >&2
exit 0
