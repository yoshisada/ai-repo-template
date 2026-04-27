#!/usr/bin/env bash
# vision-alignment-render.sh — render the 3-section alignment report.
#
# FR-008 / FR-009 / vision-tooling FR-008/FR-009: report-only — never mutates
# anything. Three sections in fixed order: Aligned / Multi-aligned / Drifters.
# Caveat header from FR-007 is emitted verbatim.
#
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme B —
#           vision-alignment-render.sh"
#
# Usage:
#   <something> | vision-alignment-render.sh
#
# Stdin (when not a tty): one line per item, format
#   <item-path>\t<pillar-1>,<pillar-2>,...
# Empty pillar list = Drifter.
#
# Stdout: full report with three sections in fixed order. `(none)` body for
#         empty sections.
# Exit:   0 always.
# Side-effects: none.
set -u
LC_ALL=C
export LC_ALL

CAVEAT="Mappings are LLM-inferred; re-runs on unchanged inputs may differ. For deterministic mapping, declare addresses_pillar: explicitly per item (V2 schema extension)."

# Read stdin if not a tty. If stdin IS a tty, the caller has not piped anything
# and we emit an empty-state report (all three sections show "(none)").
if [ -t 0 ]; then
  INPUT=""
else
  INPUT=$(cat)
fi

# Parse each line into <item-id>\t<pillars-csv>. The item-id is the basename
# without .md. Empty pillar field = Drifter.
ALIGNED=""        # <item-id>\t<pillar> — one per item-pillar pair
MULTI=""          # <item-id>\t<csv> — items with ≥2 pillars
DRIFTERS=""       # <item-id> — items with zero pillars

if [ -n "$INPUT" ]; then
  while IFS=$'\t' read -r item_path pillars_csv; do
    [ -z "$item_path" ] && continue
    item_id=$(basename "$item_path" .md)
    if [ -z "${pillars_csv:-}" ]; then
      DRIFTERS="${DRIFTERS}${item_id}
"
      continue
    fi
    # Count pillars (comma-separated).
    pillar_count=$(printf '%s' "$pillars_csv" | awk -F, '{print NF}')
    if [ "$pillar_count" -ge 2 ]; then
      MULTI="${MULTI}${item_id}	${pillars_csv}
"
    fi
    # ALL items with ≥1 pillar contribute to Aligned (one line per pair).
    # Multi-aligned items also appear in Aligned per FR-008(a) — "one line per
    # item-pillar pair; an item with N pillars produces N lines".
    IFS=',' read -ra _arr <<<"$pillars_csv"
    for p in "${_arr[@]}"; do
      p_trim=$(printf '%s' "$p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [ -z "$p_trim" ] && continue
      ALIGNED="${ALIGNED}${item_id}	${p_trim}
"
    done
  done <<<"$INPUT"
fi

# Helper: emit a section. $1 = header, $2 = body string. Empty body → "(none)".
emit_section() {
  local hdr="$1" body="$2"
  printf '## %s\n\n' "$hdr"
  if [ -z "$body" ]; then
    printf '(none)\n\n'
    return 0
  fi
  # Sort by item-id ASC (the item-id is the leading field on each line).
  printf '%s' "$body" | LC_ALL=C sort | awk 'NF { print }' | while IFS=$'\t' read -r itm rest; do
    if [ -n "${rest:-}" ]; then
      printf '%s → %s\n' "$itm" "$rest"
    else
      printf '%s\n' "$itm"
    fi
  done
  printf '\n'
}

# ---- Render ----
printf '%s\n\n' "$CAVEAT"
emit_section "Aligned items"        "$ALIGNED"
emit_section "Multi-aligned items"  "$MULTI"
emit_section "Drifters"             "$DRIFTERS"
