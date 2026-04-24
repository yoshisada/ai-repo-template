#!/usr/bin/env bash
# FR-029 — three seed critiques; each has a non-empty proof_path (FR-011).
set -euo pipefail

ITEMS_DIR=".kiln/roadmap/items"

for stem in too-many-tokens unauditable-buggy-code too-much-setup; do
  matches=( "$ITEMS_DIR"/*-"$stem".md )
  if [ "${#matches[@]}" -ne 1 ] || [ ! -f "${matches[0]}" ]; then
    echo "FAIL: seed critique missing for stem '$stem'" >&2
    ls "$ITEMS_DIR" >&2 || true
    exit 1
  fi
  f="${matches[0]}"
  grep -qE '^kind:[[:space:]]*critique$' "$f" || { echo "FAIL: $f not kind:critique" >&2; exit 1; }
  # proof_path is a YAML block scalar — the key must appear
  grep -qE '^proof_path:' "$f" || { echo "FAIL: $f missing proof_path (FR-011)" >&2; exit 1; }
  # proof_path body must have at least one non-blank line after the `|`
  if ! awk '
    /^proof_path:[[:space:]]*\|/ { in_blk=1; next }
    in_blk==1 && /^[A-Za-z_]+:[[:space:]]*/ { exit found?0:1 }
    in_blk==1 && /^---[[:space:]]*$/ { exit found?0:1 }
    in_blk==1 && /^[[:space:]]+[^[:space:]]/ { found=1 }
    END { exit found?0:1 }
  ' "$f"; then
    echo "FAIL: $f proof_path block is empty" >&2
    exit 1
  fi
done

echo "PASS: three seed critiques present with non-empty proof_path" >&2
exit 0
