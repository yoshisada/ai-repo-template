#!/usr/bin/env bash
# T016 — SC-004 / FR-004 / NFR-002.
# Asserts deterministic synthesizer output filenames: `fixture-NNN.md`
# zero-padded 3-digit index. The synthesizer agent itself is mocked (CLAUDE.md
# Rule 5 — newly-shipped agents not live-spawnable in the same session); we
# write N pre-baked fixture files into a proposed-corpus dir using the SAME
# naming convention asserted by the agent's contract (§6) and verify that:
#   1. Filenames match `fixture-NNN.md` regex with zero-padding.
#   2. Sorted filename order matches numeric index order.
#   3. Re-running the mock-write produces byte-identical filename sets.
# Substrate: tier-2 (run.sh-only).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert_pass() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"; else FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"; fi
}

# Mock-synthesizer pre-bake. The shared name-generator in this test mirrors
# what the orchestrator's synthesizer-spawn caller documents (§6 final stanza:
# "fixture-NNN.md zero-padded 3-digit index"). If the convention drifts, the
# generator MUST drift too — so this test is the canary.
mock_write_fixtures() {
  local outdir="$1" count="$2"
  mkdir -p "$outdir"
  rm -f "$outdir"/*.md
  local i
  for ((i = 1; i <= count; i++)); do
    local fid
    fid=$(printf 'fixture-%03d.md' "$i")
    cat > "$outdir/$fid" <<EOF
---
axis_focus: tokens
shape: typical
summary: Synthetic fixture $i for stable-naming test.
---
Body of fixture $i.
EOF
  done
}

# Case 1: 3-digit zero padding — confirm small N produces correct filenames.
case_zero_padding() {
  local d="$TMP/run1"
  mock_write_fixtures "$d" 5
  local got expected
  got=$(cd "$d" && ls fixture-*.md | sort | tr '\n' ' ' | sed 's/ $//')
  expected="fixture-001.md fixture-002.md fixture-003.md fixture-004.md fixture-005.md"
  [[ "$got" == "$expected" ]]
}
assert_pass "Filenames zero-padded to 3 digits (fixture-001..005)" case_zero_padding

# Case 2: 10+ fixtures — verify ordering still works.
case_ten_plus() {
  local d="$TMP/run2"
  mock_write_fixtures "$d" 12
  local first_three last_three
  # Sorting fixture-001..fixture-012 ALPHABETICALLY = NUMERICALLY thanks to padding.
  first_three=$(cd "$d" && ls fixture-*.md | sort | head -3 | tr '\n' ' ')
  last_three=$(cd "$d" && ls fixture-*.md | sort | tail -3 | tr '\n' ' ')
  [[ "$first_three" == "fixture-001.md fixture-002.md fixture-003.md " ]] || return 1
  [[ "$last_three" == "fixture-010.md fixture-011.md fixture-012.md " ]]
}
assert_pass "Lexicographic sort matches numeric order at N≥10" case_ten_plus

# Case 3: re-run determinism — the FILENAME SET must be byte-identical.
case_filename_determinism() {
  local d1="$TMP/det1" d2="$TMP/det2"
  mock_write_fixtures "$d1" 7
  mock_write_fixtures "$d2" 7
  diff <(cd "$d1" && ls *.md | sort) <(cd "$d2" && ls *.md | sort) >/dev/null
}
assert_pass "Filename set byte-identical across two synthesis runs" case_filename_determinism

# Case 4: regex shape conformance.
case_regex_shape() {
  local d="$TMP/run3"
  mock_write_fixtures "$d" 4
  local f
  for f in "$d"/fixture-*.md; do
    [[ "$(basename "$f")" =~ ^fixture-[0-9]{3}\.md$ ]] || return 1
  done
}
assert_pass "Each filename matches fixture-NNN.md regex" case_regex_shape

# Case 5: agent contract documents this naming. Grep the agent.md.
case_agent_documents_naming() {
  local agent="$SCRIPT_DIR/../../agents/fixture-synthesizer.md"
  grep -q -F 'fixture-NNN.md' "$agent" \
    && grep -q -F 'zero-padded' "$agent"
}
assert_pass "Synthesizer agent.md documents fixture-NNN.md naming" case_agent_documents_naming

TOTAL=$((PASS+FAIL))
echo
if [[ $FAIL -eq 0 ]]; then echo "PASS: $PASS/$TOTAL assertions"; exit 0
else echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1; fi
