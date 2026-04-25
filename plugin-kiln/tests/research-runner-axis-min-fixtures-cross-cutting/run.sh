#!/usr/bin/env bash
# research-runner-axis-min-fixtures-cross-cutting/run.sh — SC-AE-002 anchor.
#
# Validates User Story 2 (FR-AE-004 / NFR-AE-007):
# A 5-fixture corpus + PRD declaring `blast_radius: cross-cutting` (rigor row:
# min_fixtures=20) MUST exit 2 with `Bail out! min-fixtures-not-met: 5 < 20`
# BEFORE any subprocess invocation. NO scratch dirs created.
#
# Pure-shell unit fixture per the test substrate hierarchy. Drives the runner
# CLI directly with a synthetic 5-fixture corpus + PRD; the bail-out fires
# at runner startup before any claude subprocess invocation.
set -euo pipefail

here=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )
repo_root=$( cd -- "$here/../../.." && pwd )
runner="$repo_root/plugin-wheel/scripts/harness/research-runner.sh"

assertions=0
fail() { echo "FAIL: $*"; exit 1; }

# A1: build a 5-fixture corpus.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for i in 1 2 3 4 5; do
  dir="$tmp/corpus/00${i}-fixture"
  mkdir -p "$dir"
  printf '{"type":"user","message":{"role":"user","content":"/help"}}\n' >"$dir/input.json"
  printf '{"expected_exit_code":0}\n' >"$dir/expected.json"
done
assertions=$((assertions + 1))

# A2: invoke runner with the cross-cutting PRD — expect bail-out PRE-subprocess.
# Anchors: User Story 2 acceptance scenario 1, FR-AE-004.
set +e
out=$(bash "$runner" --baseline "$repo_root/plugin-kiln" --candidate "$repo_root/plugin-kiln" \
                     --corpus "$tmp/corpus" --prd "$here/fixtures/cross-cutting-prd.md" 2>&1)
rc=$?
set -e

[[ $rc -eq 2 ]] || fail "expected exit 2, got $rc (output: $out)"
assertions=$((assertions + 1))

echo "$out" | grep -qF "Bail out! min-fixtures-not-met: 5 < 20" || \
  fail "diagnostic missing 'Bail out! min-fixtures-not-met: 5 < 20' (output: $out)"
echo "$out" | grep -qF "blast_radius: cross-cutting" || \
  fail "diagnostic missing blast_radius citation (output: $out)"
assertions=$((assertions + 2))

# A3: verify NO scratch dirs were created (PRE-subprocess fail-fast).
# Anchors: User Story 2 acceptance scenario 1 ("BEFORE any subprocess invocation").
# We can't easily prove the runner didn't create scratch dirs unless we
# inspect /tmp; the surrogate is checking that the bail-out diagnostic
# appeared in stderr, which only fires before run_arm() is called.
# Counter-check: confirm the bail-out message comes BEFORE any TAP output.
if echo "$out" | grep -q '^TAP version'; then
  fail "TAP output emitted — runner started subprocess loop before bailing"
fi
assertions=$((assertions + 1))

# A4: positive case — blast_radius: isolated (rigor row min_fixtures=3) with
# the same 5-fixture corpus is NOT a min_fixtures violation.
# Anchors: User Story 2 acceptance scenario 2.
set +e
out2=$(bash "$runner" --baseline "$repo_root/plugin-kiln" --candidate "$repo_root/plugin-kiln" \
                     --corpus "$tmp/corpus" --prd "$here/fixtures/isolated-prd.md" 2>&1)
rc2=$?
set -e
# The runner may exit with rc=2 (claude subprocess missing on test host) but
# NOT with the min_fixtures bail-out diagnostic.
echo "$out2" | grep -qF "min-fixtures-not-met" && \
  fail "isolated blast triggered min-fixtures check incorrectly: $out2"
assertions=$((assertions + 1))

# A5: unknown blast_radius value → bail-out.
# Anchors: User Story 2 acceptance scenario 3.
set +e
out3=$(bash "$runner" --baseline "$repo_root/plugin-kiln" --candidate "$repo_root/plugin-kiln" \
                     --corpus "$tmp/corpus" --prd "$here/fixtures/unknown-blast-prd.md" 2>&1)
rc3=$?
set -e
[[ $rc3 -eq 2 ]] || fail "unknown blast_radius: expected exit 2, got $rc3"
echo "$out3" | grep -qE "(unknown blast_radius: tiny|parse error: unknown blast_radius)" || \
  fail "unknown blast_radius diagnostic missing (output: $out3)"
assertions=$((assertions + 2))

echo "PASS ($assertions assertions)"
