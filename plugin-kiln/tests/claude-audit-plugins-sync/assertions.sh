#!/usr/bin/env bash
# T082 — FR-014/FR-015. ## Plugins section proposed when absent + alphabetical.
set -euo pipefail
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
[[ ${#previews[@]} -gt 0 ]] || { echo "FAIL: no preview log" >&2; exit 1; }
preview=$(ls -1t "${previews[@]}" | head -1)
grep -qE 'Plugins Sync' "$preview" || { echo "FAIL: ## Plugins Sync section missing" >&2; cat "$preview" >&2; exit 1; }
# Either an insert proposal or section in sync — but the kiln + shelf names MUST be visible
grep -qE 'kiln' "$preview" && grep -qE 'shelf' "$preview" || { echo "FAIL: kiln + shelf not enumerated" >&2; cat "$preview" >&2; exit 1; }
# Alphabetical ordering verification — kiln MUST appear before shelf in the Plugins Sync block
awk '/^## Plugins Sync/,/^## /' "$preview" | awk '/^### kiln|^### shelf/' | head -2 | tr '\n' ' ' | grep -qE 'kiln.*shelf' \
  || { echo "FAIL: plugin order not alphabetical (kiln before shelf)" >&2; cat "$preview" >&2; exit 1; }
echo "PASS: plugins-sync produced ## Plugins Sync with alphabetical kiln+shelf per FR-014/FR-015" >&2
exit 0
