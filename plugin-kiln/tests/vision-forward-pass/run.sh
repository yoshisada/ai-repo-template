#!/usr/bin/env bash
# Test: vision-forward-pass (Theme C, T017)
#
# Validates: SC-004 literal opt-in prompt + default-N early-exit (validated
# at SKILL.md edit time — see T022 wiring). SC-005 tag-set validation +
# evidence-cite presence + ≤5 cap. SC-005 accept→`--promote` invocation
# (validated at SKILL.md edit time), decline→declined-record file write,
# skip→nothing written. SC-006 dedup verified via two-pass run. SC-010
# simple-params path emits zero forward-pass-prompt matches (validated by
# vision-simple-params/run.sh — that test owns the FR-014 guard).
#
# Substrate: PURE-SHELL UNIT FIXTURE — invoked via `bash run.sh`. Cannot be
# discovered by /kiln:kiln-test (substrate gap B-1).
set -uo pipefail
LC_ALL=C
export LC_ALL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FORWARD="$REPO_ROOT/plugin-kiln/scripts/roadmap/vision-forward-pass.sh"
DECISION="$REPO_ROOT/plugin-kiln/scripts/roadmap/vision-forward-decision.sh"
DECLINE_WRITE="$REPO_ROOT/plugin-kiln/scripts/roadmap/vision-forward-decline-write.sh"
DEDUP_LOAD="$REPO_ROOT/plugin-kiln/scripts/roadmap/vision-forward-dedup-load.sh"

PASS_COUNT=0
FAIL_COUNT=0
assert() {
  local desc="$1" cond_rc="$2"
  if [ "$cond_rc" = "0" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  PASS [$PASS_COUNT]: $desc"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "  FAIL [$FAIL_COUNT]: $desc" >&2
  fi
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
mkdir -p .kiln/roadmap/items

# ---- Mock-LLM forward-pass fixture: 3 valid blocks + 1 invalid (bad tag) ----
MOCK="$TMP/mock-llm"
mkdir -p "$MOCK"
cat > "$MOCK/forward-pass.txt" <<'EOF'
title: Vision drift detector
tag: gap
evidence: .kiln/vision.md:#how-well-know-were-winning
body: We mention drift in vision but no script flags it on the queue.

title: Forward-pass cache layer
tag: opportunity
evidence: docs/features/2026-04-27-vision-tooling/PRD.md
body: Cache LLM responses across runs to amortize cost.

title: Coach-to-pipeline handoff
tag: adjacency
evidence: plugin-kiln/skills/kiln-build-prd/SKILL.md
body: Coach interview output could seed the build-prd team prompt.

title: Bad-tag suggestion
tag: nonsense
evidence: nowhere
body: This block has an invalid tag and should be filtered.
EOF

export KILN_TEST_MOCK_LLM_DIR="$MOCK"

# ---- SC-005: forward-pass emits ≤5 valid blocks; invalid-tag filtered ----
RAW_OUT=$(bash "$FORWARD")

# Each block is 4 lines + a blank-line separator. Count blank-line-separated
# blocks; should be 3 (the 4th had a bad tag and was filtered).
BLOCK_COUNT=$(printf '%s\n' "$RAW_OUT" | awk 'BEGIN{c=0; in_block=0} NF { if(!in_block){c++; in_block=1} } /^$/ { in_block=0 } END { print c }')
assert "SC-005: forward-pass emits 3 blocks (1 of 4 filtered for bad tag)" \
  "$([ "$BLOCK_COUNT" = "3" ] && echo 0 || echo 1)"

# Each emitted block contains the four required prefixes.
HAS_TITLE=$(printf '%s\n' "$RAW_OUT" | grep -c '^title:' || true)
HAS_TAG=$(printf '%s\n' "$RAW_OUT" | grep -c '^tag:' || true)
HAS_EVIDENCE=$(printf '%s\n' "$RAW_OUT" | grep -c '^evidence:' || true)
HAS_BODY=$(printf '%s\n' "$RAW_OUT" | grep -c '^body:' || true)
assert "SC-005: every emitted block has title/tag/evidence/body lines" \
  "$([ "$HAS_TITLE" = "3" ] && [ "$HAS_TAG" = "3" ] && [ "$HAS_EVIDENCE" = "3" ] && [ "$HAS_BODY" = "3" ] && echo 0 || echo 1)"

# All emitted tags are in the allowed set.
ALL_TAGS=$(printf '%s\n' "$RAW_OUT" | awk -F': *' '/^tag:/ { print $2 }')
TAG_OK=0
while IFS= read -r t; do
  case "$t" in
    gap|opportunity|adjacency|non-goal-revisit) ;;
    "") ;;
    *) TAG_OK=1 ;;
  esac
done <<<"$ALL_TAGS"
assert "SC-005: every emitted tag is in {gap, opportunity, adjacency, non-goal-revisit}" "$TAG_OK"

# All evidence cites are non-empty.
EV_EMPTY=$(printf '%s\n' "$RAW_OUT" | awk -F': *' '/^evidence:/ { if (length($2) == 0) print "EMPTY" }' | wc -l | tr -d ' ')
assert "SC-005: every evidence line is non-empty" \
  "$([ "$EV_EMPTY" = "0" ] && echo 0 || echo 1)"

# ---- SC-005: ≤5 cap ----
# Build a fixture with 7 valid blocks; assert only 5 emitted.
cat > "$MOCK/forward-pass.txt" <<'EOF'
title: B1
tag: gap
evidence: a.md
body: b1

title: B2
tag: gap
evidence: a.md
body: b2

title: B3
tag: gap
evidence: a.md
body: b3

title: B4
tag: gap
evidence: a.md
body: b4

title: B5
tag: gap
evidence: a.md
body: b5

title: B6
tag: gap
evidence: a.md
body: b6

title: B7
tag: gap
evidence: a.md
body: b7
EOF

CAP_OUT=$(bash "$FORWARD")
CAP_COUNT=$(printf '%s\n' "$CAP_OUT" | grep -c '^title:' || true)
assert "SC-005: ≤5 suggestions cap enforced (7 in, 5 out)" \
  "$([ "$CAP_COUNT" = "5" ] && echo 0 || echo 1)"

# ---- T020: vision-forward-decision routing ----
SAMPLE_BLOCK=$'title: Sample\ntag: gap\nevidence: foo.md\nbody: sample body'

CHOICE_A=$(printf 'a\n' | { echo "$SAMPLE_BLOCK"; cat; } | bash "$DECISION" 2>/dev/null)
assert "FR-012: decision 'a' → accept" "$([ "$CHOICE_A" = "accept" ] && echo 0 || echo 1)"

CHOICE_D=$(printf 'd\n' | { echo "$SAMPLE_BLOCK"; cat; } | bash "$DECISION" 2>/dev/null)
assert "FR-012: decision 'd' → decline" "$([ "$CHOICE_D" = "decline" ] && echo 0 || echo 1)"

CHOICE_S=$(printf 's\n' | { echo "$SAMPLE_BLOCK"; cat; } | bash "$DECISION" 2>/dev/null)
assert "FR-012: decision 's' → skip" "$([ "$CHOICE_S" = "skip" ] && echo 0 || echo 1)"

# Default-empty input → skip (confirm-never-silent).
CHOICE_DEFAULT=$(printf '\n' | { echo "$SAMPLE_BLOCK"; cat; } | bash "$DECISION" 2>/dev/null)
assert "FR-012: empty input → skip (confirm-never-silent default)" \
  "$([ "$CHOICE_DEFAULT" = "skip" ] && echo 0 || echo 1)"

# ---- T021: vision-forward-decline-write ----
WRITE_OUT=$(bash "$DECLINE_WRITE" "Vision drift detector" "gap" "Body text" ".kiln/vision.md")
WRITE_PATH=$(printf '%s' "$WRITE_OUT" | sed -E 's/^declined: //')
assert "FR-013: decline-write returns a 'declined: <path>' line" \
  "$(printf '%s' "$WRITE_OUT" | grep -q '^declined: ' && echo 0 || echo 1)"

assert "FR-022: declined-record lives under .kiln/roadmap/items/declined/" \
  "$([ -f "$WRITE_PATH" ] && echo "$WRITE_PATH" | grep -q '\.kiln/roadmap/items/declined/' && echo 0 || echo 1)"

# Filename matches the convention <date>-<slug>-considered-and-declined.md
WRITE_BASE=$(basename "$WRITE_PATH")
assert "FR-022: filename follows <date>-<slug>-considered-and-declined.md" \
  "$(printf '%s' "$WRITE_BASE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-.+-considered-and-declined\.md$' && echo 0 || echo 1)"

# Frontmatter contains kind: non-goal + state: declined.
HAS_NG=$(grep -c '^kind: non-goal$' "$WRITE_PATH" || true)
HAS_DEC=$(grep -c '^state: declined$' "$WRITE_PATH" || true)
assert "FR-013: frontmatter has kind: non-goal + state: declined" \
  "$([ "$HAS_NG" = "1" ] && [ "$HAS_DEC" = "1" ] && echo 0 || echo 1)"

# Slug-collision retry: write the same suggestion AGAIN; expect a -1 suffix.
WRITE2_OUT=$(bash "$DECLINE_WRITE" "Vision drift detector" "gap" "Body text 2" ".kiln/vision.md")
WRITE2_PATH=$(printf '%s' "$WRITE2_OUT" | sed -E 's/^declined: //')
assert "FR-022: slug-collision retry produces a -1 suffix" \
  "$(printf '%s' "$WRITE2_PATH" | grep -q -- '-1\.md$' && echo 0 || echo 1)"

# ---- T018: dedup-load reads declined dir ----
DEDUP_OUT=$(bash "$DEDUP_LOAD")
# Expected at least one row: title=Vision drift detector, tag=gap.
assert "FR-013: dedup-load lists the declined record (title\ttag)" \
  "$(printf '%s\n' "$DEDUP_OUT" | awk -F'\t' '$1 == "Vision drift detector" && $2 == "gap" { found=1 } END { exit !found }' && echo 0 || echo 1)"

# ---- SC-006: dedup against declined-set across two passes ----
# Forward-pass with --declined-set should drop suggestions matching the index.
cat > "$MOCK/forward-pass.txt" <<'EOF'
title: Vision drift detector
tag: gap
evidence: .kiln/vision.md
body: should be deduped on second pass

title: Brand new suggestion
tag: opportunity
evidence: docs/features/whatever
body: this should still emit
EOF

DEDUP_FILE="$TMP/dedup.tsv"
bash "$DEDUP_LOAD" > "$DEDUP_FILE"

DEDUPED_OUT=$(bash "$FORWARD" --declined-set "$DEDUP_FILE")
DEDUPED_COUNT=$(printf '%s\n' "$DEDUPED_OUT" | grep -c '^title:' || true)
assert "SC-006: dedup against declined-set drops the previously-declined suggestion" \
  "$([ "$DEDUPED_COUNT" = "1" ] && echo 0 || echo 1)"

# The remaining title is the new one, NOT the declined one.
SURVIVOR=$(printf '%s\n' "$DEDUPED_OUT" | awk -F': *' '/^title:/ { print $2 }' | head -1)
assert "SC-006: surviving suggestion is the brand-new one (not the declined)" \
  "$([ "$SURVIVOR" = "Brand new suggestion" ] && echo 0 || echo 1)"

# ---- Mock missing fixture path → exit 0 with empty output ----
unset KILN_TEST_MOCK_LLM_DIR
export KILN_TEST_MOCK_LLM_DIR="$TMP/no-such-dir"
EMPTY_OUT=$(bash "$FORWARD" || true)
assert "Edge case: missing mock fixture → empty stdout, exit 0" \
  "$([ -z "$EMPTY_OUT" ] && echo 0 || echo 1)"

# ---- Summary ----
echo
echo "PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "FAIL: vision-forward-pass"
  exit 1
fi
echo "PASS: vision-forward-pass ($PASS_COUNT assertions)"
exit 0
