#!/usr/bin/env bash
# T053 — perf-kiln-report-issue fixture (NFR-F-4 + NFR-F-6 + SC-F-4).
#
# Two perf gates:
#
#   (a) NFR-F-4 — full /kiln:kiln-report-issue bg sub-agent path.
#       Re-runs the existing perf driver from
#       plugin-kiln/tests/kiln-report-issue-batching-perf/perf-driver.sh
#       (N=5 alternating before/after samples) and asserts that the
#       post-PRD "after" arm medians for `elapsed_sec` and `duration_api_ms`
#       are within 120% of the baseline at commit b81aa25 captured in
#       baselines/b81aa25-after.json. Both metrics MUST pass.
#
#   (b) NFR-F-6 — pre-flight resolver overhead alone.
#       Times `build_session_registry` + `resolve_workflow_dependencies` +
#       `template_workflow_json` against a synthetic workflow that declares
#       NO `requires_plugins` (fixtures/no-deps-workflow.json). Asserts
#       wall-clock <= 200ms across N=5 trials (median).
#
# Usage:
#   bash plugin-kiln/tests/perf-kiln-report-issue/run.sh
#
# Flags (env vars):
#   PERF_SKIP_LIVE=1   — skip gate (a) (the LLM-driven full perf run, ~3 min);
#                        run only gate (b). Used for fast smoke. CI runs
#                        without this flag.
#   PERF_LIVE_N=<int>  — override sample count for gate (a). Default 5.
#
# Pre-runtime mode:
#   When the runtime libs are missing OR the migrated kiln-report-issue.json
#   is missing `requires_plugins: ["shelf"]`, this script exits 2 with a
#   "RUNTIME NOT READY" message — Phase 5 atomic commit lifts that gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

BASELINE_JSON="${SCRIPT_DIR}/baselines/b81aa25-after.json"
NO_DEPS_WF="${SCRIPT_DIR}/fixtures/no-deps-workflow.json"
PERF_DRIVER="${REPO_ROOT}/plugin-kiln/tests/kiln-report-issue-batching-perf/perf-driver.sh"

REGISTRY_LIB="${REPO_ROOT}/plugin-wheel/lib/registry.sh"
RESOLVE_LIB="${REPO_ROOT}/plugin-wheel/lib/resolve.sh"
PREPROCESS_LIB="${REPO_ROOT}/plugin-wheel/lib/preprocess.sh"
KILN_REPORT_ISSUE_WF="${REPO_ROOT}/plugin-kiln/workflows/kiln-report-issue.json"

PERF_LIVE_N="${PERF_LIVE_N:-5}"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# --- 0. Static sanity --------------------------------------------------------

if [[ ! -f "$BASELINE_JSON" ]]; then
  echo "FAIL: baseline missing at $BASELINE_JSON" >&2
  exit 1
fi
if ! jq -e . "$BASELINE_JSON" >/dev/null 2>&1; then
  echo "FAIL: baseline JSON malformed" >&2
  exit 1
fi
if [[ ! -f "$PERF_DRIVER" ]]; then
  echo "FAIL: existing perf driver missing at $PERF_DRIVER" >&2
  exit 1
fi
assert_pass "static sanity (baseline JSON + perf driver present)"

# --- 1. Runtime gate ---------------------------------------------------------

if [[ ! -f "$RESOLVE_LIB" || ! -f "$PREPROCESS_LIB" || ! -f "$REGISTRY_LIB" ]]; then
  cat >&2 <<EOF
RUNTIME NOT READY: plugin-wheel/lib/{registry,resolve,preprocess}.sh missing.
This fixture is scaffolded ahead of the Phase 3 / Phase 4 / Phase 5 commits
per the team's atomic-landing protocol (NFR-F-7). Once impl-registry-resolver,
impl-preprocessor, AND the Phase 5 atomic migration commit land, re-run this
script to verify NFR-F-4 + NFR-F-6.

Static portion passed (1/1). Skipping runtime portion (exit 2).
EOF
  exit 2
fi

# Migration gate — gate (a) requires the post-PRD migrated workflow.
if [[ ! -f "$KILN_REPORT_ISSUE_WF" ]] \
   || ! jq -e '.requires_plugins // [] | index("shelf")' "$KILN_REPORT_ISSUE_WF" >/dev/null 2>&1; then
  echo "WARN: kiln-report-issue.json has not yet been migrated to declare requires_plugins:[\"shelf\"] — gate (a) is gated on T050; only gate (b) will run." >&2
  PERF_SKIP_LIVE=1
fi

# --- 2. Gate (b) NFR-F-6 — resolver overhead on no-deps workflow -----------

# Run resolver+preprocess in an out-of-process subshell so set -e in this
# script doesn't trip on transient internal exit codes inside the resolver
# functions. Each trial is a fresh `bash -c` subprocess that sources the
# libs and runs the full resolver+preprocess sequence — same shape as how
# wheel/lib/engine.sh calls them at activation.
WORKFLOW_JSON=$(jq -c . "$NO_DEPS_WF")
CALLING_PLUGIN_DIR="${REPO_ROOT}/plugin-kiln"

trial_script=$(mktemp -t perf-resolver-trial.XXXXXX)
cat > "$trial_script" <<TRIAL_EOF
#!/usr/bin/env bash
set -uo pipefail
source "$REGISTRY_LIB"
source "$RESOLVE_LIB"
source "$PREPROCESS_LIB"
WF='$WORKFLOW_JSON'
REG=\$(build_session_registry 2>/dev/null)
resolve_workflow_dependencies "\$WF" "\$REG" >/dev/null 2>&1 || exit 10
template_workflow_json "\$WF" "\$REG" "$CALLING_PLUGIN_DIR" >/dev/null 2>&1 || exit 11
exit 0
TRIAL_EOF
chmod +x "$trial_script"

RESOLVER_TIMINGS_MS=()
for i in 1 2 3 4 5; do
  START_NS=$(python3 -c 'import time; print(int(time.time_ns()))')
  if ! bash "$trial_script"; then
    echo "FAIL: resolver trial $i exited non-zero" >&2
    rm -f "$trial_script"
    exit 1
  fi
  END_NS=$(python3 -c 'import time; print(int(time.time_ns()))')
  ELAPSED_MS=$(python3 -c "print(round(($END_NS - $START_NS) / 1_000_000.0, 2))")
  RESOLVER_TIMINGS_MS+=("$ELAPSED_MS")
done
rm -f "$trial_script"

RESOLVER_MEDIAN_MS=$(python3 -c "
import statistics
vals = [${RESOLVER_TIMINGS_MS[*]/%/,}]
print(round(statistics.median(vals), 2))
")
echo "Resolver phase median (N=5): ${RESOLVER_MEDIAN_MS}ms (samples: ${RESOLVER_TIMINGS_MS[*]})"

if python3 -c "import sys; sys.exit(0 if float('$RESOLVER_MEDIAN_MS') <= 200.0 else 1)"; then
  assert_pass "NFR-F-6 — resolver+preprocess on no-deps workflow median ${RESOLVER_MEDIAN_MS}ms <= 200ms"
else
  assert_fail "NFR-F-6 — resolver+preprocess on no-deps workflow median ${RESOLVER_MEDIAN_MS}ms > 200ms"
fi

# --- 3. Gate (a) NFR-F-4 — full kiln-report-issue perf -----------------------

if [[ "${PERF_SKIP_LIVE:-0}" == "1" ]]; then
  echo "PERF_SKIP_LIVE=1 — skipping live LLM-driven gate (a) NFR-F-4." >&2
  echo "  Pre-atomic-commit: this is expected. Post-Phase-5 commit, run without PERF_SKIP_LIVE." >&2
else
  echo "Gate (a) — running live perf driver against post-PRD code (~3 min wall-clock)..." >&2
  SCRATCH=$(mktemp -d -t kiln-test-perf-kiln-report-issue.XXXXXX)
  mkdir -p "$SCRATCH/.kiln/issues/completed" "$SCRATCH/.kiln/logs" "$SCRATCH/.wheel/outputs"
  printf 'shelf_full_sync_counter=0\nshelf_full_sync_threshold=10\n' > "$SCRATCH/.shelf-config"
  cp "$REPO_ROOT/plugin-shelf/scripts/shelf-counter.sh" \
     "$REPO_ROOT/plugin-shelf/scripts/append-bg-log.sh" \
     "$REPO_ROOT/plugin-shelf/scripts/step-dispatch-background-sync.sh" \
     "$SCRATCH/"
  cp "$REPO_ROOT/plugin-kiln/tests/kiln-report-issue-batching-perf/perf-before.sh" /tmp/perf-before.sh
  cp "$REPO_ROOT/plugin-kiln/tests/kiln-report-issue-batching-perf/perf-after.sh" /tmp/perf-after.sh
  chmod +x /tmp/perf-before.sh /tmp/perf-after.sh

  # Run the driver. It writes /tmp/perf-results.tsv.
  bash "$PERF_DRIVER" "$SCRATCH" >/tmp/perf-driver.out 2>&1 || {
    echo "FAIL: perf driver crashed — see /tmp/perf-driver.out" >&2
    cat /tmp/perf-driver.out >&2 || true
    exit 1
  }

  # Compute medians of the "after" arm and compare against baseline.
  python3 <<'PY' >/tmp/perf-medians.json
import csv, json, statistics, sys
rows = list(csv.DictReader(open('/tmp/perf-results.tsv'), delimiter='\t'))
after = [r for r in rows if r['arm'] == 'after']
def med(key, cast):
    vals = []
    for r in after:
        try: vals.append(cast(r[key]))
        except: pass
    return statistics.median(vals) if vals else None
result = {
  'samples': len(after),
  'after_medians': {
    'elapsed_sec': med('elapsed_sec', float),
    'duration_api_ms': med('api_ms', float),
  }
}
json.dump(result, open('/tmp/perf-medians.json', 'w'))
print(json.dumps(result, indent=2))
PY

  POST_ELAPSED=$(jq -r '.after_medians.elapsed_sec' /tmp/perf-medians.json)
  POST_API=$(jq -r '.after_medians.duration_api_ms' /tmp/perf-medians.json)
  THRESH_ELAPSED=$(jq -r '.thresholds.elapsed_sec_max' "$BASELINE_JSON")
  THRESH_API=$(jq -r '.thresholds.duration_api_ms_max' "$BASELINE_JSON")

  echo "Post-PRD medians: elapsed_sec=${POST_ELAPSED}s api_ms=${POST_API}ms"
  echo "Thresholds (120% of b81aa25): elapsed_sec<=${THRESH_ELAPSED}s api_ms<=${THRESH_API}ms"

  if python3 -c "import sys; sys.exit(0 if float('$POST_ELAPSED') <= float('$THRESH_ELAPSED') else 1)"; then
    assert_pass "NFR-F-4 — wall-clock median ${POST_ELAPSED}s <= ${THRESH_ELAPSED}s (120% of baseline)"
  else
    assert_fail "NFR-F-4 — wall-clock median ${POST_ELAPSED}s > ${THRESH_ELAPSED}s (regression > 20%)"
  fi
  if python3 -c "import sys; sys.exit(0 if float('$POST_API') <= float('$THRESH_API') else 1)"; then
    assert_pass "NFR-F-4 — duration_api_ms median ${POST_API}ms <= ${THRESH_API}ms (120% of baseline)"
  else
    assert_fail "NFR-F-4 — duration_api_ms median ${POST_API}ms > ${THRESH_API}ms (regression > 20%)"
  fi

  echo "Driver output saved at /tmp/perf-driver.out" >&2
  echo "TSV saved at /tmp/perf-results.tsv" >&2
fi

# --- Summary ---------------------------------------------------------------
echo
echo "--- Results: ${pass} passed, ${fail} failed ---"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
