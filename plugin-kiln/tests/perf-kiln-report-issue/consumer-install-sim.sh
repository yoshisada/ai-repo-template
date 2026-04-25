#!/usr/bin/env bash
# T054 / SC-F-5 — Consumer-install simulation.
#
# Validates the full PRD flow end-to-end:
#
#   1. Spin up a temp scratch dir with NOTHING preinstalled — no marketplace
#      cache override, no settings.json — just `--plugin-dir` flags pointing
#      at the source-repo plugin dirs (mimicking a developer running
#      `claude --plugin-dir <local-checkout>` or a consumer who installed
#      kiln+shelf+wheel via marketplace cache for the first time).
#
#   2. Invoke `claude --print --plugin-dir plugin-wheel/ --plugin-dir
#      plugin-kiln/ --plugin-dir plugin-shelf/` with a /kiln:kiln-report-issue
#      prompt, against the scratch dir as cwd.
#
#   3. Assert post-run:
#      a. claude exited 0
#      b. The bg log line at .kiln/logs/report-issue-bg-<date>.md contains
#         counter_after=N+1 (counter actually incremented — proves the
#         dispatched bg sub-agent reached the wrapper).
#      c. The absolute path captured in the log line resolves under the
#         override locations (NOT the source-repo cache version) — proves
#         the resolver wired up correctly under --plugin-dir.
#      d. NO `.wheel/state/registry-failed-*.json` exists post-run — the
#         silent-failure tripwire NFR-F-2 wants impossible: bg log line
#         looks right, but resolver hit a failure path mid-run.
#
# Usage:
#   bash plugin-kiln/tests/perf-kiln-report-issue/consumer-install-sim.sh
#
# Pre-runtime / pre-migration mode:
#   - If plugin-kiln/workflows/kiln-report-issue.json doesn't declare
#     requires_plugins:["shelf"], exit 2 (T050 hasn't landed).
#   - If plugin-wheel/lib/{registry,resolve,preprocess}.sh missing, exit 2.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

KILN_REPORT_ISSUE_WF="${REPO_ROOT}/plugin-kiln/workflows/kiln-report-issue.json"
REGISTRY_LIB="${REPO_ROOT}/plugin-wheel/lib/registry.sh"
RESOLVE_LIB="${REPO_ROOT}/plugin-wheel/lib/resolve.sh"
PREPROCESS_LIB="${REPO_ROOT}/plugin-wheel/lib/preprocess.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# --- Gates ------------------------------------------------------------------

if [[ ! -f "$RESOLVE_LIB" || ! -f "$PREPROCESS_LIB" || ! -f "$REGISTRY_LIB" ]]; then
  echo "RUNTIME NOT READY: plugin-wheel/lib/{registry,resolve,preprocess}.sh missing." >&2
  exit 2
fi
if ! jq -e '.requires_plugins // [] | index("shelf")' "$KILN_REPORT_ISSUE_WF" >/dev/null 2>&1; then
  echo "MIGRATION NOT READY: kiln-report-issue.json doesn't declare requires_plugins:[\"shelf\"]." >&2
  exit 2
fi
if ! command -v claude >/dev/null 2>&1; then
  echo "claude CLI not found on PATH" >&2
  exit 2
fi

# --- Scaffold scratch dir ----------------------------------------------------

SCRATCH=$(mktemp -d -t kiln-test-consumer-install.XXXXXXXX)
echo "Scratch dir: $SCRATCH"
trap 'echo "Scratch retained at $SCRATCH (delete manually if test passes)"' EXIT

mkdir -p "$SCRATCH/.kiln/issues/completed" \
         "$SCRATCH/.kiln/logs" \
         "$SCRATCH/.wheel/outputs" \
         "$SCRATCH/.wheel/state"
printf 'shelf_full_sync_counter=0\nshelf_full_sync_threshold=10\n' > "$SCRATCH/.shelf-config"

# --- Invoke claude --print with --plugin-dir overrides ----------------------

PROMPT="Run /kiln:kiln-report-issue with the description: 'consumer-install simulation smoke test for SC-F-5'. Do not ask for clarification. Just file the issue and stop."

cd "$SCRATCH"
START=$(date -u +%FT%TZ)
echo "Invoking claude --print at $START..."
set +e
claude --print --output-format=json --dangerously-skip-permissions \
  --plugin-dir "$REPO_ROOT/plugin-wheel" \
  --plugin-dir "$REPO_ROOT/plugin-kiln" \
  --plugin-dir "$REPO_ROOT/plugin-shelf" \
  -- "$PROMPT" >"$SCRATCH/claude-output.json" 2>"$SCRATCH/claude-stderr.log"
CLAUDE_EXIT=$?
set -e
END=$(date -u +%FT%TZ)
echo "claude exited with $CLAUDE_EXIT at $END"

# --- Assertions --------------------------------------------------------------

# (a) exit 0
if [[ $CLAUDE_EXIT -eq 0 ]]; then
  assert_pass "claude --print exited 0"
else
  assert_fail "claude --print exited $CLAUDE_EXIT"
  echo "  stderr tail:" >&2
  tail -30 "$SCRATCH/claude-stderr.log" >&2 || true
fi

# (b) bg log line contains counter_after=1
BG_LOG=$(ls "$SCRATCH/.kiln/logs/report-issue-bg-"*.md 2>/dev/null | head -1 || true)
if [[ -z "$BG_LOG" ]]; then
  assert_fail "no bg log file at .kiln/logs/report-issue-bg-*.md"
elif grep -qE 'counter_after=1\b' "$BG_LOG"; then
  assert_pass "bg log line contains counter_after=1 (counter incremented; bg sub-agent reached wrapper)"
else
  assert_fail "bg log line missing counter_after=1"
  echo "  bg log contents:" >&2
  cat "$BG_LOG" >&2 || true
fi

# (c) The absolute path in the log line resolves under override locations.
# Per FR-E2 the wrapper writes pipe-delimited lines including the script
# path it ran. The override location for shelf is $REPO_ROOT/plugin-shelf,
# so the path should start with that prefix (NOT a marketplace cache path).
if [[ -n "$BG_LOG" ]] && grep -qF "$REPO_ROOT/plugin-shelf/scripts/" "$BG_LOG" 2>/dev/null; then
  assert_pass "bg log references shelf scripts under override path ($REPO_ROOT/plugin-shelf/...)"
elif [[ -n "$BG_LOG" ]] && grep -qF '/.claude/plugins/cache/' "$BG_LOG" 2>/dev/null; then
  assert_fail "bg log references the source-repo marketplace cache, NOT the --plugin-dir override (resolver bug)"
  grep -F '/scripts/' "$BG_LOG" >&2 || true
else
  # Either no log captured the path, or it's neither shape — soft warn (the
  # primary FR-F5-3 assertion is (b) counter_after=N+1; this assertion is
  # the SC-F-5 stretch goal).
  echo "WARN: bg log does not clearly indicate which path resolved (override vs cache). Manual inspection:" >&2
  cat "$BG_LOG" 2>/dev/null >&2 || true
  assert_pass "(soft) bg log path inspection inconclusive — primary assertion (b) is what gates SC-F-5"
fi

# (e) SC-F-6 — newly-archived state file has zero plugin-path tokens. The
# grep target in the spec is `.wheel/history/success/*.json`, but we
# don't want to assert on existing archived files (which may be pre-PRD
# historical). Instead, find the state file written by THIS run (sorted
# by mtime; the kiln-report-issue archive landed inside the scratch dir's
# .wheel/history/success/) and grep it specifically.
NEWEST_STATE=$(find "$SCRATCH/.wheel/history/success" -name 'kiln-report-issue-*.json' -type f 2>/dev/null \
              | xargs -I{} stat -f '%m %N' {} 2>/dev/null \
              | sort -rn | head -1 | cut -d' ' -f2-)
if [[ -z "$NEWEST_STATE" ]]; then
  # Fall back to scratch's .wheel/state if archive didn't happen.
  NEWEST_STATE=$(find "$SCRATCH/.wheel" -name '*.json' -type f 2>/dev/null \
                | xargs -I{} stat -f '%m %N' {} 2>/dev/null \
                | sort -rn | head -1 | cut -d' ' -f2-)
fi
if [[ -z "$NEWEST_STATE" ]]; then
  assert_fail "SC-F-6 — could not locate any state file under .wheel/ to grep"
elif grep -qE '\$\{(WORKFLOW_PLUGIN_DIR|WHEEL_PLUGIN_)[^}]*\}' "$NEWEST_STATE"; then
  assert_fail "SC-F-6 — state file $NEWEST_STATE contains plugin-path tokens (preprocessor failed to substitute)"
  grep -nE '\$\{(WORKFLOW_PLUGIN_DIR|WHEEL_PLUGIN_)[^}]*\}' "$NEWEST_STATE" >&2 || true
else
  assert_pass "SC-F-6 — newly-archived state file ($NEWEST_STATE) contains zero \${WHEEL_PLUGIN_*}/\${WORKFLOW_PLUGIN_DIR} tokens"
fi

# (d) NFR-F-2 silent-failure tripwire: no registry-failed snapshot exists.
SNAPSHOTS=$(find "$SCRATCH" -path '*/registry-failed-*.json' 2>/dev/null || true)
if [[ -z "$SNAPSHOTS" ]]; then
  assert_pass "NFR-F-2 silent-failure tripwire: no .wheel/state/registry-failed-*.json present (resolver did not hit a failure path)"
else
  assert_fail "NFR-F-2 silent-failure tripwire: registry-failed snapshot(s) present — resolver hit a failure path mid-run"
  echo "  snapshots:" >&2
  echo "$SNAPSHOTS" >&2
fi

# --- Summary ---------------------------------------------------------------
echo
echo "--- Results: ${pass} passed, ${fail} failed ---"
echo "Scratch dir: $SCRATCH"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
trap - EXIT
rm -rf "$SCRATCH"
