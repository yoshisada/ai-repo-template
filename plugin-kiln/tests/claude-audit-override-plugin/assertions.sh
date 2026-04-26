#!/usr/bin/env bash
# T077 — FR-017 exclude_plugin_from_sync.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
# Either an explicit "Excluded by override" line names trim, or the Plugins Sync
# section omits trim from the built body.
if ! grep -qiE 'excluded.*trim|exclude_plugin_from_sync' "$preview"; then
  echo "FAIL: trim exclusion not surfaced in Plugins Sync output" >&2
  cat "$preview" >&2
  exit 1
fi
echo "PASS: exclude_plugin_from_sync surfaced per FR-017" >&2
exit 0
