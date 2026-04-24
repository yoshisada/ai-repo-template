#!/usr/bin/env bash
# Test: distill-multi-theme-basic
#
# Validates: FR-017 (multi-select picker + N-PRD emission) + US4 scenario 1
# "backlog has 3+ themes, user picks 2 → exactly 2 PRDs are written and no
# others."
#
# Strategy — static SKILL.md content tripwire:
#   A live plugin-skill harness run of /kiln:kiln-distill with a
#   3-theme backlog and a 2-theme selection requires interactive-stdin
#   support in the claude --print subprocess AND deterministic LLM
#   behavior — both of which are outside this PR's scope. Instead, this
#   run.sh asserts the structural invariants in SKILL.md that make the
#   behavior possible:
#     - Multi-select picker section exists (FR-017 anchor).
#     - select-themes.sh invocation call-site matches the contract.
#     - Per-theme emission loop (FR-017 + FR-019 bundle tracking) exists.
#     - disambiguate-slug.sh call-site matches the contract.
#   The downstream live behavioral test runs under `/kiln:kiln-test
#   plugin-kiln` once harness stdin support lands (tracked for Phase 6).
#
# This is the same tripwire pattern used by roadmap-coached-interview-*
# tests committed by impl-context-roadmap (see 216169c).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../../skills/kiln-distill/SKILL.md"

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL: SKILL.md missing at $SKILL" >&2
  exit 1
fi

# 1. Multi-select picker section with FR-017 anchor.
if ! grep -qE '^## Step 3:.*Multi-Theme Picker.*FR-017' "$SKILL"; then
  echo "FAIL: Step 3 header missing FR-017 multi-select picker anchor" >&2
  exit 1
fi

# 2. Picker presents the multi-select UX (comma-separated list + "all" + "cancel").
for phrase in \
    "A single theme name or number" \
    "A comma-separated list of numbers" \
    '"all" to bundle every theme as its own PRD' \
    '"cancel" to abort without writing anything'; do
  if ! grep -qF "$phrase" "$SKILL"; then
    echo "FAIL: picker UX missing phrase: $phrase" >&2
    exit 1
  fi
done

# 3. select-themes.sh invocation call-site (contract call-site exact match).
if ! grep -qE 'bash plugin-kiln/scripts/distill/select-themes\.sh' "$SKILL"; then
  echo "FAIL: select-themes.sh call-site missing" >&2
  exit 1
fi

# 4. Per-theme emission loop (FR-017 + FR-019 bundle isolation).
if ! grep -qE 'Per-Theme Emission Loop.*FR-017.*FR-019.*FR-020' "$SKILL"; then
  echo "FAIL: Per-theme emission loop section missing canonical FR anchors" >&2
  exit 1
fi
if ! grep -qF 'for i in "${!SLUGS_ARR[@]}"' "$SKILL"; then
  echo "FAIL: per-theme loop scaffold not present" >&2
  exit 1
fi

# 5. disambiguate-slug.sh call-site.
if ! grep -qE 'bash plugin-kiln/scripts/distill/disambiguate-slug\.sh' "$SKILL"; then
  echo "FAIL: disambiguate-slug.sh call-site missing" >&2
  exit 1
fi

# 6. Per-PRD bundle tracking (PRD_BUNDLES array or equivalent).
if ! grep -qF 'PRD_BUNDLES+=(' "$SKILL"; then
  echo "FAIL: PRD_BUNDLES tracking missing — needed for Step 5 per-PRD flip partition (FR-019)" >&2
  exit 1
fi

# 7. Three-group derived_from sort is per-PRD (FR-020 / NFR-003).
if ! grep -qE 'LC_ALL=C sort' "$SKILL"; then
  echo "FAIL: LC_ALL=C sort not present — required for byte-identical determinism (NFR-003)" >&2
  exit 1
fi

echo "PASS: SKILL.md structural invariants for multi-theme emission present"
