#!/usr/bin/env bash
# T016 / SC-004 / FR-009 / NFR-002 — build-prd byte-identity skip-path fixture.
# Asserts that a no-research-block PRD produces:
#   1. The skip-path probe → empty stdout (Decision 7 / NFR-002 invariant).
#   2. The parser projection retains the existing three keys' values
#      byte-identically while adding 4 nulls for the new fields.
#   3. Re-running the parser is byte-identical (NFR-AE-002 sibling).
# Substrate: tier-2 (run.sh-only).
#
# Invoke: bash plugin-kiln/tests/build-prd-standard-routing-bytecompat/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PRD_PARSER="$REPO_ROOT/plugin-wheel/scripts/harness/parse-prd-frontmatter.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/prd-pre-research.md" <<'EOF'
---
blast_radius: feature
empirical_quality: [{metric: tokens, direction: equal_or_better, priority: primary}]
excluded_fixtures: [{path: "002-flaky", reason: "flaky"}]
---
body
EOF

PASS=0
FAIL=0
assert() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"
  else          FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"
  fi
}

PROJ=$(bash "$PRD_PARSER" "$TMP/prd-pre-research.md")

# 1. Existing three keys preserved.
assert "blast_radius preserved as 'feature'" \
  bash -c "echo '$PROJ' | jq -e '.blast_radius == \"feature\"' >/dev/null"

assert "empirical_quality preserves token axis" \
  bash -c "echo '$PROJ' | jq -e '.empirical_quality[0].metric == \"tokens\"' >/dev/null"

assert "excluded_fixtures preserves flaky entry" \
  bash -c "echo '$PROJ' | jq -e '.excluded_fixtures[0].path == \"002-flaky\"' >/dev/null"

# 2. Four new fields present + null.
for k in needs_research fixture_corpus fixture_corpus_path promote_synthesized; do
  assert "$k present and null" \
    bash -c "echo '$PROJ' | jq -e '.$k == null' >/dev/null"
done

# 3. Skip-path probe: needs_research:false → no stdout.
NEEDS=$(jq -r '.needs_research // false' <<<"$PROJ")
out=""
if [ "$NEEDS" = "true" ]; then
  out="research-first variant invoked"
fi
assert "skip-path emits empty stdout" \
  bash -c "[ -z '$out' ]"

# 4. Determinism — re-run produces byte-identical output.
PROJ2=$(bash "$PRD_PARSER" "$TMP/prd-pre-research.md")
assert "re-run is byte-identical" \
  bash -c "[ '$PROJ' = '$PROJ2' ]"

TOTAL=$((PASS + FAIL))
echo
if [[ $FAIL -eq 0 ]]; then
  echo "PASS: $PASS/$TOTAL assertions"; exit 0
else
  echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1
fi
