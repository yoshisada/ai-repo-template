#!/usr/bin/env bash
# NFR-2 regression tripwire for FR-D1 (specs/wheel-as-runtime/spec.md).
#
# The bug shape that shipped: wheel's agent-step dispatch silently failed
# to surface WORKFLOW_PLUGIN_DIR to sub-agents, so consumer-install bg
# sub-agents ran with the var unset and no-op'd without error. Option B
# (FR-D1) fixes this by templating the absolute value into the agent
# step's instruction via context_build's Runtime Environment block.
#
# This tripwire asserts: if the Runtime Environment block is removed from
# context.sh, the FR-D2 consumer-install smoke test fails LOUDLY with an
# identifiable error string ('FR-D1 Runtime Environment block missing').
# A silent-green regression ship is impossible.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONTEXT_LIB="${REPO_ROOT}/plugin-wheel/lib/context.sh"
FR_D2_TEST="${REPO_ROOT}/plugin-wheel/tests/workflow-plugin-dir-bg/run.sh"

if [[ ! -f "$CONTEXT_LIB" ]]; then
  echo "FAIL: context.sh missing: $CONTEXT_LIB" >&2
  exit 1
fi
if [[ ! -x "$FR_D2_TEST" ]]; then
  echo "FAIL: FR-D2 smoke test not executable: $FR_D2_TEST" >&2
  exit 1
fi

STAGE="$(mktemp -d -t wpd-tripwire-XXXXXX)"
trap 'cp "${STAGE}/context.sh.bak" "$CONTEXT_LIB" 2>/dev/null || true; rm -rf "$STAGE"' EXIT

# Back up and patch the real context.sh to neuter the FR-D1 runtime env
# block — the exact regression shape we want the tripwire to catch.
cp "$CONTEXT_LIB" "${STAGE}/context.sh.bak"

python3 - <<PY
p = "${CONTEXT_LIB}"
with open(p) as f:
    src = f.read()
# Look for the marker that denotes the FR-D1 runtime-env block.
marker = "## Runtime Environment (wheel-templated, FR-D1)"
if marker not in src:
    import sys
    sys.stderr.write("tripwire: marker '" + marker + "' not found in context.sh — FR-D1 refactor detected, tripwire needs update\n")
    sys.exit(2)
# Replace the block-emitter assignment so runtime_env_block stays empty.
# We neutralize it by setting runtime_env_block="" unconditionally.
start_anchor = "local runtime_env_block=\"\""
end_anchor   = "fi\n  fi\n\n  local context_parts="
# Simpler: replace the whole if-block that computes runtime_env_block with
# just 'runtime_env_block=""'. The block starts right after that local decl
# and the 'local _wf_file ...' line, and ends at the 'local context_parts=' line.
import re
pat = re.compile(
    r"local runtime_env_block=\"\"\n"
    r"  local _wf_file _wf_plugin_dir\n"
    r".*?(?=\n  local context_parts=\"\"\n)",
    re.DOTALL,
)
new_src, n = pat.subn('local runtime_env_block=""', src)
if n != 1:
    import sys
    sys.stderr.write("tripwire: did not find the FR-D1 block to neutralize — refactor detected\n")
    sys.exit(3)
with open(p, "w") as f:
    f.write(new_src)
PY

# Run the FR-D2 smoke test against the neutralized context.sh. Expect it to fail.
set +e
regressed_output=$(bash "$FR_D2_TEST" 2>&1)
regressed_exit=$?
set -e

# Restore the real context.sh before asserting
cp "${STAGE}/context.sh.bak" "$CONTEXT_LIB"

if [[ "$regressed_exit" -eq 0 ]]; then
  echo "FAIL: with the Runtime Environment block removed, the FR-D2 smoke test still passed — NFR-2 tripwire is blind" >&2
  echo "$regressed_output" >&2
  exit 1
fi

if ! printf '%s' "$regressed_output" | grep -qF "FR-D1 Runtime Environment block missing"; then
  echo "FAIL: regressed run exited non-zero but did not emit the identifiable error string 'FR-D1 Runtime Environment block missing'" >&2
  printf 'regressed output:\n%s\n' "$regressed_output" >&2
  exit 1
fi

echo "OK: NFR-2 tripwire verified — removing the FR-D1 Runtime Environment block causes FR-D2 to fail loudly"
