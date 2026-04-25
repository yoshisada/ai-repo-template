#!/usr/bin/env bash
# Test: require-feature-branch-build-prefix
#
# Validates: FR-001 (verification), FR-002 (verification), FR-003 (test
# fixture), NFR-001 (≤ 50ms of baseline on positive case).
#
# Strategy: drive plugin-kiln/hooks/require-feature-branch.sh directly with
# a JSON payload on stdin, with CLAUDE_PROJECT_DIR pointing at a throw-away
# git repo whose HEAD we control via `git checkout`. Each case asserts the
# hook's exit code and stderr shape.
#
# Does NOT edit the hook. FR-001/FR-002 already shipped in commit 86e3585;
# this fixture is a regression guard only.
#
# Exit codes:
#   0 — all cases pass
#   1 — any case fails
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../../hooks/require-feature-branch.sh"
BASELINE_FILE="$SCRIPT_DIR/fixture/baseline-ms.txt"

if [[ ! -f "$HOOK" ]]; then
  echo "FAIL: hook missing at $HOOK" >&2
  exit 1
fi

# Disposable git repo we can switch branches in without affecting the real
# working tree (the hook reads the branch from CLAUDE_PROJECT_DIR).
TMP_REPO=$(mktemp -d)
trap 'rm -rf "$TMP_REPO"' EXIT

git -C "$TMP_REPO" init -q
git -C "$TMP_REPO" config user.email 'test@example.com'
git -C "$TMP_REPO" config user.name 'test'
# Seed an initial commit on whatever the default branch is.
touch "$TMP_REPO/.seed"
git -C "$TMP_REPO" add .seed
git -C "$TMP_REPO" commit -q -m seed
# Normalise the default branch name to `main` so case 2 is deterministic.
git -C "$TMP_REPO" branch -M main

# Pre-seed the branches the fixture exercises.
for branch in build/workflow-governance-20260424 feature/foo randomstring; do
  git -C "$TMP_REPO" branch "$branch"
done

run_hook() {
  # usage: run_hook <branch> <file_path>
  # Echoes "<exit_code>|<stderr>" on stdout; hook stdout is discarded.
  # The hook matches file_path against */specs/* — a leading path component
  # is required. We prefix with the repo root so the match triggers and the
  # branch gate is actually evaluated (otherwise the hook short-circuits at
  # the path gate on line 24-30, masking branch-gate regressions).
  local branch=$1
  local file_path=$2
  git -C "$TMP_REPO" checkout -q "$branch"
  local payload
  payload=$(jq -cn --arg fp "$TMP_REPO/$file_path" \
    '{tool_name:"Write", tool_input:{file_path:$fp}}')
  local stderr_tmp
  stderr_tmp=$(mktemp)
  set +e
  echo "$payload" | CLAUDE_PROJECT_DIR="$TMP_REPO" bash "$HOOK" \
    >/dev/null 2>"$stderr_tmp"
  local rc=$?
  set -e
  printf '%s|%s' "$rc" "$(cat "$stderr_tmp")"
  rm -f "$stderr_tmp"
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Case 1 — POSITIVE: build/* + specs/<slug>/ write → exit 0, no stderr.
# FR-001 verification + FR-003 positive case.
# ---------------------------------------------------------------------------
result=$(run_hook build/workflow-governance-20260424 \
  specs/workflow-governance/spec.md)
rc=${result%%|*}
stderr_body=${result#*|}
[[ "$rc" == "0" ]] || fail "Case 1 (build/* positive) expected exit 0, got $rc. stderr: $stderr_body"
[[ -z "$stderr_body" ]] || fail "Case 1 (build/* positive) expected empty stderr, got: $stderr_body"
echo "PASS: Case 1 — build/workflow-governance-20260424 + specs/ write → exit 0"

# ---------------------------------------------------------------------------
# Case 2 — NEGATIVE: main branch. Hook short-circuits with exit 0 on main
# (line 40 of the hook). This case asserts the pre-existing behavior is
# preserved after the build/* widening — FR-002 non-widening guard.
# ---------------------------------------------------------------------------
result=$(run_hook main specs/anything/spec.md)
rc=${result%%|*}
stderr_body=${result#*|}
[[ "$rc" == "0" ]] || fail "Case 2 (main) expected exit 0 (short-circuit), got $rc. stderr: $stderr_body"
echo "PASS: Case 2 — main branch → exit 0 (pre-existing short-circuit preserved)"

# ---------------------------------------------------------------------------
# Case 3 — NEGATIVE: feature/foo (unprefixed). Must exit 2 with standard
# error — guards that build/* did NOT widen to accept */*.
# FR-002 non-widening guard.
# ---------------------------------------------------------------------------
result=$(run_hook feature/foo specs/rename-thing/spec.md)
rc=${result%%|*}
stderr_body=${result#*|}
[[ "$rc" == "2" ]] || fail "Case 3 (feature/foo) expected exit 2, got $rc. stderr: $stderr_body"
echo "$stderr_body" | grep -q "BLOCKED" || fail "Case 3 stderr missing BLOCKED marker. Got: $stderr_body"
echo "PASS: Case 3 — feature/foo → exit 2 (BLOCKED)"

# ---------------------------------------------------------------------------
# Case 4 — NEGATIVE: random bare branch. Must exit 2.
# ---------------------------------------------------------------------------
result=$(run_hook randomstring specs/anything/spec.md)
rc=${result%%|*}
stderr_body=${result#*|}
[[ "$rc" == "2" ]] || fail "Case 4 (randomstring) expected exit 2, got $rc. stderr: $stderr_body"
echo "PASS: Case 4 — randomstring → exit 2"

# ---------------------------------------------------------------------------
# Case 5 — PERFORMANCE: median of 10 runs on the positive case within
# baseline+50ms. NFR-001. Baseline is captured lazily on first run and
# written to fixture/baseline-ms.txt; subsequent runs compare.
# ---------------------------------------------------------------------------
git -C "$TMP_REPO" checkout -q build/workflow-governance-20260424
payload=$(jq -cn --arg fp "$TMP_REPO/specs/workflow-governance/spec.md" \
  '{tool_name:"Write", tool_input:{file_path:$fp}}')

perf_one() {
  # prints wall-clock milliseconds for one hook invocation
  local start_ns end_ns
  start_ns=$(python3 -c 'import time; print(int(time.monotonic_ns()))' 2>/dev/null \
    || date +%s%N)
  echo "$payload" | CLAUDE_PROJECT_DIR="$TMP_REPO" bash "$HOOK" >/dev/null 2>&1
  end_ns=$(python3 -c 'import time; print(int(time.monotonic_ns()))' 2>/dev/null \
    || date +%s%N)
  echo $(( (end_ns - start_ns) / 1000000 ))
}

times=()
for _ in 1 2 3 4 5 6 7 8 9 10; do
  times+=("$(perf_one)")
done
# Median of the 10 samples.
IFS=$'\n' sorted=( $(printf '%s\n' "${times[@]}" | sort -n) )
unset IFS
median=${sorted[5]}

if [[ ! -f "$BASELINE_FILE" ]]; then
  # First run — capture baseline so subsequent runs have something to compare
  # against. NFR-001 is "within 50ms of baseline"; without a baseline we just
  # log the number and pass.
  echo "$median" > "$BASELINE_FILE"
  echo "PASS: Case 5 — performance median ${median}ms (baseline captured for NFR-001)"
else
  baseline=$(tr -d ' \t\n\r' < "$BASELINE_FILE")
  delta=$(( median - baseline ))
  # Guard against negative delta (hook got faster — accept unconditionally).
  if (( delta > 50 )); then
    fail "Case 5 — median ${median}ms exceeds baseline ${baseline}ms by ${delta}ms (> 50ms NFR-001)"
  fi
  echo "PASS: Case 5 — performance median ${median}ms (baseline ${baseline}ms, Δ${delta}ms ≤ 50ms)"
fi

echo "PASS: require-feature-branch-build-prefix — all 5 cases green"
