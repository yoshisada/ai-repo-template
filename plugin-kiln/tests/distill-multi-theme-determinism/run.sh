#!/usr/bin/env bash
# Test: distill-multi-theme-determinism
#
# Validates: NFR-003 (per-PRD byte-identical output on unchanged inputs) +
# SC-005 (re-running /kiln:kiln-distill against unchanged state produces
# byte-identical per-PRD output).
#
# Approach: exercise the three emitter helpers (`select-themes.sh`,
# `disambiguate-slug.sh`, `emit-run-plan.sh`) TWICE on identical inputs and
# `diff -q` the outputs byte-for-byte. Also verify the `derived_from:`
# three-group sort is deterministic by piping a known entry-set through the
# same sort pipeline the SKILL body uses.
#
# The team-lead's critical-test mandate for impl-distill-multi:
#   "You MUST add a test that runs your multi-theme emitter twice against
#    the same fixture and diffs the outputs — byte-identical is the
#    passing bar."
#
# This file is that test.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISTILL_DIR="$SCRIPT_DIR/../../scripts/distill"
SELECT="$DISTILL_DIR/select-themes.sh"
DISAMBIG="$DISTILL_DIR/disambiguate-slug.sh"
EMIT="$DISTILL_DIR/emit-run-plan.sh"

for s in "$SELECT" "$DISAMBIG" "$EMIT"; do
  if [[ ! -x "$s" ]]; then
    echo "FAIL: missing or non-executable: $s" >&2
    exit 1
  fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- Fixture: representative grouped-themes JSON ----
cat > "$TMP/themes.json" <<'EOF'
[
  {"slug":"foundation","entries":[
    {"type":"feedback","path":".kiln/feedback/2026-04-20-a.md"},
    {"type":"issue","path":".kiln/issues/2026-04-22-z.md"}
  ]},
  {"slug":"ergo","entries":[
    {"type":"feedback","path":".kiln/feedback/2026-04-21-b.md"},
    {"type":"item","path":".kiln/roadmap/items/2026-04-23-foo.md"}
  ]},
  {"slug":"cleanup","entries":[
    {"type":"issue","path":".kiln/issues/2026-04-20-x.md"}
  ]}
]
EOF

# ---- Run 1: full select + disambig + run-plan emission ----
FEATURES_A="$(mktemp -d)"
FEATURES_B="$(mktemp -d)"

run_pipeline() {
  local features="$1"
  local label="$2"
  local out_dir="$3"

  # Select themes 1 and 2 (foundation + ergo), preserving input order.
  DISTILL_SELECTION_INDICES="1,2" \
    bash "$SELECT" "$TMP/themes.json" > "$out_dir/selection-$label.json"

  # Extract selected slugs and pass to disambiguator.
  local slugs
  slugs=$(jq -r '.selected_slugs | join(" ")' "$out_dir/selection-$label.json")
  # shellcheck disable=SC2086
  DISTILL_FEATURES_DIR="$features" \
    bash "$DISAMBIG" 2026-04-24 $slugs > "$out_dir/dirs-$label.txt"

  # Emit run-plan against a fixed emissions JSON.
  cat > "$out_dir/emissions-$label.json" <<EOF2
[
  {"slug":"foundation","path":"docs/features/2026-04-24-foundation/PRD.md","severity_hint":"foundational"},
  {"slug":"ergo","path":"docs/features/2026-04-24-ergo/PRD.md","severity_hint":"med"}
]
EOF2
  bash "$EMIT" "$out_dir/emissions-$label.json" > "$out_dir/run-plan-$label.txt"
}

run_pipeline "$FEATURES_A" "A" "$TMP"
run_pipeline "$FEATURES_B" "B" "$TMP"

# ---- Byte-identical diffs ----
for suffix in selection dirs run-plan; do
  FILE_A="$TMP/${suffix}-A"
  FILE_B="$TMP/${suffix}-B"
  # Suffix variants differ by extension (json vs txt). Cover both by
  # iterating candidate extensions per basename.
  for ext in json txt; do
    if [[ -f "${FILE_A}.${ext}" ]]; then
      if ! diff -q "${FILE_A}.${ext}" "${FILE_B}.${ext}" >/dev/null; then
        echo "FAIL: non-deterministic output for ${suffix}.${ext}" >&2
        diff "${FILE_A}.${ext}" "${FILE_B}.${ext}" | head -40 >&2
        exit 1
      fi
    fi
  done
done

# ---- Derived-from three-group sort determinism (FR-020 / NFR-003) ----
# Simulate the sort the SKILL body performs on a bundle of selected entries.
# Three groups: feedback / item / issue, filename ASC within each. Run twice
# and diff.
cat > "$TMP/entries.txt" <<'EOF'
feedback|.kiln/feedback/2026-04-22-zz.md
issue|.kiln/issues/2026-04-21-mm.md
feedback|.kiln/feedback/2026-04-20-aa.md
item|.kiln/roadmap/items/2026-04-23-bb.md
issue|.kiln/issues/2026-04-20-xx.md
item|.kiln/roadmap/items/2026-04-21-aa.md
EOF

sort_derived_from() {
  # Three-group ASC sort: feedback → item → issue, filename ASC within each.
  {
    grep '^feedback|' "$1" | LC_ALL=C sort
    grep '^item|'     "$1" | LC_ALL=C sort
    grep '^issue|'    "$1" | LC_ALL=C sort
  } | cut -d'|' -f2
}

sort_derived_from "$TMP/entries.txt" > "$TMP/sorted-A.txt"
sort_derived_from "$TMP/entries.txt" > "$TMP/sorted-B.txt"

if ! diff -q "$TMP/sorted-A.txt" "$TMP/sorted-B.txt" >/dev/null; then
  echo "FAIL: three-group sort not deterministic" >&2
  exit 1
fi

# Validate the actual sort order.
EXPECTED_SORT=".kiln/feedback/2026-04-20-aa.md
.kiln/feedback/2026-04-22-zz.md
.kiln/roadmap/items/2026-04-21-aa.md
.kiln/roadmap/items/2026-04-23-bb.md
.kiln/issues/2026-04-20-xx.md
.kiln/issues/2026-04-21-mm.md"

if [[ "$(cat "$TMP/sorted-A.txt")" != "$EXPECTED_SORT" ]]; then
  echo "FAIL: three-group sort order incorrect." >&2
  echo "Expected:" >&2; echo "$EXPECTED_SORT" >&2
  echo "Got:"      >&2; cat "$TMP/sorted-A.txt" >&2
  exit 1
fi

echo "PASS: helpers + derived_from three-group sort are byte-identical on re-run (NFR-003)"
