#!/usr/bin/env bash
# T084 — FR-013 / SC-005. Silent skip on missing guidance file.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
# No FAIL signal should be emitted for missing guidance — but the Plugins Sync
# section may legitimately list "Plugins skipped (no guidance file): kiln".
# What MUST NOT appear: a fired SIGNAL about the missing file (no row in Signal Summary).
if awk '/^## Signal Summary/,/^## /' "$preview" | grep -qiE 'guidance.*missing|missing.*guidance.*kiln'; then
  echo "FAIL: signal fired for missing guidance — should be silent (FR-013 / SC-005)" >&2
  cat "$preview" >&2
  exit 1
fi
echo "PASS: missing guidance file skipped silently per FR-013 / SC-005" >&2
exit 0
