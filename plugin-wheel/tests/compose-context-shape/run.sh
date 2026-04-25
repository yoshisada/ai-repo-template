#!/usr/bin/env bash
# SC-3 fixture — compose-context.sh emits valid JSON shape per contracts §2.
# Also asserts NFR-6 determinism (re-invocation byte-identical).
#
# Substrate hierarchy tier-2: invoke directly via `bash`, exit code + PASS summary.

set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
COMPOSER="${REPO_ROOT}/plugin-wheel/scripts/agents/compose-context.sh"
COORD_PROTO="${REPO_ROOT}/plugin-kiln/agents/_shared/coordination-protocol.md"

[[ ! -x "$COMPOSER" ]] && { echo "FAIL: composer not executable at $COMPOSER" >&2; exit 1; }

# Cross-track dep stub (Theme B owns _shared/coordination-protocol.md). If Theme B has
# shipped the real file, leave it; otherwise stub for this fixture run and clean up.
CREATED_COORD=0
if [[ ! -f "$COORD_PROTO" ]]; then
  mkdir -p "$(dirname "$COORD_PROTO")"
  cat > "$COORD_PROTO" <<'EOF'
[fixture stub — Theme B authors the real coordination-protocol body]
Plain-text output is invisible — relay via SendMessage.
EOF
  CREATED_COORD=1
fi
cleanup() {
  if (( CREATED_COORD == 1 )); then
    rm -f "$COORD_PROTO"
    rmdir "$(dirname "$COORD_PROTO")" 2>/dev/null || true
  fi
  rm -f /tmp/compose-shape-spec.$$.json /tmp/compose-shape-out1.$$.json /tmp/compose-shape-out2.$$.json
}
trap cleanup EXIT

# Build a sample task_spec.
SPEC=/tmp/compose-shape-spec.$$.json
cat > "$SPEC" <<'EOF'
{
  "task_shape": "skill",
  "task_summary": "Compare baseline vs candidate plugin against fixture-001",
  "variables": {
    "PLUGIN_DIR_UNDER_TEST": "/path/to/candidate",
    "FIXTURE_ID": "fixture-001",
    "AXES": "accuracy,input_tokens"
  },
  "axes": ["accuracy", "input_tokens"]
}
EOF

export WORKFLOW_PLUGIN_DIR="${REPO_ROOT}/plugin-kiln"

OUT1=/tmp/compose-shape-out1.$$.json
OUT2=/tmp/compose-shape-out2.$$.json

bash "$COMPOSER" \
  --agent-name research-runner \
  --plugin-id kiln \
  --task-spec "$SPEC" > "$OUT1"

# Acceptance Scenario 1 (SC-3): output is JSON with required keys.
SUBAGENT="$(jq -r .subagent_type "$OUT1")"
PREFIX="$(jq -r .prompt_prefix "$OUT1")"
MODEL="$(jq -r .model_default "$OUT1")"

[[ "$SUBAGENT" == "kiln:research-runner" ]] || { echo "FAIL: subagent_type='$SUBAGENT' (want kiln:research-runner)" >&2; exit 1; }
[[ -n "$PREFIX" ]] || { echo "FAIL: prompt_prefix is empty" >&2; exit 1; }

# I-A5 invariant: subagent_type is plugin-prefixed, never bare/general-purpose.
[[ "$SUBAGENT" == *":"* ]] || { echo "FAIL: subagent_type not plugin-prefixed: $SUBAGENT" >&2; exit 1; }
[[ "$SUBAGENT" != "general-purpose" ]] || { echo "FAIL: subagent_type='general-purpose' violates I-A5" >&2; exit 1; }

# prompt_prefix contains all required sections.
echo "$PREFIX" | grep -qF '## Runtime Environment' || { echo "FAIL: prefix missing '## Runtime Environment'" >&2; exit 1; }
echo "$PREFIX" | grep -qF "WORKFLOW_PLUGIN_DIR=${WORKFLOW_PLUGIN_DIR}" || { echo "FAIL: prefix missing WORKFLOW_PLUGIN_DIR line" >&2; exit 1; }
echo "$PREFIX" | grep -qF '### Task' || { echo "FAIL: prefix missing '### Task'" >&2; exit 1; }
echo "$PREFIX" | grep -qF -- '- task_shape: skill' || { echo "FAIL: prefix missing task_shape" >&2; exit 1; }
echo "$PREFIX" | grep -qF '### Variables' || { echo "FAIL: prefix missing '### Variables'" >&2; exit 1; }
echo "$PREFIX" | grep -qF '### Verbs' || { echo "FAIL: prefix missing '### Verbs'" >&2; exit 1; }
echo "$PREFIX" | grep -qF '### Axes' || { echo "FAIL: prefix missing '### Axes'" >&2; exit 1; }
echo "$PREFIX" | grep -qF '### Task Shape: skill' || { echo "FAIL: prefix missing task-shape stanza heading" >&2; exit 1; }
echo "$PREFIX" | grep -qF '### Coordination Protocol' || { echo "FAIL: prefix missing coordination-protocol stanza" >&2; exit 1; }

# Determinism (NFR-6): re-invocation byte-identical.
bash "$COMPOSER" \
  --agent-name research-runner \
  --plugin-id kiln \
  --task-spec "$SPEC" > "$OUT2"

if ! diff -q "$OUT1" "$OUT2" >/dev/null; then
  echo "FAIL: composer non-deterministic (NFR-6 violation)" >&2
  diff "$OUT1" "$OUT2" >&2
  exit 1
fi

# Variable + verb sorting (LC_ALL=C). Variables in alpha order.
# Extract just the lines between '### Variables' and '### Verbs' to be safe.
VAR_LINES="$(awk '/^### Variables$/{flag=1; next} /^### /{flag=0} flag && /^\| / && !/^\| Key/ && !/^\|---/' <<<"$PREFIX")"
EXPECTED_VARS=$'| AXES | accuracy,input_tokens |\n| FIXTURE_ID | fixture-001 |\n| PLUGIN_DIR_UNDER_TEST | /path/to/candidate |'
[[ "$VAR_LINES" == "$EXPECTED_VARS" ]] || { echo "FAIL: variables not sorted as expected"; echo "got:"; echo "$VAR_LINES"; echo "want:"; echo "$EXPECTED_VARS"; exit 1; } >&2

# Variables empty → section omitted.
SPEC_EMPTY=/tmp/compose-shape-spec-empty.$$.json
cat > "$SPEC_EMPTY" <<'EOF'
{ "task_shape": "skill", "task_summary": "no vars no axes" }
EOF
PREFIX_EMPTY="$(bash "$COMPOSER" --agent-name research-runner --plugin-id kiln --task-spec "$SPEC_EMPTY" | jq -r .prompt_prefix)"
if echo "$PREFIX_EMPTY" | grep -qF '### Variables'; then
  echo "FAIL: empty variables should omit '### Variables' section" >&2
  exit 1
fi
if echo "$PREFIX_EMPTY" | grep -qF '### Axes'; then
  echo "FAIL: empty axes should omit '### Axes' section" >&2
  exit 1
fi
rm -f "$SPEC_EMPTY"

# task_shape unknown → exit 2.
SPEC_BAD=/tmp/compose-shape-spec-bad.$$.json
cat > "$SPEC_BAD" <<'EOF'
{ "task_shape": "not-a-real-shape", "task_summary": "x" }
EOF
set +e
bash "$COMPOSER" --agent-name research-runner --plugin-id kiln --task-spec "$SPEC_BAD" >/dev/null 2>/tmp/compose-shape-err.$$
rc=$?
set -e
[[ $rc -eq 2 ]] || { echo "FAIL: unknown task_shape exit code = $rc (want 2)" >&2; cat /tmp/compose-shape-err.$$ >&2; exit 1; }
rm -f "$SPEC_BAD" /tmp/compose-shape-err.$$

# WORKFLOW_PLUGIN_DIR unset → exit 6.
set +e
WORKFLOW_PLUGIN_DIR="" bash "$COMPOSER" --agent-name research-runner --plugin-id kiln --task-spec "$SPEC" >/dev/null 2>/tmp/compose-shape-err.$$
rc=$?
set -e
[[ $rc -eq 6 ]] || { echo "FAIL: WORKFLOW_PLUGIN_DIR unset exit = $rc (want 6)" >&2; exit 1; }
rm -f /tmp/compose-shape-err.$$

# Unknown agent → exit 3.
set +e
bash "$COMPOSER" --agent-name not-a-declared-agent --plugin-id kiln --task-spec "$SPEC" >/dev/null 2>/tmp/compose-shape-err.$$
rc=$?
set -e
[[ $rc -eq 3 ]] || { echo "FAIL: unknown agent exit = $rc (want 3)" >&2; exit 1; }
rm -f /tmp/compose-shape-err.$$

echo "PASS: compose-context-shape — JSON shape, sorting, determinism, exit codes 2/3/6 all OK"
