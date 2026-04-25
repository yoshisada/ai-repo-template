#!/usr/bin/env bash
# research-runner-pass-path/run.sh — SC-S-001 + SC-S-003 anchor.
#
# Validates: byte-identical baseline=candidate (symlink-copy) → Overall: PASS,
# 3 per-fixture rows, exit 0, wall-clock ≤ 240s on the FR-S-009 seed corpus.
#
# Mode: structural by default (validates runner CLI shape, arg validation,
# bail-out diagnostics, README invariant — no live claude subprocess). Set
# KILN_TEST_LIVE=1 to additionally invoke the real seed corpus end-to-end
# (slow + costs API tokens; gated for CI parity with kiln-test convention).
#
# Acceptance scenarios anchored:
# - User Story 1, scenario 1: symlink-copied baseline=candidate produces
#   `Overall: PASS`, exit 0, .kiln/logs/research-*.md exists.
# - User Story 1, scenario 2: report contains the markdown table columns
#   per §8 layout.
set -euo pipefail

here=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )
repo_root=$( cd -- "$here/../../.." && pwd )
runner="$repo_root/plugin-wheel/scripts/harness/research-runner.sh"
seed_corpus="$repo_root/plugin-kiln/fixtures/research-first-seed/corpus"
readme="$repo_root/plugin-wheel/scripts/harness/README-research-runner.md"

assertions=0
fail() { echo "FAIL: $*"; exit 1; }

# --- Structural assertions (always run) -------------------------------------

# A1: runner exists + is executable.
[[ -x $runner ]] || fail "runner missing or not executable: $runner"
assertions=$((assertions + 1))

# A2: seed corpus has 3 fixtures + each has the required files (FR-S-002,
# FR-S-009 anchor for User Story 1).
fixture_count=$(find "$seed_corpus" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
[[ $fixture_count -eq 3 ]] || fail "expected 3 seed fixtures, got $fixture_count"
assertions=$((assertions + 1))
for f in "$seed_corpus"/*/; do
  [[ -f "$f/input.json" ]] || fail "fixture missing input.json: $f"
  [[ -f "$f/expected.json" ]] || fail "fixture missing expected.json: $f"
done
assertions=$((assertions + 1))

# A3: bail-out on missing flags (FR-S-008 exit-code contract anchor).
set +e
out=$(bash "$runner" 2>&1)
rc=$?
set -e
[[ $rc -eq 2 ]] || fail "expected exit 2 on missing flags, got $rc"
echo "$out" | grep -qF "Bail out! missing required flag" || fail "bail-out diagnostic missing"
assertions=$((assertions + 1))

# A4: bail-out on missing baseline dir.
set +e
out=$(bash "$runner" --baseline /nonexistent --candidate /tmp --corpus /tmp 2>&1)
rc=$?
set -e
[[ $rc -eq 2 ]] || fail "expected exit 2 on missing baseline, got $rc"
echo "$out" | grep -qF "Bail out! baseline plugin-dir not found" || fail "missing baseline diag"
assertions=$((assertions + 1))

# A5: bail-out on empty corpus dir (edge case from spec §Edge Cases).
empty_corpus=$(mktemp -d)
set +e
out=$(bash "$runner" --baseline "$repo_root/plugin-kiln" --candidate "$repo_root/plugin-kiln" --corpus "$empty_corpus" 2>&1)
rc=$?
set -e
rm -rf "$empty_corpus"
# Note: claude CLI check may bail before we get here on systems without claude.
# Accept both outcomes (rc=2 either way).
[[ $rc -eq 2 ]] || fail "expected exit 2 on empty corpus, got $rc"
assertions=$((assertions + 1))

# A6: README exists and is ≤ 200 lines (NFR-S-009 invariant).
# Anchored to: User Story 5, NFR-S-009.
[[ -f $readme ]] || fail "README missing: $readme"
lines=$(wc -l < "$readme" | tr -d ' ')
(( lines <= 200 )) || fail "README is $lines lines (> 200, NFR-S-009 violation)"
assertions=$((assertions + 1))

# --- Live mode (only when KILN_TEST_LIVE=1) ---------------------------------
# Anchored to: SC-S-001 (≤240s wall-clock), SC-S-003 (Overall: PASS).
if [[ ${KILN_TEST_LIVE:-0} == "1" ]]; then
  if ! command -v claude >/dev/null 2>&1; then
    echo "FAIL: KILN_TEST_LIVE=1 set but claude CLI not on PATH"
    exit 1
  fi
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  ln -s "$repo_root/plugin-kiln" "$tmp/baseline"
  ln -s "$repo_root/plugin-kiln" "$tmp/candidate"
  report_path="$tmp/research-test.md"
  t_start=$(date +%s)
  set +e
  bash "$runner" --baseline "$tmp/baseline" --candidate "$tmp/candidate" \
                 --corpus "$seed_corpus" --report-path "$report_path"
  rc=$?
  set -e
  t_end=$(date +%s)
  wall=$((t_end - t_start))

  [[ $rc -eq 0 ]] || fail "live run: expected exit 0, got $rc"
  [[ -f $report_path ]] || fail "live run: report not written"
  grep -qE 'Overall\*?\*?: PASS' "$report_path" || fail "live run: report missing 'Overall: PASS'"
  rows=$(grep -cE '^\| 00[0-9]-' "$report_path")
  [[ $rows -eq 3 ]] || fail "live run: expected 3 fixture rows, got $rows"
  (( wall <= 240 )) || fail "live run: wall-clock ${wall}s exceeds SC-S-001 budget 240s"
  assertions=$((assertions + 4))
  echo "live-mode: wall-clock=${wall}s exit=${rc} rows=${rows}"
fi

echo "PASS ($assertions assertions)"
