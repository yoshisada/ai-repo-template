#!/usr/bin/env bash
# T056 — /specify hook flips item state: distilled → specced + patches spec: field.
# FR-034 / contract §9.

set -euo pipefail

item=".kiln/roadmap/items/2026-04-23-cache-embeddings.md"

if [[ ! -f "$item" ]]; then
  echo "FAIL: fixture item missing after specify run" >&2
  exit 1
fi

# 1. state must be specced (was distilled before specify).
if ! grep -qE '^state:[[:space:]]*specced' "$item"; then
  echo "FAIL: item state did not flip distilled → specced" >&2
  sed -n '1,20p' "$item" >&2
  exit 1
fi

# 2. spec: field must be set and point at a specs/ path.
if ! grep -qE '^spec:[[:space:]]*specs/' "$item"; then
  echo "FAIL: item missing spec: field pointing at specs/..." >&2
  sed -n '1,20p' "$item" >&2
  exit 1
fi

# 3. prd: field must still be intact (hook must not clobber).
if ! grep -qE '^prd:[[:space:]]*docs/features/' "$item"; then
  echo "FAIL: item prd: field was clobbered by specify hook" >&2
  sed -n '1,20p' "$item" >&2
  exit 1
fi

echo "PASS: specify hook flipped state specced + patched spec: field ($item)" >&2
exit 0
