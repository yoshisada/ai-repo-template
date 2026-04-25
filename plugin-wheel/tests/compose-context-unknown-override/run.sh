#!/usr/bin/env bash
# SC-5 fixture — compose-context.sh exits 5 when PRD agent_binding_overrides references
# an agent not declared in the plugin manifest's agent_bindings.
# Also covers exit 4 for unknown-verb-in-overrides.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
COMPOSER="${REPO_ROOT}/plugin-wheel/scripts/agents/compose-context.sh"
COORD_PROTO="${REPO_ROOT}/plugin-kiln/agents/_shared/coordination-protocol.md"

[[ ! -x "$COMPOSER" ]] && { echo "FAIL: composer not executable" >&2; exit 1; }

# Cross-track stub (Theme B owns the real file).
CREATED_COORD=0
if [[ ! -f "$COORD_PROTO" ]]; then
  mkdir -p "$(dirname "$COORD_PROTO")"
  printf 'fixture stub — relay via SendMessage\n' > "$COORD_PROTO"
  CREATED_COORD=1
fi

TMPDIR="$(mktemp -d -t compose-override.XXXXXX)"
cleanup() {
  rm -rf "$TMPDIR"
  if (( CREATED_COORD == 1 )); then
    rm -f "$COORD_PROTO"
    rmdir "$(dirname "$COORD_PROTO")" 2>/dev/null || true
  fi
}
trap cleanup EXIT

cat > "$TMPDIR/task-spec.json" <<'EOF'
{ "task_shape": "skill", "task_summary": "test override validation" }
EOF

export WORKFLOW_PLUGIN_DIR="${REPO_ROOT}/plugin-kiln"

# Case A — PRD overrides reference an agent NOT in the manifest's agent_bindings.
cat > "$TMPDIR/prd-bad-agent.md" <<'EOF'
---
agent_binding_overrides:
  not-a-declared-agent:
    verbs:
      verify_quality: /kiln:kiln-test --plugin-dir x --fixture y
---

# PRD body
EOF

set +e
bash "$COMPOSER" \
  --agent-name research-runner \
  --plugin-id kiln \
  --task-spec "$TMPDIR/task-spec.json" \
  --prd-path "$TMPDIR/prd-bad-agent.md" >"$TMPDIR/out" 2>"$TMPDIR/err"
rc=$?
set -e

[[ $rc -eq 5 ]] || { echo "FAIL (case A): override unknown-agent exit = $rc (want 5)" >&2; cat "$TMPDIR/err" >&2; exit 1; }
grep -qF "not-a-declared-agent" "$TMPDIR/err" || { echo "FAIL: stderr missing offending agent name" >&2; cat "$TMPDIR/err" >&2; exit 1; }

# Case B — PRD overrides reference a verb NOT in the closed namespace.
cat > "$TMPDIR/prd-bad-verb.md" <<'EOF'
---
agent_binding_overrides:
  research-runner:
    verbs:
      not_a_real_verb: /usr/bin/false
---
EOF

set +e
bash "$COMPOSER" \
  --agent-name research-runner \
  --plugin-id kiln \
  --task-spec "$TMPDIR/task-spec.json" \
  --prd-path "$TMPDIR/prd-bad-verb.md" >"$TMPDIR/out" 2>"$TMPDIR/err"
rc=$?
set -e

[[ $rc -eq 4 ]] || { echo "FAIL (case B): override unknown-verb exit = $rc (want 4)" >&2; cat "$TMPDIR/err" >&2; exit 1; }
grep -qF "not_a_real_verb" "$TMPDIR/err" || { echo "FAIL: stderr missing offending verb name" >&2; cat "$TMPDIR/err" >&2; exit 1; }

# Case C — valid override is applied (override REPLACES the manifest entry for the same verb).
cat > "$TMPDIR/prd-good.md" <<'EOF'
---
agent_binding_overrides:
  research-runner:
    verbs:
      verify_quality: OVERRIDE-WINS
      run_baseline: bash /tmp/baseline.sh
---
EOF

OUT="$(bash "$COMPOSER" \
  --agent-name research-runner \
  --plugin-id kiln \
  --task-spec "$TMPDIR/task-spec.json" \
  --prd-path "$TMPDIR/prd-good.md")"

PREFIX="$(jq -r .prompt_prefix <<<"$OUT")"
echo "$PREFIX" | grep -qF "| verify_quality | OVERRIDE-WINS |" || { echo "FAIL (case C): override did not replace manifest verify_quality" >&2; echo "$PREFIX" | grep -F verify_quality >&2; exit 1; }
echo "$PREFIX" | grep -qF "| run_baseline | bash /tmp/baseline.sh |" || { echo "FAIL (case C): override did not add run_baseline" >&2; exit 1; }
# Manifest's `measure` should still be present (override doesn't drop unmentioned verbs).
echo "$PREFIX" | grep -qF "| measure |" || { echo "FAIL (case C): manifest 'measure' was dropped" >&2; exit 1; }

echo "PASS: compose-context-unknown-override — exit 5 on unknown-agent, exit 4 on unknown-verb, override+merge semantics correct"
