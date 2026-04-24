#!/usr/bin/env bash
# Test: distill-multi-theme-run-plan
#
# Validates: FR-018 (run-plan block formatting) + US4 scenario 3 "when the
# run-plan prints, it lists N /kiln:kiln-build-prd <slug> lines in an
# explicit order with a one-line rationale per line" + FR-018 omission
# rule for single-PRD runs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT="$SCRIPT_DIR/../../scripts/distill/emit-run-plan.sh"

if [[ ! -x "$EMIT" ]]; then
  echo "FAIL: emit-run-plan.sh missing or not executable" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- Case 1: N=1 → zero bytes on stdout ----
cat > "$TMP/single.json" <<'EOF'
[{"slug":"only","path":"docs/features/2026-04-24-only/PRD.md","severity_hint":"null"}]
EOF
OUT1="$(bash "$EMIT" "$TMP/single.json")"
if [[ -n "$OUT1" ]]; then
  echo "FAIL case 1: N=1 must emit zero bytes (FR-018 omission)." >&2
  printf 'Got:\n%s\n' "$OUT1" >&2
  exit 1
fi

# ---- Case 2: N=2 renders block with 2 numbered lines + rationale ----
cat > "$TMP/two.json" <<'EOF'
[
  {"slug":"foundation","path":"docs/features/2026-04-24-foundation/PRD.md","severity_hint":"foundational"},
  {"slug":"user-flow","path":"docs/features/2026-04-24-user-flow/PRD.md","severity_hint":"highest"}
]
EOF
OUT2="$(bash "$EMIT" "$TMP/two.json")"
if ! grep -q '^## Run Plan$' <<<"$OUT2"; then
  echo "FAIL case 2: missing '## Run Plan' header" >&2
  printf '%s\n' "$OUT2" >&2
  exit 1
fi
if ! grep -qE '^1\. `/kiln:kiln-build-prd foundation` — .+$' <<<"$OUT2"; then
  echo "FAIL case 2: foundation line missing/malformed" >&2
  printf '%s\n' "$OUT2" >&2
  exit 1
fi
if ! grep -qE '^2\. `/kiln:kiln-build-prd user-flow` — .+$' <<<"$OUT2"; then
  echo "FAIL case 2: user-flow line missing/malformed" >&2
  printf '%s\n' "$OUT2" >&2
  exit 1
fi

# ---- Case 3: severity ordering — foundational wins over highest ----
# Build input where "highest" appears BEFORE "foundational"; output must
# still put foundational first (FR-018 ordering rule).
cat > "$TMP/sev.json" <<'EOF'
[
  {"slug":"alpha","path":"x","severity_hint":"highest"},
  {"slug":"beta","path":"x","severity_hint":"foundational"}
]
EOF
OUT3="$(bash "$EMIT" "$TMP/sev.json")"
# Line-number check: beta's numbered line must come before alpha's.
BETA_LINE=$(grep -nE '^[0-9]+\. `/kiln:kiln-build-prd beta`' <<<"$OUT3" | cut -d: -f1)
ALPHA_LINE=$(grep -nE '^[0-9]+\. `/kiln:kiln-build-prd alpha`' <<<"$OUT3" | cut -d: -f1)
if [[ -z "$BETA_LINE" || -z "$ALPHA_LINE" || "$BETA_LINE" -ge "$ALPHA_LINE" ]]; then
  echo "FAIL case 3: severity ordering violated — foundational (beta) must precede highest (alpha)." >&2
  printf '%s\n' "$OUT3" >&2
  exit 1
fi

# ---- Case 4: stable sort within same severity (input order preserved) ----
cat > "$TMP/stable.json" <<'EOF'
[
  {"slug":"mid-one","path":"x","severity_hint":"med","rationale":"first"},
  {"slug":"mid-two","path":"x","severity_hint":"med","rationale":"second"}
]
EOF
OUT4="$(bash "$EMIT" "$TMP/stable.json")"
ONE_LINE=$(grep -nE '^[0-9]+\. `/kiln:kiln-build-prd mid-one`' <<<"$OUT4" | cut -d: -f1)
TWO_LINE=$(grep -nE '^[0-9]+\. `/kiln:kiln-build-prd mid-two`' <<<"$OUT4" | cut -d: -f1)
if [[ "$ONE_LINE" -ge "$TWO_LINE" ]]; then
  echo "FAIL case 4: stable-sort within same severity broken — mid-one must precede mid-two." >&2
  printf '%s\n' "$OUT4" >&2
  exit 1
fi

# ---- Case 5: user-supplied rationale preserved verbatim ----
if ! grep -qE '— first$' <<<"$OUT4"; then
  echo "FAIL case 5: custom rationale 'first' not rendered verbatim" >&2
  printf '%s\n' "$OUT4" >&2
  exit 1
fi

echo "PASS: emit-run-plan renders block correctly with omission + severity sort + stable-within-tie"
