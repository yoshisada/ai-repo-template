#!/usr/bin/env bash
# T051 / US5 scenarios 1 + 3 — three-stream distill ingestion.
#
# FR-023: items are a third input stream.
# FR-024 + contract §7.2: derived_from order is feedback → item → issue, filename ASC within groups.
# FR-026 + contract §7.5: item state flips in-phase → distilled; prd: field patched in.

set -euo pipefail

shopt -s nullglob
prds=( docs/features/*/PRD.md )
if [[ ${#prds[@]} -eq 0 ]]; then
  echo "FAIL: no generated PRD found" >&2
  exit 1
fi
prd=$(ls -1t "${prds[@]}" | head -1)
echo "Generated PRD: $prd" >&2

feedback_fixture=".kiln/feedback/2026-04-22-0900-planning-surface-friction.md"
item_fixture=".kiln/roadmap/items/2026-04-23-structured-capture.md"
issue_fixture=".kiln/issues/2026-04-23-1200-roadmap-parse-bug.md"

# 1. All three paths must appear in the PRD frontmatter (first ~40 lines).
header=$(sed -n '1,40p' "$prd")
for path in "$feedback_fixture" "$item_fixture" "$issue_fixture"; do
  if ! grep -qF "$path" <<<"$header"; then
    echo "FAIL: PRD frontmatter missing derived_from path: $path" >&2
    echo "Header:" >&2; printf '%s\n' "$header" >&2
    exit 1
  fi
done

# 2. Order check — feedback line-number < item line-number < issue line-number in the header.
fb_line=$(grep -nF "$feedback_fixture" <<<"$header" | head -1 | cut -d: -f1)
it_line=$(grep -nF "$item_fixture"     <<<"$header" | head -1 | cut -d: -f1)
is_line=$(grep -nF "$issue_fixture"    <<<"$header" | head -1 | cut -d: -f1)

if ! [[ "$fb_line" -lt "$it_line" && "$it_line" -lt "$is_line" ]]; then
  echo "FAIL: derived_from order violates contract §7.2 (expected feedback→item→issue)" >&2
  echo "feedback line=$fb_line  item line=$it_line  issue line=$is_line" >&2
  printf '%s\n' "$header" >&2
  exit 1
fi

# 3. Item state must have flipped to distilled (FR-026).
if ! grep -qE '^state:[[:space:]]*distilled' "$item_fixture"; then
  echo "FAIL: item state did not flip to distilled" >&2
  echo "Item frontmatter:" >&2
  sed -n '1,20p' "$item_fixture" >&2
  exit 1
fi

# 4. Item must carry a prd: back-reference (contract §7.5).
if ! grep -qE '^prd:[[:space:]]*docs/features/' "$item_fixture"; then
  echo "FAIL: item missing prd: back-reference after distill" >&2
  sed -n '1,20p' "$item_fixture" >&2
  exit 1
fi

echo "PASS: three-stream distill — derived_from order correct, item state → distilled, prd: set ($prd)" >&2
exit 0
