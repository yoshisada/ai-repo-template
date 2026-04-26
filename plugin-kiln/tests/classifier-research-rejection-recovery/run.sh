#!/usr/bin/env bash
# T020 / SC-008 / FR-015 / NFR-006 — classifier rejection structural-absence fixture.
# Asserts that a `reject` response in the coached-capture research-block
# question results in NO research-block keys at all in the captured artifact
# (not `needs_research: false`, not empty `empirical_quality: []`).
# Mocks the interview by directly writing the resulting file with NO
# research-block frontmatter.
# Substrate: tier-2 (run.sh-only).
#
# Invoke: bash plugin-kiln/tests/classifier-research-rejection-recovery/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLASSIFIER="$REPO_ROOT/plugin-kiln/scripts/roadmap/classify-description.sh"
PARSER="$REPO_ROOT/plugin-kiln/scripts/research/parse-research-block.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Step 1: classifier infers research_inference for "make this cheaper".
CLS=$(bash "$CLASSIFIER" "make this cheaper")
HAS_INF=$(printf '%s' "$CLS" | jq -r 'has("research_inference")')
if [ "$HAS_INF" != "true" ]; then
  echo "FAIL: classifier did not infer research_inference for cheaper"
  exit 1
fi

# Step 2: simulate maintainer typing "reject" — write the captured item
# with NO research-block keys.
cat > "$TMP/2026-04-25-test.md" <<'EOF'
---
id: 2026-04-25-test
title: Cheaper feature
kind: feature
date: 2026-04-25
status: open
phase: 09-research-first
state: planned
blast_radius: feature
review_cost: moderate
context_cost: cheap
---
body: maintainer rejected the research-block proposal
EOF

PASS=0
FAIL=0
assert() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"
  else          FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"
  fi
}

# Verify NO research-block keys present in the file (structural absence).
for k in needs_research empirical_quality fixture_corpus fixture_corpus_path promote_synthesized excluded_fixtures; do
  assert "structural absence of '$k:' line" \
    bash -c "! grep -qF '$k:' '$TMP/2026-04-25-test.md'"
done

# Verify the parser projection produces all-null for research-block fields
PROJ=$(bash "$PARSER" "$TMP/2026-04-25-test.md")
for k in needs_research empirical_quality fixture_corpus fixture_corpus_path promote_synthesized excluded_fixtures; do
  assert "$k projects as null" \
    bash -c "echo '$PROJ' | jq -e '.$k == null' >/dev/null"
done

# Verify the bad shape (`needs_research: false`) is NOT what we want.
# This is a meta-assertion that confirms the spec's structural-absence
# requirement: `false` is the WRONG recovery shape.
cat > "$TMP/wrong-shape.md" <<'EOF'
---
id: 2026-04-25-wrong
needs_research: false
empirical_quality: []
---
EOF
WRONG_PROJ=$(bash "$PARSER" "$TMP/wrong-shape.md")
assert "WRONG shape detected: needs_research:false present" \
  bash -c "echo '$WRONG_PROJ' | jq -e '.needs_research == false' >/dev/null"
assert "WRONG shape detected: empirical_quality:[] present" \
  bash -c "echo '$WRONG_PROJ' | jq -e '.empirical_quality == []' >/dev/null"

TOTAL=$((PASS + FAIL))
echo
if [[ $FAIL -eq 0 ]]; then
  echo "PASS: $PASS/$TOTAL assertions"; exit 0
else
  echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1
fi
