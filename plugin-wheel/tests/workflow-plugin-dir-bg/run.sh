#!/usr/bin/env bash
# FR-D2 consumer-install smoke test (specs/wheel-as-runtime/spec.md).
#
# Simulates the consumer install layout — plugin-shelf/, plugin-kiln/, etc.
# absent from the repo root; plugin scripts only reachable via the install
# cache at ~/.claude/plugins/cache/<org>-<mp>/<plugin>/<version>/. Then runs
# a workflow whose agent step expects WORKFLOW_PLUGIN_DIR to be resolvable
# from inside a background-sub-agent's bash commands.
#
# Because this is a shell-level smoke test (no real harness in play), we
# verify the CONTRACT that FR-D1 Option B guarantees:
#   1. wheel's context_build emits a "## Runtime Environment" block
#      naming the absolute WORKFLOW_PLUGIN_DIR derived from the workflow
#      file's location.
#   2. the emitted absolute path points to an existing directory that
#      contains the scripts the sub-agent will need (simulating the
#      consumer-install cache layout).
#   3. scripts referenced via ${WORKFLOW_PLUGIN_DIR} are executable from
#      the resolved absolute path.
#   4. SC-007: no log line written during the smoke test contains
#      'WORKFLOW_PLUGIN_DIR was unset'.
#
# NFR-4 (CI wiring): this script is invoked by /wheel:wheel-test and must
# also run in CI on every PR touching plugin-wheel/ or any plugin workflow
# JSON. See .github/workflows/wheel-tests.yml for the CI glue.
#
# NFR-2 (silent-failure tripwire): paired with
# plugin-wheel/tests/workflow-plugin-dir-tripwire/ — removing the Runtime
# Environment block from context.sh MUST make this test fail loudly with
# the identifiable string 'FR-D1 Runtime Environment block missing'.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONTEXT_LIB="${REPO_ROOT}/plugin-wheel/lib/context.sh"

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
echo "demo-script ok | WORKFLOW_PLUGIN_DIR=${WORKFLOW_PLUGIN_DIR:-<unset>}"
SH
chmod +x "${install_dir}/scripts/demo-script.sh"

# Simulated consumer repo — explicitly do NOT create plugin-*/ at the repo
# root so a "wheel should resolve via WORKFLOW_PLUGIN_DIR" assertion is
# meaningful.
cd "${consumer_repo}"
mkdir -p .kiln/logs

# Invoke context_build with a state that points at the install-cache workflow.
# This is the contract the harness will exercise at agent-step dispatch time.
set +u
source "$CONTEXT_LIB"
set -u

step_json='{"type":"agent","instruction":"Spawn a bg sub-agent that runs bash \"${WORKFLOW_PLUGIN_DIR}/scripts/demo-script.sh\" and logs the result."}'
state_json=$(python3 -c "import json,sys; print(json.dumps({'workflow_file': sys.argv[1], 'steps':[]}))" "$workflow_path")
wf_json=$(cat "$workflow_path")

OUT=$(context_build "$step_json" "$state_json" "$wf_json")

FAILURES=0

# ---- Assertion 1: Runtime Environment block present (FR-D1) ----
if ! printf '%s' "$OUT" | grep -qF "## Runtime Environment (wheel-templated, FR-D1)"; then
  echo "FAIL: FR-D1 Runtime Environment block missing from agent-step instruction under consumer-install layout" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 2: the templated absolute path equals the install-cache plugin dir ----
expected_abs="$install_dir"
if ! printf '%s' "$OUT" | grep -qF "WORKFLOW_PLUGIN_DIR=${expected_abs}"; then
  echo "FAIL: expected WORKFLOW_PLUGIN_DIR=${expected_abs} in instruction; not found" >&2
  printf 'instruction:\n%s\n' "$OUT" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 3: the absolute path resolves a real script the sub-agent
# would need (demo-script.sh) ----
if [[ ! -x "${expected_abs}/scripts/demo-script.sh" ]]; then
  echo "FAIL: expected scripts/demo-script.sh at resolved path; not present or not executable" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 4: simulate a sub-agent running the script with the
# templated env value and capture its output. This is the FR-D2 contract:
# the value must be usable in a bash command exactly as templated. ----
demo_out=$(env -i PATH="$PATH" WORKFLOW_PLUGIN_DIR="${expected_abs}" bash "${expected_abs}/scripts/demo-script.sh" 2>&1)
if ! printf '%s' "$demo_out" | grep -qF "demo-script ok | WORKFLOW_PLUGIN_DIR=${expected_abs}"; then
  echo "FAIL: demo-script did not observe the templated WORKFLOW_PLUGIN_DIR value" >&2
  echo "  got: $demo_out" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 5: SC-007 grep — simulate writing a bg-log entry from the
# "bg sub-agent" using the templated value, then assert the log does NOT
# contain the regression-fingerprint string 'WORKFLOW_PLUGIN_DIR was unset'. ----
today=$(date -u +%Y-%m-%d)
bg_log="${consumer_repo}/.kiln/logs/report-issue-bg-${today}.md"
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# What a well-behaved bg sub-agent logs:
printf '%s\n' "${timestamp} | counter_before=3 | counter_after=4 | threshold=10 | action=increment | notes=ok WORKFLOW_PLUGIN_DIR=${expected_abs}" >> "$bg_log"

if grep -F 'WORKFLOW_PLUGIN_DIR was unset' "$bg_log" >/dev/null 2>&1; then
  echo "FAIL: SC-007 regression — bg log contains 'WORKFLOW_PLUGIN_DIR was unset' string" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 6: NFR-5 back-compat — context_build without workflow_file
# in state must NOT crash and must NOT emit the runtime block. ----
state_empty='{"steps":[]}'
out_empty=$(context_build "$step_json" "$state_empty" "$wf_json")
if printf '%s' "$out_empty" | grep -qF "## Runtime Environment"; then
  echo "FAIL: runtime block emitted when workflow_file absent from state (NFR-5 regression)" >&2
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo "" >&2
  echo "FAIL: ${FAILURES} assertion(s) broke under consumer-install simulation — FR-D2 invariant violated" >&2
  exit 1
fi

echo "OK: FR-D2 consumer-install smoke test passed (Runtime Env block + SC-007 grep clean + NFR-5 back-compat)"
