#!/usr/bin/env bash
# vision-tooling Theme A — pure-shell test substrate (tier 2; PR #189
# convention). Validates SC-001, SC-002, SC-009 anchors, FR-001 (interview
# skip), FR-004 (warn-and-continue), FR-005 (validator) end-to-end against
# the writer + validator + dispatch + flag-map.
#
# Cited substrate: tier 2 (pure-shell run.sh — no kiln-test harness coverage
# exists for these scripts yet). Run via:
#     bash plugin-kiln/tests/vision-simple-params/run.sh
#
# Coverage gate: ≥12 assertion blocks (NFR-004 / plan §Constitution Check
# Article II / PR #189 fixture-and-assertion-block convention).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS="$REPO_ROOT/plugin-kiln/scripts/roadmap"
FIXTURE_VISION="$REPO_ROOT/plugin-kiln/tests/vision-coached-back-compat/fixtures/vision.md"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1" >&2; }
assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then pass "$1"
  else fail "$1 (expected '$2', got '$3')"; fi
}
assert_contains() { # name needle haystack
  if printf '%s' "$3" | grep -Fq -- "$2"; then pass "$1"
  else fail "$1 (missing '$2')"; fi
}
assert_not_contains() { # name needle haystack
  if printf '%s' "$3" | grep -Fq -- "$2"; then fail "$1 (unexpected '$2')"
  else pass "$1"; fi
}

setup_repo() {
  WORK=$(mktemp -d)
  mkdir -p "$WORK/.kiln"
  cp "$FIXTURE_VISION" "$WORK/.kiln/vision.md"
  cd "$WORK"
  git init -q
  git config user.email t@t.t
  git config user.name t
  git add .kiln/vision.md
  git -c commit.gpgsign=false commit -qm "fixture"
}
teardown_repo() {
  cd "$REPO_ROOT"
  rm -rf "$WORK"
}

echo "=== vision-simple-params: tier-2 shell substrate ==="

# ---------------------------------------------------------------------------
# Block 1 — SC-001 (a/b/c): bullet under correct section + last_updated bump
#                            + verbatim text preserved.
# ---------------------------------------------------------------------------
setup_repo
START_TS=$(date +%s)
OUT=$(KILN_REPO_ROOT="$WORK" KILN_VISION_TODAY=2026-04-27 \
  bash "$SCRIPTS/vision-write-section.sh" --add-constraint "Verbatim payload — Δ test" 2>&1)
RC=$?
END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))
assert_eq "SC-001 writer exits 0 on happy path" 0 "$RC"
assert_contains "SC-001(a) bullet appended under Guiding constraints" \
  "- Verbatim payload — Δ test" \
  "$(sed -n '/^## Guiding constraints/,/^## /p' "$WORK/.kiln/vision.md")"
assert_contains "SC-001(b) last_updated bumped to today" \
  "last_updated: 2026-04-27" \
  "$(head -3 "$WORK/.kiln/vision.md")"
assert_contains "SC-001(c) verbatim text preserved (no Unicode mangling)" \
  "Verbatim payload — Δ test" \
  "$(cat "$WORK/.kiln/vision.md")"
# Block 2 — SC-001(d): <3-second wall-clock budget (we use a generous bound
#  on shell ops; the budget is dominated by awk + mv on a small file).
if [ "$ELAPSED" -lt 3 ]; then
  pass "SC-001(d) write completed in <3s wall-clock ($ELAPSED s)"
else
  fail "SC-001(d) write exceeded 3s budget ($ELAPSED s)"
fi
teardown_repo

# ---------------------------------------------------------------------------
# Block 3 — SC-002: flag-conflict refusal + empty git diff (no I/O on refusal)
# ---------------------------------------------------------------------------
setup_repo
OUT=$(bash "$SCRIPTS/vision-flag-validator.sh" -- \
  --add-constraint "x" --add-non-goal "y" 2>&1)
RC=$?
assert_eq "SC-002 validator exits 2 on flag conflict" 2 "$RC"
assert_contains "SC-002 conflict diagnostic shape" \
  "mutually exclusive" "$OUT"
DIFF=$(git diff --quiet; echo $?)
assert_eq "SC-002 git diff empty after refusal" 0 "$DIFF"
teardown_repo

# ---------------------------------------------------------------------------
# Block 4 — FR-005: unknown-flag rejection (exit 2)
# ---------------------------------------------------------------------------
OUT=$(bash "$SCRIPTS/vision-flag-validator.sh" -- --add-bogus "z" 2>&1)
RC=$?
assert_eq "FR-005 unknown-flag exits 2" 2 "$RC"
assert_contains "FR-005 unknown-flag diagnostic" \
  "unknown flag: --add-bogus" "$OUT"

# ---------------------------------------------------------------------------
# Block 5 — FR-005: empty-value rejection (exit 2)
# ---------------------------------------------------------------------------
OUT=$(bash "$SCRIPTS/vision-flag-validator.sh" -- --add-constraint "" 2>&1)
RC=$?
assert_eq "FR-005 empty-value exits 2" 2 "$RC"
assert_contains "FR-005 empty-value diagnostic" \
  "non-empty value" "$OUT"

# ---------------------------------------------------------------------------
# Block 6 — FR-004: missing .shelf-config → warn-and-continue, exit 0
# ---------------------------------------------------------------------------
setup_repo
OUT=$(KILN_REPO_ROOT="$WORK" bash "$SCRIPTS/vision-shelf-dispatch.sh" 2>&1)
RC=$?
assert_eq "FR-004 dispatch exits 0 with missing .shelf-config" 0 "$RC"
assert_contains "FR-004 warn-shape literal" \
  "shelf: .shelf-config not configured" "$OUT"
teardown_repo

# ---------------------------------------------------------------------------
# Block 7 — FR-004: configured .shelf-config + KILN_TEST_DISABLE_LLM →
#                    dispatch-mocked, exit 0
# ---------------------------------------------------------------------------
setup_repo
cat > "$WORK/.shelf-config" <<EOF
base_path: /tmp/vault
slug: testproj
EOF
OUT=$(KILN_REPO_ROOT="$WORK" KILN_TEST_DISABLE_LLM=1 \
  bash "$SCRIPTS/vision-shelf-dispatch.sh" 2>&1)
RC=$?
assert_eq "FR-004 dispatch exits 0 with valid .shelf-config" 0 "$RC"
assert_contains "FR-004 dispatch-fired marker" \
  "dispatched mirror update" "$OUT"
teardown_repo

# ---------------------------------------------------------------------------
# Block 8 — FR-001 last sentence: simple-params path emits NO coached-
#           interview prompts. The validator's stdout is the only signal the
#           skill needs to dispatch; no banner / no §V.* prompt appears.
# ---------------------------------------------------------------------------
OUT=$(bash "$SCRIPTS/vision-flag-validator.sh" -- --add-constraint "x" 2>&1)
assert_not_contains "FR-001 no blank-slate banner emitted" \
  "blank-slate fallback" "$OUT"
assert_not_contains "FR-001 no first-draft banner emitted" \
  "Here's a first-draft vision" "$OUT"
assert_not_contains "FR-001 no step-through prompt emitted" \
  "step-through" "$OUT"

# ---------------------------------------------------------------------------
# Block 9 — atomic-write rollback: simulate awk failure by passing a flag
#  whose section is missing from a corrupted vision.md. Writer must exit 2
#  and leave the file byte-identical.
# ---------------------------------------------------------------------------
setup_repo
# Strip "## Guiding constraints" section header to force section-not-found.
sed -i.bak '/^## Guiding constraints$/d' "$WORK/.kiln/vision.md" && rm -f "$WORK/.kiln/vision.md.bak"
PRE_HASH=$(git -C "$WORK" hash-object "$WORK/.kiln/vision.md")
OUT=$(KILN_REPO_ROOT="$WORK" KILN_VISION_TODAY=2026-04-27 \
  bash "$SCRIPTS/vision-write-section.sh" --add-constraint "should-fail" 2>&1)
RC=$?
POST_HASH=$(git -C "$WORK" hash-object "$WORK/.kiln/vision.md")
assert_eq "FR-002 missing section exits 2" 2 "$RC"
assert_eq "FR-003 vision.md byte-identical after refusal" "$PRE_HASH" "$POST_HASH"
teardown_repo

# ---------------------------------------------------------------------------
# Block 10 — flag-map exposes all seven canonical flags (FR-021 maintenance
#  contract surface).
# ---------------------------------------------------------------------------
OUT=$(bash "$SCRIPTS/vision-section-flag-map.sh" --list)
assert_contains "FR-021 add-constraint mapped" "add-constraint" "$OUT"
assert_contains "FR-021 add-non-goal mapped"   "add-non-goal"   "$OUT"
assert_contains "FR-021 add-signal mapped"     "add-signal"     "$OUT"
assert_contains "FR-021 update-what mapped"    "update-what"    "$OUT"
assert_contains "FR-021 update-not mapped"     "update-not"     "$OUT"
assert_contains "FR-021 update-signals mapped" "update-signals" "$OUT"
assert_contains "FR-021 update-constraints mapped" "update-constraints" "$OUT"

# ---------------------------------------------------------------------------
# Block 11 — replace-body op semantics: --update-not replaces "What it is not"
#  body verbatim while preserving surrounding sections.
# ---------------------------------------------------------------------------
setup_repo
KILN_REPO_ROOT="$WORK" KILN_VISION_TODAY=2026-04-27 \
  bash "$SCRIPTS/vision-write-section.sh" --update-not "Brand new body line." >/dev/null
NEW=$(sed -n '/^## What it is not/,/^## /p' "$WORK/.kiln/vision.md")
assert_contains "FR-002 replace-body inserted new body" "Brand new body line." "$NEW"
assert_not_contains "FR-002 replace-body dropped old body" \
  "Not a fully autonomous system" "$NEW"
PRESERVED=$(sed -n '/^## How we.ll know we.re winning/,/^## /p' "$WORK/.kiln/vision.md")
assert_contains "FR-002 sibling section preserved" \
  "An idea captured" "$PRESERVED"
teardown_repo

# ---------------------------------------------------------------------------
# Block 12 — equals-form flag parsing (--add-constraint=value)
# ---------------------------------------------------------------------------
OUT=$(bash "$SCRIPTS/vision-flag-validator.sh" -- --add-constraint=hello)
assert_eq "FR-005 equals-form parsed" "--add-constraint	hello" "$OUT"

# ---------------------------------------------------------------------------
echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "PASS vision-simple-params: $PASS assertion blocks"
exit 0
