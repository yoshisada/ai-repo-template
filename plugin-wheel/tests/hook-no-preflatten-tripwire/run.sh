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
REAL_EXTRACTORS="${REPO_ROOT}/plugin-wheel/dist/hooks/post-tool-use/extractors.js"
ACTIVATE_TEST="${REPO_ROOT}/plugin-wheel/tests/activate-multiline/run.sh"

if [[ ! -f "$REAL_EXTRACTORS" ]]; then
  echo "FAIL: compiled extractors missing: $REAL_EXTRACTORS — run \`npm run build\` first" >&2
  exit 1
fi
if [[ ! -x "$ACTIVATE_TEST" ]]; then
  echo "FAIL: multi-line activation test missing or not executable: $ACTIVATE_TEST" >&2
  exit 1
fi

# Work in a disposable stage. We back up the compiled extractor module,
# patch it to simulate the pre-FR-C1 regression (flatten newlines before
# scanning), run the activate-multiline test against the regressed dist,
# and restore the original on exit.
STAGE="$(mktemp -d -t preflatten-tripwire-XXXXXX)"
cp "$REAL_EXTRACTORS" "${STAGE}/extractors.js.bak"
trap 'cp "${STAGE}/extractors.js.bak" "$REAL_EXTRACTORS" 2>/dev/null || true; rm -rf "$STAGE"' EXIT

# Patch the compiled extractor to simulate the pre-FR-C1 regression by
# replacing detectActivateLine's body with a flatten-first scan: collapse
# newlines to spaces BEFORE matching. This is the exact shape FR-C1 removed
# — when the command has activate.sh on a non-last line, the flatten makes
# the line-by-line scan miss the activate token's position context, and
# downstream `extractWorkflowName` extracts garbage from the merged blob.
#
# Marker: literal string `function detectActivateLine`. If the marker
# disappears (refactor), the patcher fails loudly so the maintainer knows
# to update the patch site rather than ship a blind tripwire.
PATCHER="${STAGE}/patch.py"
cat > "$PATCHER" <<'PY'
import re, sys
p = sys.argv[1]
with open(p) as f:
    src = f.read()
marker = "export function detectActivateLine"
if marker not in src:
    sys.stderr.write("tripwire: marker 'function detectActivateLine' not found in compiled extractors — FR-C1 refactor detected, tripwire needs update\n")
    sys.exit(2)
# Regression body: returns a flattened blob that includes activate.sh but
# whose tokens-after-activate.sh are scrambled by the original newlines
# (now spaces). extractWorkflowName picks the wrong token, activation
# attempts the wrong workflow, and FR-C2 invariant breaks.
regression = (
    "export function detectActivateLine(command) {\n"
    "    const flat = command.split('\\n').join(' ');\n"
    "    if (flat.indexOf('plugin-wheel/bin/activate.sh') === -1) return null;\n"
    "    return flat;\n"
    "}"
)
# Replace from `export function detectActivateLine` up to (but not
# including) the next top-level `export function ` declaration.
patched = re.sub(
    r"export function detectActivateLine[\s\S]*?(?=\nexport function )",
    regression + "\n",
    src,
    count=1,
)
if patched == src:
    sys.stderr.write("tripwire: regex replacement failed — extractors.js layout changed, tripwire needs update\n")
    sys.exit(2)
with open(p, "w") as f:
    f.write(patched)
PY
python3 "$PATCHER" "$REAL_EXTRACTORS"

# Run the FR-C2 test against the regressed hook. We expect:
#   - exit non-zero
#   - output contains "FR-C2 invariant broken" (identifiable error string)
set +e
regressed_output=$(bash "$ACTIVATE_TEST" 2>&1)
regressed_exit=$?
set -e

# Restore the real extractors before we make any assertions
cp "${STAGE}/extractors.js.bak" "$REAL_EXTRACTORS"

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
