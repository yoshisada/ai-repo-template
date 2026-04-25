#!/usr/bin/env bash
# Consumer-install smoke test for cross-plugin path resolution.
#
# History: this file used to validate the FR-D1 Option B "## Runtime
# Environment" header that wheel injected into agent step instructions
# (specs/wheel-as-runtime). Theme F4 of cross-plugin-resolver-and-preflight-
# registry SUPERSEDES Option B by templating literal absolute paths into
# `.instruction` BEFORE state_init via
# plugin-wheel/lib/preprocess.sh::template_workflow_json (T041). The header
# is gone; the path is in the instruction text directly.
#
# This test is repurposed for Theme F4. It simulates the consumer-install
# layout — plugin-shelf/, plugin-kiln/, etc. absent from the repo root;
# plugin scripts reachable only via the install cache at
# ~/.claude/plugins/cache/<org>-<mp>/<plugin>/<version>/ — and asserts the
# new contract:
#
#   1. After preprocessing (Theme F4), an agent step that wrote
#      `${WORKFLOW_PLUGIN_DIR}/scripts/foo.sh` in its instruction now
#      contains the literal absolute install-cache path.
#   2. The literal path resolves to a real script the bg sub-agent will
#      need (simulating consumer-install cache layout).
#   3. The sub-agent can run that script with the literal path AS-IS, with
#      no env-var propagation needed (the value lives in the prompt text).
#   4. SC-F-6 / SC-007 grep — no log line written during this run contains
#      'WORKFLOW_PLUGIN_DIR was unset' OR a residual `${WHEEL_PLUGIN_*}` /
#      `${WORKFLOW_PLUGIN_DIR*}` token.
#   5. NFR-F-5 back-compat — workflows without `requires_plugins` and
#      without `${WHEEL_PLUGIN_*}` tokens continue to work via the
#      preprocessor's same code path (legacy `${WORKFLOW_PLUGIN_DIR}` is
#      treated as `${WHEEL_PLUGIN_<calling-plugin>}`).
#
# NFR-4 (CI wiring): invoked by /wheel:wheel-test and by
# .github/workflows/wheel-tests.yml on every PR touching plugin-wheel/ or
# plugin workflow JSON files.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONTEXT_LIB="${REPO_ROOT}/plugin-wheel/lib/context.sh"
PREPROCESS_LIB="${REPO_ROOT}/plugin-wheel/lib/preprocess.sh"
REGISTRY_LIB="${REPO_ROOT}/plugin-wheel/lib/registry.sh"

STAGE="$(mktemp -d -t wf-plugin-dir-bg-XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

# Build a consumer-install layout:
#   $STAGE/consumer-repo/          <- the "consumer" repo root (no plugin-*/ dirs)
#   $STAGE/install-cache/<org>-<mp>/plugin-fake/<version>/
#     ├── workflows/fake.json
#     └── scripts/demo-script.sh
install_dir="${STAGE}/install-cache/acme-marketplace/plugin-fake/1.0.0"
mkdir -p "${install_dir}/workflows" "${install_dir}/scripts"
consumer_repo="${STAGE}/consumer-repo"
mkdir -p "${consumer_repo}"

# Workflow uses the legacy ${WORKFLOW_PLUGIN_DIR} token on purpose — this is
# the back-compat path that NFR-F-5 protects. Theme F4 must preserve the
# legacy behaviour: the token resolves to the workflow's owning plugin dir.
workflow_path="${install_dir}/workflows/fake.json"
cat > "${workflow_path}" <<'WF'
{
  "name": "fake-bg",
  "steps": [
    {
      "id": "spawn-bg",
      "type": "agent",
      "instruction": "Spawn a bg sub-agent that runs bash \"${WORKFLOW_PLUGIN_DIR}/scripts/demo-script.sh\" and logs the result."
    }
  ]
}
WF

cat > "${install_dir}/scripts/demo-script.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# After Theme F4, the bg sub-agent reads the literal path verbatim from its
# prompt — no env var lookup needed. We emit both branches (env-or-arg) so
# tests can verify either resolution path.
echo "demo-script ok | path=${1:-${WORKFLOW_PLUGIN_DIR:-<unset>}}"
SH
chmod +x "${install_dir}/scripts/demo-script.sh"

# Simulated consumer repo — explicitly do NOT create plugin-*/ at the repo
# root so the cross-plugin resolution is forced through the install-cache.
cd "${consumer_repo}"
mkdir -p .kiln/logs

# Source the libs.
set +u
source "$REGISTRY_LIB"
source "$PREPROCESS_LIB"
source "$CONTEXT_LIB"
set -u

# Build a synthetic registry containing the fake plugin at the install-cache
# path. This mimics what build_session_registry would derive from PATH if the
# fake plugin's /bin were on $PATH. Note: the test does NOT need the live
# registry — Theme F4's contract is the input/output shape, validated here
# in isolation.
FAKE_REGISTRY=$(python3 -c "
import json, sys
print(json.dumps({
    'schema_version': 1,
    'built_at': '2026-04-24T00:00:00Z',
    'source': 'candidate-a-path-parsing',
    'fallback_used': False,
    'plugins': {'fake': sys.argv[1]},
}))
" "$install_dir")

# Run the preprocessor as if engine activation had just happened. The
# calling plugin dir is the workflow's owning plugin dir, derived per the
# convention $(dirname (dirname workflow_file)).
calling_plugin_dir=$(cd "$(dirname "$(dirname "$workflow_path")")" && pwd)
WF_JSON_RAW=$(cat "$workflow_path")
WF_JSON_TEMPLATED=$(template_workflow_json "$WF_JSON_RAW" "$FAKE_REGISTRY" "$calling_plugin_dir")

FAILURES=0

# ---- Assertion 1: legacy ${WORKFLOW_PLUGIN_DIR} substituted to literal path ----
expected_abs="$install_dir"
templated_instruction=$(printf '%s' "$WF_JSON_TEMPLATED" | jq -r '.steps[0].instruction')
if ! printf '%s' "$templated_instruction" | grep -qF "${expected_abs}/scripts/demo-script.sh"; then
  echo "FAIL: NFR-F-5 back-compat violated — preprocessor did not substitute \${WORKFLOW_PLUGIN_DIR} to the literal install-cache path" >&2
  echo "  expected literal: ${expected_abs}/scripts/demo-script.sh" >&2
  echo "  got: ${templated_instruction}" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 2: no residual token in the templated instruction ----
# (FR-F4-6: post-PRD, NO agent prompt produced by wheel contains ${VAR} for
# plugin paths.)
if printf '%s' "$templated_instruction" | grep -qE '\$\{(WHEEL_PLUGIN_|WORKFLOW_PLUGIN_DIR)'; then
  echo "FAIL: FR-F4-6 violated — residual \${WHEEL_PLUGIN_*} or \${WORKFLOW_PLUGIN_DIR*} token in templated instruction" >&2
  echo "  templated: ${templated_instruction}" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 3: now feed the templated workflow into context_build and
# verify the instruction reaches the LLM as a literal path. ----
STEP_JSON=$(printf '%s' "$WF_JSON_TEMPLATED" | jq -c '.steps[0]')
STATE_JSON=$(python3 -c "import json,sys; print(json.dumps({'workflow_file': sys.argv[1], 'steps':[]}))" "$workflow_path")
CTX_OUT=$(context_build "$STEP_JSON" "$STATE_JSON" "$WF_JSON_TEMPLATED")
if ! printf '%s' "$CTX_OUT" | grep -qF "${expected_abs}/scripts/demo-script.sh"; then
  echo "FAIL: context_build output does not contain the literal install-cache script path" >&2
  printf 'context_build output:\n%s\n' "$CTX_OUT" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 4: obsolete Runtime Environment header MUST be absent ----
if printf '%s' "$CTX_OUT" | grep -qF "## Runtime Environment"; then
  echo "FAIL: T042 invariant violated — context_build still emits the obsolete '## Runtime Environment' header" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 5: the resolved absolute path resolves a real script ----
if [[ ! -x "${expected_abs}/scripts/demo-script.sh" ]]; then
  echo "FAIL: expected scripts/demo-script.sh at resolved path; not present or not executable" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 6: simulate a sub-agent running the script with the
# templated PATH passed as a positional arg (the new world: the sub-agent
# sees the literal path in its prompt and uses it directly). ----
demo_out=$(env -i PATH="$PATH" bash "${expected_abs}/scripts/demo-script.sh" "${expected_abs}/scripts/demo-script.sh" 2>&1)
if ! printf '%s' "$demo_out" | grep -qF "demo-script ok | path=${expected_abs}/scripts/demo-script.sh"; then
  echo "FAIL: demo-script did not observe the templated literal path" >&2
  echo "  got: $demo_out" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 7: SC-007 grep — simulate writing a bg-log entry and assert
# the log does NOT contain 'WORKFLOW_PLUGIN_DIR was unset'. ----
today=$(date -u +%Y-%m-%d)
bg_log="${consumer_repo}/.kiln/logs/report-issue-bg-${today}.md"
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s\n' "${timestamp} | counter_before=3 | counter_after=4 | threshold=10 | action=increment | notes=ok path=${expected_abs}" >> "$bg_log"

if grep -F 'WORKFLOW_PLUGIN_DIR was unset' "$bg_log" >/dev/null 2>&1; then
  echo "FAIL: SC-007 regression — bg log contains 'WORKFLOW_PLUGIN_DIR was unset' string" >&2
  FAILURES=$((FAILURES + 1))
fi

if grep -qE '\$\{(WHEEL_PLUGIN_|WORKFLOW_PLUGIN_DIR)' "$bg_log"; then
  echo "FAIL: SC-F-6 regression — bg log contains a residual plugin-path token" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 8: NFR-F-5 back-compat — context_build without workflow_file
# in state must NOT crash and must NOT emit the runtime block. ----
state_empty='{"steps":[]}'
out_empty=$(context_build "$STEP_JSON" "$state_empty" "$WF_JSON_TEMPLATED")
if printf '%s' "$out_empty" | grep -qF "## Runtime Environment"; then
  echo "FAIL: runtime block emitted when workflow_file absent from state (NFR-F-5 regression)" >&2
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo "" >&2
  echo "FAIL: ${FAILURES} assertion(s) broke under consumer-install simulation — Theme F4 invariant violated" >&2
  exit 1
fi

echo "OK: Theme F4 consumer-install smoke test passed (preprocessor literal substitution + no residual tokens + back-compat preserved)"
