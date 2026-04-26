#!/usr/bin/env bash
# T014 / SC-002 / FR-005 / FR-007 / contracts §5 — distill propagation fixture.
# Asserts the canonical jq expression from contracts §5 produces:
#   1. union-merged empirical_quality[] (deduplicated by metric+direction)
#   2. ASC sort by metric, ties on direction
#   3. priority promotion (any primary → primary)
#   4. verbatim scalar-key propagation
# Substrate: tier-2 (run.sh-only). Mock the distill SKILL.md by invoking the
# canonical jq expression directly against fixture source-frontmatter JSONs.
#
# Invoke: bash plugin-kiln/tests/distill-research-block-propagation/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PARSER="$REPO_ROOT/plugin-kiln/scripts/research/parse-research-block.sh"

[[ -x "$PARSER" ]] || { echo "FAIL: parser missing"; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Fixture: two items with distinct axes (tokens + time).
cat > "$TMP/item-a.md" <<'EOF'
---
id: 2026-04-25-item-a
needs_research: true
empirical_quality: [{metric: tokens, direction: lower, priority: primary}]
fixture_corpus: declared
fixture_corpus_path: fixtures/corpus/
---
EOF
cat > "$TMP/item-b.md" <<'EOF'
---
id: 2026-04-25-item-b
needs_research: true
empirical_quality: [{metric: time, direction: lower, priority: secondary}]
---
EOF
cat > "$TMP/item-c.md" <<'EOF'
---
id: 2026-04-25-item-c
empirical_quality: [{metric: tokens, direction: lower, priority: primary}]
---
EOF

PROJ_A=$(bash "$PARSER" "$TMP/item-a.md")
PROJ_B=$(bash "$PARSER" "$TMP/item-b.md")
PROJ_C=$(bash "$PARSER" "$TMP/item-c.md")

SOURCES=$(printf '%s\n%s\n%s\n' "$PROJ_A" "$PROJ_B" "$PROJ_C" | jq -s -c '.')

# Canonical jq expression from contracts §5
MERGED_AXES=$(jq -c '
  [.[] | (.empirical_quality // []) | .[]]
  | group_by(.metric + ":" + .direction)
  | map({
      metric: .[0].metric,
      direction: .[0].direction,
      priority: (
        if any(.priority == "primary") then "primary" else "secondary" end
      )
    })
  | sort_by(.metric, .direction)
' <<<"$SOURCES")

PASS=0
FAIL=0
assert() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"
  else          FAIL=$((FAIL+1)); printf '  FAIL  %s\n  result: %s\n' "$name" "$MERGED_AXES"
  fi
}

# 1. tokens deduplicated to one entry (a + c both declare it)
assert "tokens deduped to one entry" \
  bash -c "echo '$MERGED_AXES' | jq -e '[.[] | select(.metric == \"tokens\")] | length == 1' >/dev/null"

# 2. time present (from item-b)
assert "time axis propagated" \
  bash -c "echo '$MERGED_AXES' | jq -e '[.[] | select(.metric == \"time\")] | length == 1' >/dev/null"

# 3. ASC sort by metric: time < tokens
assert "sorted ASC by metric (time, tokens)" \
  bash -c "echo '$MERGED_AXES' | jq -e '[.[].metric] == [\"time\", \"tokens\"]' >/dev/null"

# 4. tokens priority is primary (item-a + item-c both primary)
assert "tokens priority promoted/preserved primary" \
  bash -c "echo '$MERGED_AXES' | jq -e '[.[] | select(.metric == \"tokens\")][0].priority == \"primary\"' >/dev/null"

# 5. time priority is secondary (only item-b declares, secondary)
assert "time priority secondary (no promotion)" \
  bash -c "echo '$MERGED_AXES' | jq -e '[.[] | select(.metric == \"time\")][0].priority == \"secondary\"' >/dev/null"

# 6. fixture_corpus propagates verbatim from item-a
FIXTURE_CORPUS=$(jq -r 'map(.fixture_corpus) | map(select(. != null)) | first' <<<"$SOURCES")
assert "fixture_corpus: declared propagated verbatim" \
  bash -c "[ '$FIXTURE_CORPUS' = 'declared' ]"

# 7. needs_research: true (any source declares)
NR=$(jq -r 'any(.needs_research == true)' <<<"$SOURCES")
assert "needs_research: true (any source)" \
  bash -c "[ '$NR' = 'true' ]"

TOTAL=$((PASS + FAIL))
echo
if [[ $FAIL -eq 0 ]]; then
  echo "PASS: $PASS/$TOTAL assertions"; exit 0
else
  echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1
fi
