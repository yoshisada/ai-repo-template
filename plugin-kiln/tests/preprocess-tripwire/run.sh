#!/usr/bin/env bash
# T043 — preprocess-tripwire: FR-F4-5 narrowed-pattern tripwire fires at
# preprocess time, no state file is created, error text matches verbatim.
#
# Strategy: build a workflow whose agent .instruction contains a malformed
# token like `${WHEEL_PLUGIN_some.dotted.name}`. The token has a dot, so:
#   1. resolve.sh's token-discovery scan (strict `[a-zA-Z0-9_-]+` grammar)
#      does NOT match it — the resolver sees no unknown token and passes.
#   2. preprocess.sh's substitution regex (same strict grammar) does NOT
#      substitute — the literal token survives the substitute stage.
#   3. preprocess.sh's narrowed-pattern tripwire (`\${(WHEEL_PLUGIN_|`
#      `WORKFLOW_PLUGIN_DIR)`) DOES match the prefix and fires.
#
# This proves the preprocessor's tripwire is the genuine last line of
# defense for FR-F4-5: it catches residual tokens the resolver couldn't
# see through the strict grammar gate.
#
# Asserts:
#   (a) validate-workflow.sh exits non-zero
#   (b) the documented FR-F4-5 error text appears on stderr (verbatim)
#   (c) NO state file is created (preprocess fires BEFORE state_init in
#       post-tool-use.sh; validate-workflow.sh's preflight short-circuits
#       earlier but the activation path is the contractual checkpoint).
#       For this fixture we exercise the activation path via the hook by
#       simulating an activate.sh tool_input.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
PLUGIN_DIR="${REPO_ROOT}/plugin-wheel"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS: $1"; }
nok() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/preprocess-tripwire-XXXXXX")
trap 'rm -rf "$TMP"' EXIT

mkdir -p "${TMP}/.wheel" "${TMP}/workflows"

# Workflow: an agent step whose instruction holds a malformed plugin token.
# Note: we deliberately leave requires_plugins ABSENT so the resolver's
# token-discovery scan finds zero matches (strict grammar) and passes. The
# preprocessor's narrowed-pattern tripwire is the lone gate.
cat >"${TMP}/workflows/needs-tripwire.json" <<'EOF'
{
  "name": "needs-tripwire",
  "steps": [
    {
      "id": "trip-step",
      "type": "agent",
      "instruction": "Run ${WHEEL_PLUGIN_some.dotted.name}/scripts/foo.sh and report."
    }
  ]
}
EOF

# Drive the activation path via the post-tool-use.sh hook. Simulate the
# hook input shape that the harness sends when activate.sh runs from a
# Bash tool call.
HOOK_INPUT=$(python3 -c "import json, sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command':'bash ' + sys.argv[1] + '/bin/activate.sh needs-tripwire'},'session_id':'tripwire-fixture-session','agent_id':'tripwire-fixture-agent','tool_output':{'exit_code':0}}))" "$PLUGIN_DIR")

stderr_capture="${TMP}/stderr"
log_capture="${TMP}/log"
preexisting=$(find "${TMP}/.wheel" -name 'state_*.json' 2>/dev/null | wc -l | tr -d ' ')

# Run the hook from inside the temp dir so .wheel/ resolves to TMP.
( cd "$TMP" && \
  printf '%s' "$HOOK_INPUT" | \
  bash "${PLUGIN_DIR}/hooks/post-tool-use.sh" >"$log_capture" 2>"$stderr_capture" ) || true

# (c) NO state file created — the preprocess tripwire fires BEFORE state_init
# in post-tool-use.sh's activation block (T041 guard).
postcount=$(find "${TMP}/.wheel" -name 'state_*.json' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$postcount" == "$preexisting" ]]; then
  ok "(c) no state file created — preprocess tripwire blocked state_init"
else
  nok "(c) state file created despite preprocess tripwire (count went $preexisting → $postcount)"
fi

# Now verify the tripwire path directly via template_workflow_json — the
# hook may swallow stderr when state file isn't created, but the contractual
# error string lives in preprocess.sh::template_workflow_json. Exercising
# that function with an empty registry (since requires_plugins is absent)
# gives us the exact FR-F4-5 string.
set +u
source "${PLUGIN_DIR}/lib/preprocess.sh"
set -u
WF_JSON=$(jq -c '.' "${TMP}/workflows/needs-tripwire.json")
EMPTY_REGISTRY=$(jq -nc '{schema_version:1,plugins:{}}')
direct_stderr="${TMP}/direct_stderr"
direct_rc=0
template_workflow_json "$WF_JSON" "$EMPTY_REGISTRY" "$TMP" >/dev/null 2>"$direct_stderr" || direct_rc=$?

# (a) preprocess returns non-zero on tripwire
if [[ "$direct_rc" -ne 0 ]]; then
  ok "(a) template_workflow_json exited non-zero ($direct_rc) on residual token"
else
  nok "(a) expected non-zero exit from template_workflow_json, got $direct_rc"
fi

# (b) documented FR-F4-5 error text — verbatim, including step id
expected="Wheel preprocessor failed: instruction text for step 'trip-step' still contains '\${...}'. This is a wheel runtime bug; please file an issue."
if grep -qF "$expected" "$direct_stderr"; then
  ok "(b) documented FR-F4-5 error text emitted verbatim with step id"
else
  nok "(b) FR-F4-5 error text not found; stderr was: $(cat "$direct_stderr")"
fi

echo
echo "preprocess-tripwire: $pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
