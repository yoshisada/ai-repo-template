#!/usr/bin/env bash
# T083 — FR-015 disabled plugin subsection removed only.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
# Proposed Diff MUST reference removing the ### trim subsection.
grep -qE 'trim' "$preview" || { echo "FAIL: trim removal not surfaced" >&2; cat "$preview" >&2; exit 1; }
# kiln + shelf MUST NOT be proposed for removal.
if awk '/^## Proposed Diff/,/^## /' "$preview" | grep -qE '^\-.*### kiln|^\-.*### shelf'; then
  echo "FAIL: enabled plugins kiln/shelf proposed for removal" >&2
  cat "$preview" >&2
  exit 1
fi
echo "PASS: only disabled plugin (trim) subsection proposed for removal per FR-015 / US1 AC#2" >&2
exit 0
