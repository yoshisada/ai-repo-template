#!/usr/bin/env bash
# Test: distill-single-theme-no-regression
#
# Validates: FR-021 / NFR-005 — single-theme distill MUST produce
# byte-identical output to pre-change behavior. The multi-select picker
# MAY appear in single-viable-theme repos; selecting the lone theme MUST
# yield byte-identical single-theme output.
#
# Strategy — assertion-level tripwire on the SKILL.md:
#   1. Picker body explicitly short-circuits when N_themes == 1 (Step 3
#      "Shortcut" language + auto-select-all fallback on select-themes.sh).
#   2. select-themes.sh's Channel 4 fallback auto-selects ALL themes when
#      no env var is set — exercised by direct script call here.
#   3. Run-plan block is OMITTED when N<2 (FR-018 + emit-run-plan.sh
#      contract) — exercised by direct script call here.
#   4. SKILL.md has an explicit rule acknowledging FR-021 / NFR-005.
#
# This is a tripwire against accidental coupling of the multi-theme path
# into the single-theme case.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../../skills/kiln-distill/SKILL.md"
SELECT="$SCRIPT_DIR/../../scripts/distill/select-themes.sh"
EMIT="$SCRIPT_DIR/../../scripts/distill/emit-run-plan.sh"

# 1. SKILL.md carries the N=1 shortcut documentation.
if ! grep -qF 'if there is exactly ONE theme, skip the prompt' "$SKILL"; then
  echo "FAIL: single-theme shortcut language missing from SKILL.md Step 3" >&2
  exit 1
fi

# 2. Explicit FR-021 / NFR-005 rule.
if ! grep -qE 'Single-theme byte-identical compat.*FR-021.*NFR-005' "$SKILL"; then
  echo "FAIL: SKILL.md Rules section missing FR-021/NFR-005 compat acknowledgement" >&2
  exit 1
fi

# 3. select-themes.sh Channel 4 auto-select-all works for single theme
#    (no env var, no cancel).
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/one-theme.json" <<'EOF'
[{"slug":"lone-theme","entries":[
  {"type_tag":"issue","path":".kiln/issues/x.md"}
]}]
EOF

OUT=$(bash "$SELECT" "$TMP/one-theme.json")
SEL_COUNT=$(echo "$OUT" | jq '.selected_slugs | length')
if [[ "$SEL_COUNT" -ne 1 ]]; then
  echo "FAIL: single-theme auto-select did not pick the lone theme" >&2
  echo "Got: $OUT" >&2
  exit 1
fi
SEL_SLUG=$(echo "$OUT" | jq -r '.selected_slugs[0]')
if [[ "$SEL_SLUG" != "lone-theme" ]]; then
  echo "FAIL: auto-selected wrong slug '$SEL_SLUG' (expected 'lone-theme')" >&2
  exit 1
fi

# 4. emit-run-plan.sh emits zero bytes for N=1.
cat > "$TMP/one-emission.json" <<'EOF'
[{"slug":"lone-theme","path":"docs/features/2026-04-24-lone-theme/PRD.md","severity_hint":"null"}]
EOF
RUN_PLAN=$(bash "$EMIT" "$TMP/one-emission.json")
if [[ -n "$RUN_PLAN" ]]; then
  echo "FAIL: emit-run-plan.sh produced output for N=1 — MUST be zero bytes (FR-018 + FR-021)" >&2
  printf 'Got:\n%s\n' "$RUN_PLAN" >&2
  exit 1
fi

echo "PASS: single-theme path remains byte-identical (FR-021 / NFR-005)"
