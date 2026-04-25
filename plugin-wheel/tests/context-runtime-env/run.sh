#!/usr/bin/env bash
# context_build agent-step formatting test.
#
# History: this file used to assert the FR-D1 Option B "## Runtime
# Environment (wheel-templated, FR-D1)" block (specs/wheel-as-runtime).
# Theme F4 of specs/cross-plugin-resolver-and-preflight-registry SUPERSEDES
# Option B by templating literal absolute paths into agent step
# `.instruction` fields BEFORE state_init via
# plugin-wheel/lib/preprocess.sh::template_workflow_json. By the time
# context_build runs, the instruction already contains literal paths —
# emitting a duplicate runtime-env header is now redundant and was removed
# in T042 of cross-plugin-resolver-and-preflight-registry/tasks.md.
#
# This test is repurposed (NFR-F-2 silent-failure tripwire) — it now
# guards the inverse invariant:
#   1. context_build does NOT emit the obsolete "## Runtime Environment"
#      header (a regression that re-introduces it would mean Theme F4 was
#      partially undone).
#   2. context_build still emits the "## Step Instruction" block with the
#      preserved instruction text (FR-027 of wheel core).
#   3. The output makes no reference to FR-D1 marker text — that string
#      is reserved for the (now-removed) Theme D Option B path.
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

# Note: the preprocessor would have already substituted ${WORKFLOW_PLUGIN_DIR}
# into a literal absolute path BEFORE context_build sees the instruction.
# We simulate the post-preprocess state directly here: the instruction
# contains a literal path, no token. (Verifying the substitution itself is
# the job of plugin-wheel/tests/preprocess-substitution.bats.)
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

# ---- Assertion 1: obsolete Runtime Environment header MUST be absent ----
# (T042 invariant: Theme F4 superseded Theme D Option B; no regression that
# re-emits the header is acceptable.)
if printf '%s' "$OUT" | grep -qF "## Runtime Environment"; then
  echo "FAIL: T042 invariant violated — context_build emitted a '## Runtime Environment' header (Theme F4 should have removed it)" >&2
  printf 'output:\n%s\n' "$OUT" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 2: FR-D1 marker MUST be absent ----
# (Theme D Option B's identifying string is gone; if it reappears, an
# auditor needs to know.)
if printf '%s' "$OUT" | grep -qF "FR-D1"; then
  echo "FAIL: T042 invariant violated — output contains 'FR-D1' marker (should be removed by Theme F4 refactor)" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 3: Step Instruction header is still present ----
if ! printf '%s' "$OUT" | grep -qF "## Step Instruction"; then
  echo "FAIL: '## Step Instruction' header missing from context_build output" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 4: literal instruction text survives ----
if ! printf '%s' "$OUT" | grep -qF "Do the thing."; then
  echo "FAIL: instruction text 'Do the thing.' missing from context_build output" >&2
  FAILURES=$((FAILURES + 1))
fi

# ---- Assertion 5: NFR-F-5 back-compat — context_build with no workflow_file
# still emits a Step Instruction block (and never crashes). ----
STATE_NO_WF='{"steps":[]}'
OUT2=$(context_build "$STEP_JSON" "$STATE_NO_WF" "$WF_JSON")
if printf '%s' "$OUT2" | grep -qF "## Runtime Environment"; then
  echo "FAIL: runtime env block emitted with empty workflow_file — should be absent post-T042" >&2
  FAILURES=$((FAILURES + 1))
fi
if ! printf '%s' "$OUT2" | grep -qF "## Step Instruction"; then
  echo "FAIL: instruction missing in no-workflow-file fallback path" >&2
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo "" >&2
  echo "FAIL: ${FAILURES} assertion(s) broke — Theme F4 context_build refactor regression" >&2
  exit 1
fi

echo "OK: context_build emits Step Instruction without obsolete Runtime Environment header (Theme F4 / T042)"
