#!/usr/bin/env bash
# Test: vision-alignment-check (Theme B, T012)
#
# Validates: SC-003 (3 sections in order, caveat header verbatim, sort ASC,
# empty git diff post-run), FR-006 (shipped items excluded), FR-008
# (Multi-aligned section populated when fixture has dual-pillar item),
# FR-009 (no file mutation).
#
# Substrate: PURE-SHELL UNIT FIXTURE — invoked via `bash run.sh`. Cannot be
# discovered by /kiln:kiln-test (substrate gap B-1 in PRs #166/#168). Cite
# exit code + last-line PASS + assertion count when reporting.
set -uo pipefail
LC_ALL=C
export LC_ALL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WALK="$REPO_ROOT/plugin-kiln/scripts/roadmap/vision-alignment-walk.sh"
MAP="$REPO_ROOT/plugin-kiln/scripts/roadmap/vision-alignment-map.sh"
RENDER="$REPO_ROOT/plugin-kiln/scripts/roadmap/vision-alignment-render.sh"

CAVEAT="Mappings are LLM-inferred; re-runs on unchanged inputs may differ. For deterministic mapping, declare addresses_pillar: explicitly per item (V2 schema extension)."

PASS_COUNT=0
FAIL_COUNT=0

assert() {
  local desc="$1" cond_rc="$2"
  if [ "$cond_rc" = "0" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  PASS [$PASS_COUNT]: $desc"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "  FAIL [$FAIL_COUNT]: $desc" >&2
  fi
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
mkdir -p .kiln/roadmap/items/declined

# ---- Seed fixture vision.md with two pillars ----
cat > .kiln/vision.md <<'EOF'
---
last_updated: 2026-04-25
---

# Vision

## Guiding constraints

- **Context-informed autonomy** — deliberate over precedent before acting.
- **Plugin-workflow portability** — scripts resolve via WORKFLOW_PLUGIN_DIR.
EOF

# ---- Seed open items: aligned, multi-aligned, drifter, shipped (excluded) ----
cat > .kiln/roadmap/items/2026-04-24-aligned-item.md <<'EOF'
---
title: "Aligned item"
state: in-phase
status: planned
kind: feature
---

This item is about context-informed autonomy improvements.
EOF

cat > .kiln/roadmap/items/2026-04-24-multi-item.md <<'EOF'
---
title: "Multi item"
state: in-phase
status: planned
kind: feature
---

This item touches both autonomy and portability concerns.
EOF

cat > .kiln/roadmap/items/2026-04-24-drifter-item.md <<'EOF'
---
title: "Drifter item"
state: in-phase
status: planned
kind: feature
---

This item is unrelated to any pillar.
EOF

cat > .kiln/roadmap/items/2026-04-24-shipped-item.md <<'EOF'
---
title: "Shipped item"
state: shipped
status: shipped
kind: feature
---

Already shipped — should be excluded.
EOF

# ---- Mock-LLM dir: one .txt per item ----
MOCK="$TMP/mock-llm"
mkdir -p "$MOCK"
printf 'context-informed-autonomy\n'                              > "$MOCK/2026-04-24-aligned-item.txt"
printf 'context-informed-autonomy\nplugin-workflow-portability\n' > "$MOCK/2026-04-24-multi-item.txt"
:                                                                  > "$MOCK/2026-04-24-drifter-item.txt"
# (No fixture for shipped → it should be excluded by the walker, not even mapped.)

export KILN_TEST_MOCK_LLM_DIR="$MOCK"

# ---- snapshot for "no mutation" assertion ----
SNAP_BEFORE=$(find .kiln -type f -exec shasum -a 256 {} \; | LC_ALL=C sort)

# ---- T013: walker filters shipped ----
WALK_OUT=$(bash "$WALK")
assert "FR-006: walker excludes status:shipped + state:shipped items" \
  "$([ -z "$(echo "$WALK_OUT" | grep -F shipped-item)" ] && echo 0 || echo 1)"

# Walker should emit 3 lines (aligned, drifter, multi).
WALK_LINES=$(printf '%s\n' "$WALK_OUT" | awk 'NF' | wc -l | tr -d ' ')
assert "FR-006: walker emits 3 open items (excluding shipped)" \
  "$([ "$WALK_LINES" = "3" ] && echo 0 || echo 1)"

# Walker output is sorted ASC.
WALK_SORTED=$(printf '%s\n' "$WALK_OUT" | LC_ALL=C sort)
assert "FR-006: walker output sorted ASC" \
  "$([ "$WALK_OUT" = "$WALK_SORTED" ] && echo 0 || echo 1)"

# ---- T014: per-item mapping (mock) ----
MAP_ALIGNED=$(bash "$MAP" .kiln/roadmap/items/2026-04-24-aligned-item.md)
assert "FR-007: aligned item maps to one pillar via mock" \
  "$([ "$MAP_ALIGNED" = "context-informed-autonomy" ] && echo 0 || echo 1)"

MAP_MULTI=$(bash "$MAP" .kiln/roadmap/items/2026-04-24-multi-item.md)
MAP_MULTI_LINES=$(printf '%s\n' "$MAP_MULTI" | awk 'NF' | wc -l | tr -d ' ')
assert "FR-007: multi-aligned item maps to two pillars" \
  "$([ "$MAP_MULTI_LINES" = "2" ] && echo 0 || echo 1)"

MAP_DRIFTER=$(bash "$MAP" .kiln/roadmap/items/2026-04-24-drifter-item.md)
assert "FR-007: drifter item maps to zero pillars (empty stdout)" \
  "$([ -z "$MAP_DRIFTER" ] && echo 0 || echo 1)"

# ---- T015: end-to-end render ----
INPUT_FILE="$TMP/render-input.tsv"
: > "$INPUT_FILE"
while IFS= read -r p; do
  [ -z "$p" ] && continue
  pillars=$(bash "$MAP" "$p" | awk 'NF' | tr '\n' ',' | sed 's/,$//')
  printf '%s\t%s\n' "$p" "$pillars" >> "$INPUT_FILE"
done <<<"$WALK_OUT"

REPORT=$(bash "$RENDER" < "$INPUT_FILE")

# Caveat header verbatim, present on the first non-empty line of the report.
FIRST_LINE=$(printf '%s\n' "$REPORT" | awk 'NF { print; exit }')
assert "SC-003: caveat header emitted verbatim on first non-empty line" \
  "$([ "$FIRST_LINE" = "$CAVEAT" ] && echo 0 || echo 1)"

# Three sections in fixed order: Aligned → Multi-aligned → Drifters.
SEC_ALIGNED_LINE=$(printf '%s\n' "$REPORT" | grep -nF '## Aligned items' | head -1 | cut -d: -f1)
SEC_MULTI_LINE=$(printf '%s\n' "$REPORT" | grep -nF '## Multi-aligned items' | head -1 | cut -d: -f1)
SEC_DRIFT_LINE=$(printf '%s\n' "$REPORT" | grep -nF '## Drifters' | head -1 | cut -d: -f1)
ORDER_OK=0
if [ -n "$SEC_ALIGNED_LINE" ] && [ -n "$SEC_MULTI_LINE" ] && [ -n "$SEC_DRIFT_LINE" ]; then
  if [ "$SEC_ALIGNED_LINE" -lt "$SEC_MULTI_LINE" ] && [ "$SEC_MULTI_LINE" -lt "$SEC_DRIFT_LINE" ]; then
    ORDER_OK=0
  else
    ORDER_OK=1
  fi
else
  ORDER_OK=1
fi
assert "SC-003: three sections appear in fixed order (Aligned → Multi → Drifters)" "$ORDER_OK"

# FR-008: Multi-aligned section is populated when a dual-pillar fixture exists.
MULTI_BODY=$(printf '%s\n' "$REPORT" | awk '/^## Multi-aligned items$/,/^## Drifters$/' | grep -F 'multi-item' || true)
assert "FR-008: Multi-aligned section populated for the dual-pillar item" \
  "$([ -n "$MULTI_BODY" ] && echo 0 || echo 1)"

# Aligned section contains both the aligned + multi item-pillar pairs (multi appears with both pillars).
ALIGNED_BODY=$(printf '%s\n' "$REPORT" | awk '/^## Aligned items$/,/^## Multi-aligned items$/')
ALIGNED_HAS_ALIGNED=$(printf '%s\n' "$ALIGNED_BODY" | grep -c 'aligned-item' || true)
ALIGNED_HAS_MULTI=$(printf '%s\n' "$ALIGNED_BODY" | grep -c 'multi-item' || true)
assert "FR-008(a): Aligned section emits one line per item-pillar pair (multi appears 2×)" \
  "$([ "$ALIGNED_HAS_MULTI" -eq 2 ] && [ "$ALIGNED_HAS_ALIGNED" -eq 1 ] && echo 0 || echo 1)"

# Drifters section contains the drifter.
DRIFTER_BODY=$(printf '%s\n' "$REPORT" | awk '/^## Drifters$/,EOF { print }')
assert "FR-008(c): Drifters section lists the zero-pillar item" \
  "$(printf '%s\n' "$DRIFTER_BODY" | grep -qF 'drifter-item' && echo 0 || echo 1)"

# ---- FR-009: no file mutation ----
SNAP_AFTER=$(find .kiln -type f -exec shasum -a 256 {} \; | LC_ALL=C sort)
assert "FR-009: no file mutation across walk + map + render" \
  "$([ "$SNAP_BEFORE" = "$SNAP_AFTER" ] && echo 0 || echo 1)"

# ---- Empty-state behavior: render with empty input still emits 3 sections + (none) ----
EMPTY_REPORT=$(printf '' | bash "$RENDER")
EMPTY_NONE_COUNT=$(printf '%s\n' "$EMPTY_REPORT" | grep -c '^(none)$' || true)
assert "Edge case: empty input → 3 sections each with body '(none)'" \
  "$([ "$EMPTY_NONE_COUNT" = "3" ] && echo 0 || echo 1)"

# ---- Summary ----
echo
echo "PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "FAIL: vision-alignment-check"
  exit 1
fi
echo "PASS: vision-alignment-check ($PASS_COUNT assertions)"
exit 0
