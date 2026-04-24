#!/usr/bin/env bash
# T054 — implementation_hints flow into ## Implementation Hints with item-id back-reference.
# FR-027 / PRD FR-027.

set -euo pipefail
shopt -s nullglob
prds=( docs/features/*/PRD.md )
if [[ ${#prds[@]} -eq 0 ]]; then
  echo "FAIL: no generated PRD found" >&2
  exit 1
fi
prd=$(ls -1t "${prds[@]}" | head -1)

# 1. Must have ## Implementation Hints section.
if ! grep -qE '^##[[:space:]]+Implementation Hints[[:space:]]*$' "$prd"; then
  echo "FAIL: PRD missing '## Implementation Hints' section" >&2
  head -120 "$prd" >&2
  exit 1
fi

# 2. Verbatim hint content must appear.
if ! grep -qF "content-addressed cache" "$prd"; then
  echo "FAIL: PRD does not render the item's implementation_hints verbatim" >&2
  head -120 "$prd" >&2
  exit 1
fi

# 3. Back-reference to item id.
if ! grep -qF "2026-04-23-cache-embeddings" "$prd"; then
  echo "FAIL: PRD missing item-id back-reference in Implementation Hints" >&2
  head -120 "$prd" >&2
  exit 1
fi

echo "PASS: ## Implementation Hints rendered with item back-reference ($prd)" >&2
exit 0
