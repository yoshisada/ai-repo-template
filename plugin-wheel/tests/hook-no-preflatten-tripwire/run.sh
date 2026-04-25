#!/usr/bin/env bash
# NFR-2 regression tripwire for FR-C1 (specs/wheel-as-runtime/spec.md).
#
# This test inserts the pre-FR-C1 `tr '\n' ' '` pre-flatten back into the
# hook (in a disposable copy, NOT in the real hook file), runs the FR-C2
# multi-line activation test against it, and asserts the test FAILS with
# an identifiable error string.
#
# If this tripwire itself passes silently when the flatten is re-added,
# the NFR-2 invariant is broken: future regressions to the pre-flatten
# behavior would ship green. We want them to ship RED and loud.
#
# Success shape: the activate-multiline run.sh exits non-zero AND the
# output contains "FR-C2 invariant broken" on the simulated-regression run.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
REAL_HOOK="${REPO_ROOT}/plugin-wheel/hooks/post-tool-use.sh"
ACTIVATE_TEST="${REPO_ROOT}/plugin-wheel/tests/activate-multiline/run.sh"

if [[ ! -f "$REAL_HOOK" ]]; then
  echo "FAIL: real hook missing: $REAL_HOOK" >&2
  exit 1
fi
if [[ ! -x "$ACTIVATE_TEST" ]]; then
  echo "FAIL: multi-line activation test missing or not executable: $ACTIVATE_TEST" >&2
  exit 1
fi

# Work in a disposable hooks-dir that the activate-multiline test can be
# pointed at via a patched copy of the hook.
STAGE="$(mktemp -d -t preflatten-tripwire-XXXXXX)"
trap 'rm -rf "$STAGE"; cp "${STAGE}/real-hook.bak" "$REAL_HOOK" 2>/dev/null || true' EXIT

# Back up the real hook so we can restore if anything goes wrong
cp "$REAL_HOOK" "${STAGE}/real-hook.bak"

# Patch the real hook to re-insert the pre-flatten bug shape. We rewrite the
# command-extraction line to pipe through `tr '\n' ' '` before jq — the exact
# regression shape FR-C1 removed.
python3 - <<PY
p = "${REAL_HOOK}"
with open(p) as f:
    src = f.read()
# Replace the call to _extract_command with a pre-flatten extractor. If the
# hook refactors and this marker disappears, the tripwire fails loudly (the
# sed finds no match and we catch that below).
marker = "COMMAND=\$(_extract_command)"
patch  = 'COMMAND=\$(printf "%s" "\$RAW_INPUT" | tr "\\n" " " | jq -r ".tool_input.command // empty" 2>/dev/null || echo "")'
if marker not in src:
    import sys
    sys.stderr.write("tripwire: marker '_extract_command' not found in hook — FR-C1 refactor detected, tripwire needs update\n")
    sys.exit(2)
with open(p, "w") as f:
    f.write(src.replace(marker, patch))
PY

# Run the FR-C2 test against the regressed hook. We expect:
#   - exit non-zero
#   - output contains "FR-C2 invariant broken" (identifiable error string)
set +e
regressed_output=$(bash "$ACTIVATE_TEST" 2>&1)
regressed_exit=$?
set -e

# Restore the real hook before we make any assertions
cp "${STAGE}/real-hook.bak" "$REAL_HOOK"

if [[ "$regressed_exit" -eq 0 ]]; then
  echo "FAIL: with pre-flatten re-inserted, the FR-C2 test still passed — NFR-2 tripwire is blind" >&2
  echo "$regressed_output" >&2
  exit 1
fi
if ! printf '%s' "$regressed_output" | grep -q "FR-C2 invariant broken"; then
  echo "FAIL: regressed run exited non-zero but did not emit the identifiable error string 'FR-C2 invariant broken'" >&2
  echo "regressed output:" >&2
  printf '%s\n' "$regressed_output" >&2
  exit 1
fi

echo "OK: NFR-2 tripwire verified — re-inserting the pre-flatten makes FR-C2 fail loudly with identifiable error string"
