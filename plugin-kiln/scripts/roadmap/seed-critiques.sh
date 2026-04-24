#!/usr/bin/env bash
# seed-critiques.sh — bootstrap three named critique files
#
# FR-029 / PRD FR-029: seed content — three named critiques with pre-filled proof_path
# Contract: specs/structured-roadmap/contracts/interfaces.md §2.8
#
# Usage:   seed-critiques.sh
# Output:  stdout = JSON {"created": <int>, "skipped": <bool>}
# Exit:    0 always

set -u

ROOT="${ROOT:-.}"
ITEMS_DIR="$ROOT/.kiln/roadmap/items"

# Fire only when items dir is empty (idempotent per §2.8)
if [ -d "$ITEMS_DIR" ]; then
  if find "$ITEMS_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | read -r _; then
    printf '{"created":0,"skipped":true}\n'
    exit 0
  fi
fi

mkdir -p "$ITEMS_DIR"

SEED_DATE="2026-04-24"

write_critique() {
  local id="$1" title="$2" proof="$3" body="$4"
  local file="$ITEMS_DIR/${id}.md"
  [ -f "$file" ] && return 0
  cat > "$file" <<EOF
---
id: ${id}
title: "${title}"
kind: critique
date: ${SEED_DATE}
status: open
phase: unsorted
state: planned
blast_radius: cross-cutting
review_cost: careful
context_cost: ongoing — revisit each release
proof_path: |
  ${proof}
---

# ${title}

${body}

_Seed critique — FR-029. Edit \`proof_path\` above if your definition of "disproved" is sharper than the default._
EOF
}

write_critique \
  "${SEED_DATE}-too-many-tokens" \
  "kiln uses too many tokens compared to doing it by hand" \
  "A 30-day audit shows the median feature PR consumed fewer tokens with kiln than the ad-hoc baseline capture would have consumed; or, the total token cost per shipped FR decreased by ≥30% over two consecutive releases." \
  "The fear: kiln's scaffolding (spec, plan, tasks, contracts, audits, retros) burns more context than the value it returns. Counter-examples should show either fewer total tokens per shipped unit of work, or comparable tokens with meaningfully higher quality (fewer bugs, less rework)."

write_critique \
  "${SEED_DATE}-unauditable-buggy-code" \
  "kiln produces unauditable buggy code" \
  "Over a 10-PR window, (a) escaped-bug rate is ≤ hand-written baseline, AND (b) every production bug traces to a spec FR or blocker, meaning audit was possible even if the code was wrong." \
  "The fear: because the pipeline writes code at machine speed, humans stop reading it, and the spec→code traceability is only aspirational. Counter-examples should show that FR-comments, test references, and PRD audit actually caught regressions or made diagnosis fast."

write_critique \
  "${SEED_DATE}-too-much-setup" \
  "kiln requires too much setup" \
  "A new user runs \`/kiln:kiln-init\` or \`/clay:clay-create-repo\` and ships a first real PR (not a throwaway) in ≤90 minutes; measured by a recorded session or a reproducible quickstart." \
  "The fear: the four-gate hook system, the spec scaffolding, and the plugin install path add so much friction that dropouts happen before value shows. Counter-examples should show a reliable first-run happy path and a short time-to-first-PR."

printf '{"created":3,"skipped":false}\n'
