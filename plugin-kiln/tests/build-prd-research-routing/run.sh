#!/usr/bin/env bash
# T015 / SC-003 / FR-009 / FR-010 — build-prd research-first routing fixture.
# Asserts the Phase 2.5 skip-path probe correctly identifies a
# `needs_research: true` PRD and would route to the variant pipeline (we
# don't actually run the variant — that's the E2E fixture).
# Substrate: tier-2 (run.sh-only).
#
# Invoke: bash plugin-kiln/tests/build-prd-research-routing/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PRD_PARSER="$REPO_ROOT/plugin-wheel/scripts/harness/parse-prd-frontmatter.sh"

[[ -x "$PRD_PARSER" ]] || { echo "FAIL: prd parser missing"; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Fixture: PRD declaring needs_research: true
cat > "$TMP/prd-research.md" <<'EOF'
---
derived_from:
  - .kiln/roadmap/items/2026-04-25-foo.md
distilled_date: 2026-04-26
theme: research-first-test
needs_research: true
empirical_quality: [{metric: tokens, direction: lower, priority: primary}]
fixture_corpus: declared
fixture_corpus_path: fixtures/corpus/
---
body
EOF

# Fixture: standard PRD (no research)
cat > "$TMP/prd-standard.md" <<'EOF'
---
derived_from:
  - .kiln/issues/2026-04-25-foo.md
distilled_date: 2026-04-26
theme: standard-test
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

# Mock the build-prd Phase 2.5 skip-path probe.
probe() {
  local prd="$1"
  local json
  json=$(bash "$PRD_PARSER" "$prd" 2>/dev/null) || return 2
  local needs
  needs=$(jq -r '.needs_research // false' <<<"$json")
  if [ "$needs" = "true" ]; then
    echo "research-first variant invoked"
    return 0
  else
    return 1  # skip-path returns immediately, no stdout
  fi
}

# 1. Research PRD → variant invoked.
out=$(probe "$TMP/prd-research.md" 2>&1)
assert "needs_research:true → variant banner" \
  bash -c "[ '$out' = 'research-first variant invoked' ]"

# 2. Standard PRD → no stdout (NFR-002 byte-identity).
out=$(probe "$TMP/prd-standard.md" 2>&1 || true)
assert "no needs_research → no stdout (skip-path)" \
  bash -c "[ -z '$out' ]"

# 3. Research PRD parser-projection includes fixture_corpus_path.
PROJ=$(bash "$PRD_PARSER" "$TMP/prd-research.md")
assert "fixture_corpus_path projected from research PRD" \
  bash -c "echo '$PROJ' | jq -e '.fixture_corpus_path == \"fixtures/corpus/\"' >/dev/null"

# 4. Research PRD projects empirical_quality with tokens axis.
assert "empirical_quality tokens axis projected" \
  bash -c "echo '$PROJ' | jq -e '.empirical_quality[0].metric == \"tokens\"' >/dev/null"

# 5. Standard PRD projects null for new research-block fields.
PROJ_STD=$(bash "$PRD_PARSER" "$TMP/prd-standard.md")
assert "standard PRD: needs_research projected as null" \
  bash -c "echo '$PROJ_STD' | jq -e '.needs_research == null' >/dev/null"

TOTAL=$((PASS + FAIL))
echo
if [[ $FAIL -eq 0 ]]; then
  echo "PASS: $PASS/$TOTAL assertions"; exit 0
else
  echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1
fi
