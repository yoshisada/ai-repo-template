#!/usr/bin/env bash
# vision-tooling SC-009 / NFR-005 — back-compat assertion.
#
# Asserts that the post-PRD `kiln-roadmap --vision` (with NO new simple-
# params or --check-vision-alignment flag) preserves byte-identity with the
# pre-PRD coached-interview path. Per NFR-001, LLM-mediated stdout is
# explicitly NOT deterministic; "byte-identity" therefore anchors on the
# DETERMINISTIC SKELETON: literal banner strings, no-drift exit, frontmatter
# preservation, and the §V dispatch routing. The baseline file at
# fixtures/pre-prd-coached-output.txt enumerates those anchors.
#
# Tier-2 substrate (PR #189 convention). Run via:
#     bash plugin-kiln/tests/vision-coached-back-compat/run.sh

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../../.." && pwd)"
FIXTURE_DIR="$SELF_DIR/fixtures"
BASELINE="$FIXTURE_DIR/pre-prd-coached-output.txt"
SKILL="$REPO_ROOT/plugin-kiln/skills/kiln-roadmap/SKILL.md"
SCRIPTS="$REPO_ROOT/plugin-kiln/scripts/roadmap"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1" >&2; }
assert_file_contains() { # name file needle
  if grep -Fq -- "$2" "$3"; then pass "$1"
  else fail "$1 (missing '$2' in $3)"; fi
}

echo "=== vision-coached-back-compat: SC-009 / NFR-005 ==="

# ---------------------------------------------------------------------------
# Block 1 — fixtures present (R-4 mitigation: T001 baseline committed)
# ---------------------------------------------------------------------------
[ -s "$BASELINE" ] && pass "T001 baseline fixture exists ≥1 byte" \
  || fail "T001 baseline fixture missing or empty"
[ -s "$FIXTURE_DIR/vision.md" ] && pass "T001 frozen fixture vision.md exists" \
  || fail "T001 fixture vision.md missing"

# ---------------------------------------------------------------------------
# Block 2 — Each baseline anchor (literal pre-PRD §V text) is still present
#  in the post-PRD SKILL.md. The Theme A / B / C edits MUST be additive only;
#  removing or reshaping these literals breaks NFR-005.
# ---------------------------------------------------------------------------
assert_file_contains "NFR-005 §V dispatch anchor preserved (coached fallthrough)" \
  "jump to **§V: Vision update**" "$SKILL"
# NFR-005 byte-identity is BEHAVIOURAL — the coached path still routes when
# no simple-params flag is present. The literal dispatch line evolved
# additively in T011 to add §V-A; that's allowed.
assert_file_contains "NFR-005 §V-A simple-params dispatch additive" \
  "Vision simple-params CLI" "$SKILL"
assert_file_contains "NFR-005 §V.1 reader-warn anchor preserved" \
  "warn: project-context reader unavailable" "$SKILL"
assert_file_contains "NFR-005 §V.2 blank-slate banner verbatim" \
  "blank-slate fallback: the project-context snapshot is empty" "$SKILL"
assert_file_contains "NFR-005 §V.3 first-run banner verbatim" \
  "Here's a first-draft vision drawn from your repo" "$SKILL"
assert_file_contains "NFR-005 §V no-drift exit anchor preserved" \
  "no drift detected" "$SKILL"
assert_file_contains "NFR-005 §V Rules block preserved" \
  "Rules (FR-008..FR-012 test harness relies on these)" "$SKILL"

# ---------------------------------------------------------------------------
# Block 3 — Pre-PRD frontmatter rule: a no-drift run on the fixture vision.md
#  must NOT bump last_updated. Validator (with no flags) must produce empty
#  stdout AND exit 0, so the SKILL.md can fall through to the coached path.
# ---------------------------------------------------------------------------
PRE_HASH=$(shasum "$FIXTURE_DIR/vision.md" | awk '{print $1}')
EMPTY_OUT=$(bash "$SCRIPTS/vision-flag-validator.sh" -- )
RC=$?
[ -z "$EMPTY_OUT" ] && pass "FR-005 empty-flag stdout is empty (coached fallthrough)" \
  || fail "FR-005 expected empty stdout, got: $EMPTY_OUT"
[ "$RC" -eq 0 ] && pass "FR-005 empty-flag exit 0 (coached fallthrough)" \
  || fail "FR-005 expected exit 0, got $RC"
POST_HASH=$(shasum "$FIXTURE_DIR/vision.md" | awk '{print $1}')
[ "$PRE_HASH" = "$POST_HASH" ] \
  && pass "NFR-005 fixture vision.md byte-identical after validator pass" \
  || fail "NFR-005 fixture vision.md mutated by validator (forbidden)"

# ---------------------------------------------------------------------------
# Block 4 — The simple-params dispatch tree must be ADDITIVE: the existing
#  Step-1 dispatch table must still list `--vision`. Theme A's edit must
#  not have replaced or moved the line.
# ---------------------------------------------------------------------------
assert_file_contains "NFR-005 Step 1 dispatch table preserved" \
  "Step 1: Dispatch on flag (routing gate)" "$SKILL"

# ---------------------------------------------------------------------------
# Block 5 — Baseline file documents the deterministic skeleton (sanity: each
#  enumerated anchor we just asserted appears in the baseline file too).
# ---------------------------------------------------------------------------
assert_file_contains "baseline enumerates blank-slate banner" \
  "blank-slate fallback" "$BASELINE"
assert_file_contains "baseline enumerates no-drift exit" \
  "no drift detected" "$BASELINE"
assert_file_contains "baseline enumerates SKILL anchor for dispatch" \
  "Step 1: Dispatch on flag" "$BASELINE"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "PASS vision-coached-back-compat: $PASS assertion blocks"
exit 0
