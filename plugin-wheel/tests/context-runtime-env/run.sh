#!/usr/bin/env bash
# FR-D1 Option B unit test (specs/wheel-as-runtime/spec.md User Story 2).
#
# Asserts: context_build prepends a "## Runtime Environment (wheel-templated,
# FR-D1)" block that names WORKFLOW_PLUGIN_DIR with the absolute plugin path
# derived from the workflow file. This is the Option B channel — the LLM
# sees the value in its instruction text and propagates it into Bash tool
# calls + nested sub-agent spawns.
#
# NFR-2 (silent-failure tripwire): if a future refactor drops the block OR
# templates an empty value, this test fails with an identifiable error
# string "FR-D1 Runtime Environment block missing".
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONTEXT_LIB="${REPO_ROOT}/plugin-wheel/lib/context.sh"

if [[ ! -f "$CONTEXT_LIB" ]]; then
  echo "FAIL: context.sh missing: $CONTEXT_LIB" >&2
  exit 1
fi

# Build a fake state that points at a workflow file located inside a
# controlled plugin dir. The plugin dir is the parent of the workflows/ dir.
STAGE="$(mktemp -d -t ctx-runtime-env-XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/plugin-fake/workflows"
WF_FILE="$STAGE/plugin-fake/workflows/fake.json"
printf '%s' '{"name":"fake","steps":[]}' > "$WF_FILE"

STEP_JSON='{"type":"agent","instruction":"Do the thing."}'
STATE_JSON=$(python3 -c "import json,sys; print(json.dumps({'workflow_file': sys.argv[1], 'steps':[]}))" "$WF_FILE")
WF_JSON=$(cat "$WF_FILE")

# Source context.sh (and its transitive deps if any — state.sh is only needed
# for context_build's state-file reads which we bypass by passing state_json).
# context.sh uses only jq + pure-bash, so a clean source works.
set +u  # context.sh may touch variables set by callers; lenient for the source
source "$CONTEXT_LIB"
set -u

# Invoke context_build
OUT=$(context_build "$STEP_JSON" "$STATE_JSON" "$WF_JSON")

FAILURES=0

# ---- Assertion 1: Runtime Environment header appears ----
if ! printf '%s' "$OUT" | grep -qF "## Runtime Environment (wheel-templated, FR-D1)"; then
  echo "FAIL: FR-D1 Runtime Environment block missing from context_build output" >&2
  printf 'output head:\n%s\n' "$(printf '%s' "$OUT" | head -c 400)" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 2: absolute value of WORKFLOW_PLUGIN_DIR is embedded ----
expected_abs=$(cd "$STAGE/plugin-fake" && pwd)
if ! printf '%s' "$OUT" | grep -qF "WORKFLOW_PLUGIN_DIR=${expected_abs}"; then
  echo "FAIL: FR-D1 expected 'WORKFLOW_PLUGIN_DIR=${expected_abs}' in output but not found" >&2
  printf 'output:\n%s\n' "$OUT" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 3: instruction block still present downstream of env block ----
if ! printf '%s' "$OUT" | grep -qF "## Step Instruction"; then
  echo "FAIL: Step Instruction header missing — runtime env block suppressed the existing instruction" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 4: env block appears BEFORE instruction block ----
# Use awk to find line numbers and compare
env_line=$(printf '%s\n' "$OUT" | grep -nF "## Runtime Environment" | head -1 | cut -d: -f1)
ins_line=$(printf '%s\n' "$OUT" | grep -nF "## Step Instruction" | head -1 | cut -d: -f1)
if [[ -n "$env_line" && -n "$ins_line" && "$env_line" -ge "$ins_line" ]]; then
  echo "FAIL: Runtime Environment block should precede Step Instruction (env@${env_line}, instruction@${ins_line})" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 5: NFR-5 back-compat — step with no workflow_file in state
# should NOT emit the env block (nothing to template); no crash either.
STATE_NO_WF='{"steps":[]}'
OUT2=$(context_build "$STEP_JSON" "$STATE_NO_WF" "$WF_JSON")
if printf '%s' "$OUT2" | grep -qF "## Runtime Environment"; then
  echo "FAIL: runtime env block emitted with empty workflow_file — should be absent" >&2
  FAILURES=$((FAILURES + 1))
fi
if ! printf '%s' "$OUT2" | grep -qF "## Step Instruction"; then
  echo "FAIL: instruction missing in no-workflow-file fallback path" >&2
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo "" >&2
  echo "FAIL: ${FAILURES} assertion(s) broke — FR-D1 Runtime Environment block missing or malformed" >&2
  exit 1
fi

echo "OK: FR-D1 Runtime Environment block present with absolute WORKFLOW_PLUGIN_DIR and correct ordering"
