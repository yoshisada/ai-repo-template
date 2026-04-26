#!/usr/bin/env bash
# T076 — FR-017 exclude_section_from_classification.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
# enumeration-bloat MUST NOT fire on the excluded section. We accept the rule_id
# appearing in a "did not fire / suppressed" context, but a fired removal-candidate
# row pointing at "## Available Commands" would be a regression.
if grep -E 'enumeration-bloat' "$preview" | grep -qiE 'available commands.*removal-candidate|removal-candidate.*available commands'; then
  echo "FAIL: enumeration-bloat fired on excluded section" >&2
  cat "$preview" >&2
  exit 1
fi
echo "PASS: exclude_section_from_classification suppressed enumeration-bloat per FR-017" >&2
exit 0
