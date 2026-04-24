#!/usr/bin/env bash
# T053 — --kind research bundles only research items.
# FR-025 / PRD FR-025.

set -euo pipefail
shopt -s nullglob
prds=( docs/features/*/PRD.md )
if [[ ${#prds[@]} -eq 0 ]]; then
  echo "FAIL: no generated PRD found" >&2
  exit 1
fi
prd=$(ls -1t "${prds[@]}" | head -1)
header=$(sed -n '1,40p' "$prd")

research_item=".kiln/roadmap/items/2026-04-23-spike-embedding-store.md"
feature_item=".kiln/roadmap/items/2026-04-23-oauth-flow.md"

if ! grep -qF "$research_item" <<<"$header"; then
  echo "FAIL: PRD missing the research item the filter should have selected" >&2
  printf '%s\n' "$header" >&2
  exit 1
fi
if grep -qF "$feature_item" <<<"$header"; then
  echo "FAIL: --kind research filter leaked a feature item into the PRD" >&2
  printf '%s\n' "$header" >&2
  exit 1
fi

echo "PASS: --kind research selected only research item ($prd)" >&2
exit 0
