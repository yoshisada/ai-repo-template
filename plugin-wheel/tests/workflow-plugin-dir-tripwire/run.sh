#!/usr/bin/env bash
# Theme F4 / T042 — repurposed silent-failure tripwire.
#
# History: this file used to neutralize the FR-D1 Option B
# `runtime_env_block` in context.sh and assert that the FR-D2 consumer-
# install smoke test failed loudly (specs/wheel-as-runtime). Theme F4 of
# specs/cross-plugin-resolver-and-preflight-registry SUPERSEDES Option B —
# the runtime_env_block has been removed (T042). The original tripwire
# scenario is no longer reachable.
#
# Rather than delete the file (which would silently drop a tripwire from
# CI), the test is repurposed for the Theme F4 equivalent invariant:
#
#   "Mutating preprocess.sh to drop the FR-F4-5 narrowed-pattern tripwire
#    MUST cause the preprocess-tripwire.bats test to fail loudly."
#
# This guards against a regression where a future refactor removes or
# weakens the residual-token grep in template_workflow_json.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PREPROCESS_LIB="${REPO_ROOT}/plugin-wheel/lib/preprocess.sh"
TRIPWIRE_BATS="${REPO_ROOT}/plugin-wheel/tests/preprocess-tripwire.bats"

if [[ ! -f "$PREPROCESS_LIB" ]]; then
  echo "FAIL: preprocess.sh missing: $PREPROCESS_LIB" >&2
  exit 1
fi
if [[ ! -f "$TRIPWIRE_BATS" ]]; then
  echo "FAIL: preprocess-tripwire.bats missing: $TRIPWIRE_BATS" >&2
  exit 1
fi
if ! command -v bats >/dev/null 2>&1; then
  echo "SKIP: bats not installed; cannot run the FR-F4-5 tripwire. Install bats-core (e.g. brew install bats-core / apt-get install bats) and re-run." >&2
  exit 0
fi

STAGE="$(mktemp -d -t wpd-tripwire-XXXXXX)"
trap 'cp "${STAGE}/preprocess.sh.bak" "$PREPROCESS_LIB" 2>/dev/null || true; rm -rf "$STAGE"' EXIT

# Back up the real preprocess.sh and patch out the FR-F4-5 narrowed-pattern
# tripwire grep. The exact regression shape we want to catch.
cp "$PREPROCESS_LIB" "${STAGE}/preprocess.sh.bak"

python3 - <<PY
import re, sys
p = "${PREPROCESS_LIB}"
with open(p) as f:
    src = f.read()
# Look for the marker comment that denotes the FR-F4-5 tripwire.
marker = "FR-F4-5 tripwire — narrowed pattern"
if marker not in src:
    sys.stderr.write("tripwire: marker '" + marker + "' not found in preprocess.sh — Theme F4 refactor detected, this guard needs updating\n")
    sys.exit(2)
# Match from the marker comment through the closing 'fi' — neutralise the
# whole if-block by replacing it with a no-op. Avoiding fragile escape-
# heavy regexes: anchor on the marker, find the next 'fi\n' and replace.
start = src.find("    # FR-F4-5 tripwire")
if start == -1:
    sys.stderr.write("tripwire: could not locate FR-F4-5 block start — refactor detected\n")
    sys.exit(3)
# The block is: <comment lines>\n    if printf ...\n      printf ...\n      return 1\n    fi
# Find the end as the first '    fi\n' after the 'return 1' line.
ret_idx = src.find("return 1", start)
if ret_idx == -1:
    sys.stderr.write("tripwire: could not locate 'return 1' inside FR-F4-5 block — refactor detected\n")
    sys.exit(4)
fi_idx = src.find("    fi\n", ret_idx)
if fi_idx == -1:
    sys.stderr.write("tripwire: could not locate closing 'fi' for FR-F4-5 block — refactor detected\n")
    sys.exit(5)
end = fi_idx + len("    fi\n")
new_src = src[:start] + "    : # tripwire neutered for NFR-F-2 verification\n" + src[end:]
with open(p, "w") as f:
    f.write(new_src)
PY

# Run the FR-F4-5 bats suite against the neutered preprocess.sh.
# Expect at least one assertion to fail.
set +e
regressed_output=$(bats "$TRIPWIRE_BATS" 2>&1)
regressed_exit=$?
set -e

# Restore the real preprocess.sh before asserting.
cp "${STAGE}/preprocess.sh.bak" "$PREPROCESS_LIB"

if [[ "$regressed_exit" -eq 0 ]]; then
  echo "FAIL: with the FR-F4-5 tripwire neutered, preprocess-tripwire.bats still passed — NFR-F-2 silent-failure tripwire is blind" >&2
  echo "$regressed_output" >&2
  exit 1
fi

# Verify the failure surfaced an identifiable Theme F4 marker. The bats
# tests assert the FR-F4-5 documented error string verbatim; with the
# tripwire neutered they fail because the error never fires, producing
# bats output mentioning the missing 'Wheel preprocessor failed' line.
if ! printf '%s' "$regressed_output" | grep -qE "(Wheel preprocessor failed|not ok)"; then
  echo "FAIL: regressed run exited non-zero but did not show the expected bats failure markers" >&2
  printf 'regressed output:\n%s\n' "$regressed_output" >&2
  exit 1
fi

echo "OK: NFR-F-2 tripwire verified — neutering the FR-F4-5 grep causes preprocess-tripwire.bats to fail loudly"
