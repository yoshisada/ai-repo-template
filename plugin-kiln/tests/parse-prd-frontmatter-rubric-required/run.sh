#!/usr/bin/env bash
# T013 — SC-007 / FR-010 / contracts §3.
# Asserts parse-prd-frontmatter.sh's additive rubric validator:
#   1. metric: output_quality with no rubric → exit 2 + Bail out! output_quality-axis-missing-rubric.
#   2. metric: output_quality with empty rubric → exit 2 (same).
#   3. metric: output_quality with non-empty quoted rubric → exit 0 + JSON includes rubric verbatim.
#   4. metric: tokens (no output_quality) → exit 0 (back-compat preserved).
# Substrate: tier-2 (run.sh-only).
# Invoke: bash plugin-kiln/tests/parse-prd-frontmatter-rubric-required/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PARSER="$REPO_ROOT/plugin-wheel/scripts/harness/parse-prd-frontmatter.sh"

[[ -x "$PARSER" ]] || { echo "FAIL: parser not executable at $PARSER"; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
assert_pass() {
  local name="$1"; shift
  if "$@"; then
    PASS=$((PASS + 1)); printf '  pass  %s\n' "$name"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$name"
  fi
}

# Case 1: missing rubric → exit 2 with bail-out message.
case_missing_rubric() {
  local prd="$TMP/prd-missing.md"
  cat > "$prd" <<'EOF'
---
blast_radius: feature
empirical_quality: [{metric: output_quality, direction: equal_or_better}]
---
body
EOF
  local err
  err=$(bash "$PARSER" "$prd" 2>&1 >/dev/null) && return 1
  [[ "$?" == "0" ]] && return 1  # bash quirk: capture exit via subshell test next
  bash "$PARSER" "$prd" >/dev/null 2>"$TMP/err1"
  local rc=$?
  [[ "$rc" == "2" ]] || return 1
  grep -q -F "Bail out! output_quality-axis-missing-rubric:" "$TMP/err1"
}
assert_pass "Missing rubric → exit 2 + bail-out message" case_missing_rubric

# Case 2: empty (quoted-empty-string) rubric → exit 2.
case_empty_rubric() {
  local prd="$TMP/prd-empty.md"
  cat > "$prd" <<'EOF'
---
empirical_quality: [{metric: output_quality, direction: equal_or_better, rubric: ""}]
---
body
EOF
  bash "$PARSER" "$prd" >/dev/null 2>"$TMP/err2"
  local rc=$?
  [[ "$rc" == "2" ]] || return 1
  grep -q -F "Bail out! output_quality-axis-missing-rubric:" "$TMP/err2"
}
assert_pass "Empty rubric → exit 2 + bail-out message" case_empty_rubric

# Case 3: non-empty quoted rubric → exit 0 + JSON projection includes rubric verbatim.
case_valid_rubric() {
  local prd="$TMP/prd-valid.md"
  local rubric_text='Error messages should name the specific failure mode and suggest one concrete next action'
  cat > "$prd" <<EOF
---
blast_radius: feature
empirical_quality: [{metric: output_quality, direction: equal_or_better, rubric: "$rubric_text"}]
---
body
EOF
  local out
  out=$(bash "$PARSER" "$prd" 2>"$TMP/err3")
  local rc=$?
  [[ "$rc" == "0" ]] || return 1
  # JSON projection contains the rubric verbatim.
  printf '%s' "$out" | jq -e --arg r "$rubric_text" '.empirical_quality[0].rubric == $r' >/dev/null
}
assert_pass "Valid rubric → exit 0 + verbatim preservation" case_valid_rubric

# Case 4: back-compat — non-output_quality axis with no rubric → exit 0.
case_back_compat() {
  local prd="$TMP/prd-tokens.md"
  cat > "$prd" <<'EOF'
---
blast_radius: feature
empirical_quality: [{metric: tokens, direction: lower}]
---
body
EOF
  bash "$PARSER" "$prd" >/dev/null 2>&1
  [[ "$?" == "0" ]]
}
assert_pass "tokens-only PRD (no rubric needed) → exit 0" case_back_compat

# Case 5: rubric character preservation — punctuation + colons + special chars.
case_rubric_special_chars() {
  local prd="$TMP/prd-special.md"
  local rubric_text='Quote: name the failure (e.g., timeout, OOM); end with one next action.'
  cat > "$prd" <<EOF
---
empirical_quality: [{metric: output_quality, direction: equal_or_better, rubric: "$rubric_text"}]
---
body
EOF
  local out
  out=$(bash "$PARSER" "$prd" 2>/dev/null)
  printf '%s' "$out" | jq -e --arg r "$rubric_text" '.empirical_quality[0].rubric == $r' >/dev/null
}
assert_pass "Rubric with special chars preserved character-for-character" case_rubric_special_chars

TOTAL=$((PASS + FAIL))
echo
if [[ $FAIL -eq 0 ]]; then
  echo "PASS: $PASS/$TOTAL assertions"; exit 0
else
  echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1
fi
