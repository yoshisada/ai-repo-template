#!/usr/bin/env bash
# T019 / SC-007 / NFR-003 / contracts §5 — distill determinism fixture.
# Asserts re-running the canonical merge jq expression on unchanged inputs
# produces byte-identical output.
# Substrate: tier-2 (run.sh-only).
#
# Invoke: bash plugin-kiln/tests/distill-research-block-determinism/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PARSER="$REPO_ROOT/plugin-kiln/scripts/research/parse-research-block.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Conflict-free fixture set with multiple axes.
cat > "$TMP/a.md" <<'EOF'
---
needs_research: true
empirical_quality: [{metric: tokens, direction: lower, priority: primary}]
---
EOF
cat > "$TMP/b.md" <<'EOF'
---
needs_research: true
empirical_quality: [{metric: time, direction: lower, priority: secondary}]
---
EOF
cat > "$TMP/c.md" <<'EOF'
---
empirical_quality: [{metric: cost, direction: lower, priority: secondary}]
---
EOF

run_merge() {
  local sources
  sources=$(for f in "$TMP/a.md" "$TMP/b.md" "$TMP/c.md"; do
    bash "$PARSER" "$f"
  done | jq -s -c '.')
  jq -c '
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
  ' <<<"$sources"
}

R1=$(run_merge)
R2=$(run_merge)
R3=$(run_merge)

PASS=0
FAIL=0

if [ "$R1" = "$R2" ]; then
  PASS=$((PASS+1)); echo "  pass  run1 == run2 (byte-identical)"
else
  FAIL=$((FAIL+1)); echo "  FAIL  run1 != run2 — drift!"
  echo "  R1: $R1"
  echo "  R2: $R2"
fi

if [ "$R2" = "$R3" ]; then
  PASS=$((PASS+1)); echo "  pass  run2 == run3 (byte-identical)"
else
  FAIL=$((FAIL+1)); echo "  FAIL  run2 != run3 — drift!"
fi

# Extract metrics order — should be ASC alphabetical: cost, time, tokens.
METRICS=$(echo "$R1" | jq -r '[.[].metric] | join(",")')
if [ "$METRICS" = "cost,time,tokens" ]; then
  PASS=$((PASS+1)); echo "  pass  metric order ASC alphabetical (cost,time,tokens)"
else
  FAIL=$((FAIL+1)); echo "  FAIL  unexpected metric order: $METRICS"
fi

TOTAL=$((PASS + FAIL))
echo
if [[ $FAIL -eq 0 ]]; then
  echo "PASS: $PASS/$TOTAL assertions"; exit 0
else
  echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1
fi
