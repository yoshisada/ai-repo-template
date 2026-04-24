#!/usr/bin/env bash
# US2 — critique capture: kind:critique, proof_path non-empty, status:open.
# FR-011 / PRD FR-011.
set -euo pipefail

ITEMS_DIR=".kiln/roadmap/items"

# Find the user-captured critique — its title contains "too many tokens" or similar.
# Seed critiques are also critiques but their ids end in -too-many-tokens etc.
# The user's new item will be today's date and a slug derived from the description.
shopt -s nullglob
user_critique=""
for f in "$ITEMS_DIR"/*.md; do
  if grep -qE '^kind:[[:space:]]*critique$' "$f" \
     && grep -qE '^status:[[:space:]]*open$' "$f"; then
    # Exclude seed critiques by stable id suffix
    b=$(basename "$f" .md)
    case "$b" in
      2026-04-24-too-many-tokens|2026-04-24-unauditable-buggy-code|2026-04-24-too-much-setup) continue ;;
    esac
    # Must have non-empty proof_path
    if grep -qE '^proof_path:' "$f"; then
      user_critique="$f"
      break
    fi
  fi
done

if [ -z "$user_critique" ]; then
  echo "FAIL: no user-captured critique found (with proof_path) — FR-011 broken" >&2
  ls "$ITEMS_DIR" >&2
  exit 1
fi

# Verify required frontmatter
grep -qE '^kind:[[:space:]]*critique$'  "$user_critique" || { echo "FAIL: kind != critique" >&2; exit 1; }
grep -qE '^status:[[:space:]]*open$'    "$user_critique" || { echo "FAIL: status != open" >&2; exit 1; }
grep -qE '^proof_path:'                 "$user_critique" || { echo "FAIL: missing proof_path (FR-011)" >&2; exit 1; }

# proof_path body must be non-empty
if ! awk '
    /^proof_path:[[:space:]]*\|/ { in_blk=1; next }
    /^proof_path:[[:space:]]*[^|[:space:]]/ { print "scalar"; exit }
    in_blk==1 && /^[A-Za-z_]+:[[:space:]]*/ { exit found?0:1 }
    in_blk==1 && /^---[[:space:]]*$/ { exit found?0:1 }
    in_blk==1 && /^[[:space:]]+[^[:space:]]/ { found=1 }
    END { exit found?0:1 }
  ' "$user_critique" >/dev/null; then
  echo "FAIL: proof_path appears empty — FR-011 re-prompt loop didn't work" >&2
  cat "$user_critique" >&2
  exit 1
fi

echo "PASS: user critique captured with non-empty proof_path → $user_critique" >&2
exit 0
