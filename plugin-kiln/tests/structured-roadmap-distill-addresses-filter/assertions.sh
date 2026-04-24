#!/usr/bin/env bash
# T052 — --addresses filter bundles only items whose addresses[] references the critique.
# FR-025 / PRD FR-025.

set -euo pipefail

shopt -s nullglob
prds=( docs/features/*/PRD.md )
if [[ ${#prds[@]} -eq 0 ]]; then
  echo "FAIL: no generated PRD found" >&2
  exit 1
fi
prd=$(ls -1t "${prds[@]}" | head -1)
header=$(sed -n '1,50p' "$prd")

related_a=".kiln/roadmap/items/2026-04-23-trim-prd-tokens.md"
related_b=".kiln/roadmap/items/2026-04-23-share-embeddings.md"
unrelated=".kiln/roadmap/items/2026-04-23-unrelated-feature.md"

# Both related items MUST appear.
for path in "$related_a" "$related_b"; do
  if ! grep -qF "$path" <<<"$header"; then
    echo "FAIL: PRD missing item that addresses the critique: $path" >&2
    printf '%s\n' "$header" >&2
    exit 1
  fi
done

# Unrelated item MUST NOT appear in the derived_from: block.
if grep -qF "$unrelated" <<<"$header"; then
  echo "FAIL: PRD included the unrelated item — --addresses filter leaked" >&2
  printf '%s\n' "$header" >&2
  exit 1
fi

echo "PASS: --addresses filter correctly bundled only addressing items ($prd)" >&2
exit 0
