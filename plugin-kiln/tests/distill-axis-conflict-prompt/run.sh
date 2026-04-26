#!/usr/bin/env bash
# T018 / SC-006 / FR-006 / NFR-004 / contracts §6 — distill conflict-prompt fixture.
# Asserts the conflict-detection jq expression fires when two sources declare
# the same metric with different directions, and the rendered prompt names
# both source paths AND both direction values verbatim.
# Substrate: tier-2 (run.sh-only).
#
# Invoke: bash plugin-kiln/tests/distill-axis-conflict-prompt/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PARSER="$REPO_ROOT/plugin-kiln/scripts/research/parse-research-block.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Two items declaring metric:tokens with DIFFERENT directions.
cat > "$TMP/feedback-foo.md" <<'EOF'
---
needs_research: true
empirical_quality: [{metric: tokens, direction: lower, priority: primary}]
---
EOF
cat > "$TMP/item-bar.md" <<'EOF'
---
needs_research: true
empirical_quality: [{metric: tokens, direction: equal_or_better, priority: primary}]
---
EOF

PROJ_A=$(bash "$PARSER" "$TMP/feedback-foo.md")
PROJ_B=$(bash "$PARSER" "$TMP/item-bar.md")
SOURCES=$(printf '%s\n%s\n' "$PROJ_A" "$PROJ_B" | jq -s -c '.')

# Conflict-detection jq expression from contracts §5.
CONFLICTS=$(jq -c '
  [.[] | (.empirical_quality // []) | .[]]
  | group_by(.metric)
  | map(select((map(.direction) | unique | length) > 1))
' <<<"$SOURCES")

PASS=0
FAIL=0
assert() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"
  else          FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"
  fi
}

# 1. Conflict detected — non-empty result.
assert "conflict detected (non-empty result)" \
  bash -c "echo '$CONFLICTS' | jq -e 'length > 0' >/dev/null"

# 2. Conflict on metric: tokens.
assert "conflict on metric: tokens" \
  bash -c "echo '$CONFLICTS' | jq -e '.[0][0].metric == \"tokens\"' >/dev/null"

# 3. Both directions present.
assert "both 'lower' and 'equal_or_better' present" \
  bash -c "echo '$CONFLICTS' | jq -e '[.[0][].direction] | (index(\"lower\") != null) and (index(\"equal_or_better\") != null)' >/dev/null"

# 4. Render NFR-004 prompt shape and assert it names both directions.
PROMPT="$(cat <<'PROMPT_EOF'
Conflict on direction: tokens
  feedback-foo.md declares direction: lower
  item-bar.md declares direction: equal_or_better
Pick one direction or specify a third.
> _
PROMPT_EOF
)"

assert "prompt names both source paths" \
  bash -c "echo '$PROMPT' | grep -qF 'feedback-foo.md' && echo '$PROMPT' | grep -qF 'item-bar.md'"

assert "prompt names both direction values" \
  bash -c "echo '$PROMPT' | grep -qF 'direction: lower' && echo '$PROMPT' | grep -qF 'direction: equal_or_better'"

assert "prompt ends with 'Pick one direction or specify a third.'" \
  bash -c "echo '$PROMPT' | grep -qF 'Pick one direction or specify a third.'"

# 5. Bad-shape prompt must NOT match (sanity check on NFR-004 invariant).
BAD_PROMPT="axes conflict, please resolve"
assert "rejected: bad shape ('axes conflict, please resolve')" \
  bash -c "[ \"$BAD_PROMPT\" != \"\$(echo '$PROMPT' | tr -d '\n')\" ]"

TOTAL=$((PASS + FAIL))
echo
if [[ $FAIL -eq 0 ]]; then
  echo "PASS: $PASS/$TOTAL assertions"; exit 0
else
  echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1
fi
