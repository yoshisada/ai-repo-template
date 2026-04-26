#!/usr/bin/env bash
# research-runner-axis-fallback-strict-gate/run.sh — SC-AE-005 anchor.
#
# Validates User Story 6 + NFR-AE-003 (backward compat):
# A PRD with no `empirical_quality:` declared (or no --prd flag at all) MUST
# produce a report whose per-fixture verdicts + aggregate are byte-identical
# to the foundation strict-gate path modulo §3 exclusion comparator.
#
# ALSO re-runs the foundation's 5 existing fixtures to verify they pass
# post-PRD with their pre-PRD verdicts — this is the load-bearing
# backward-compat guarantee.
set -euo pipefail

here=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )
repo_root=$( cd -- "$here/../../.." && pwd )
runner="$repo_root/plugin-wheel/scripts/harness/research-runner.sh"

assertions=0
fail() { echo "FAIL: $*"; exit 1; }

# A1: invocation WITHOUT --prd flag → gate_mode=foundation_strict.
# Anchors: User Story 6 acceptance scenario 1, FR-AE-008 fall-through.
# We verify by inspecting the runner's reported gate_mode in the aggregate
# verdict line. The runner needs claude CLI to actually run, so we use the
# missing-claude-CLI path which exits BEFORE gate-mode is decided. That
# doesn't validate gate_mode dispatch.
# Alternate: trigger an inconclusive corpus (no input.json) and check the
# aggregate-verdict comment line for gate_mode signal.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# 3-fixture corpus — meets min_fixtures=3 (isolated blast) so per_axis_direction
# can reach aggregate-emit. Each fixture is broken (no input.json) → run_arm
# bails inconclusive, but PRE-subprocess validation has already passed.
for slug in 001-broken 002-broken 003-broken; do
  mkdir -p "$tmp/corpus/$slug"
  echo '{"expected_exit_code":0}' > "$tmp/corpus/$slug/expected.json"
done
set +e
out=$(bash "$runner" --baseline "$repo_root/plugin-kiln" --candidate "$repo_root/plugin-kiln" \
                     --corpus "$tmp/corpus" --report-path "$tmp/r1.md" 2>&1)
rc=$?
set -e
[[ $rc -eq 2 ]] || fail "expected exit 2 (inconclusive), got $rc (output: $out)"
echo "$out" | grep -qF "gate_mode=foundation_strict" || \
  fail "expected gate_mode=foundation_strict in aggregate, got: $out"
assertions=$((assertions + 2))

# A2: invocation WITH --prd to a PRD with no empirical_quality: → still
# foundation_strict (FR-AE-008 + NFR-AE-003).
# Anchors: User Story 6 acceptance scenario 1.
set +e
out2=$(bash "$runner" --baseline "$repo_root/plugin-kiln" --candidate "$repo_root/plugin-kiln" \
                     --corpus "$tmp/corpus" --report-path "$tmp/r2.md" \
                     --prd "$here/fixtures/no-empirical-quality-prd.md" 2>&1)
rc2=$?
set -e
[[ $rc2 -eq 2 ]] || fail "expected exit 2, got $rc2"
echo "$out2" | grep -qF "gate_mode=foundation_strict" || \
  fail "PRD without empirical_quality should still trigger foundation_strict, got: $out2"
assertions=$((assertions + 2))

# A3: invocation WITH --prd that DOES have empirical_quality: → per_axis_direction.
set +e
out3=$(bash "$runner" --baseline "$repo_root/plugin-kiln" --candidate "$repo_root/plugin-kiln" \
                     --corpus "$tmp/corpus" --report-path "$tmp/r3.md" \
                     --prd "$here/fixtures/with-empirical-quality-prd.md" 2>&1)
rc3=$?
set -e
[[ $rc3 -eq 2 ]] || fail "expected exit 2 (inconclusive), got $rc3"
echo "$out3" | grep -qF "gate_mode=per_axis_direction" || \
  fail "PRD with empirical_quality should trigger per_axis_direction, got: $out3"
assertions=$((assertions + 2))

# A4: re-run foundation's 5 existing fixtures — backward compat.
# Anchors: NFR-AE-003 / SC-AE-005 (foundation 5 fixtures pass post-PRD).
foundation_tests=(
  "research-runner-pass-path"
  "research-runner-regression-detect"
  "research-runner-determinism"
  "research-runner-missing-usage"
  "research-runner-back-compat"
)
for ft in "${foundation_tests[@]}"; do
  ft_dir="$repo_root/plugin-kiln/tests/$ft"
  [[ -d $ft_dir ]] || fail "foundation test missing: $ft"
  if ! bash "$ft_dir/run.sh" >/dev/null 2>&1; then
    fail "foundation test $ft failed post-PRD"
  fi
  assertions=$((assertions + 1))
done

echo "PASS ($assertions assertions)"
