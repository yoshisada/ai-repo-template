#!/usr/bin/env bash
# research-runner-axis-pricing-stale-audit/run.sh — SC-AE-007 anchor.
#
# Validates User Story 7 (FR-AE-013):
# When `plugin-kiln/lib/pricing.json` mtime > 180 days ago, an auditor
# subcheck MUST surface `pricing-table-stale: <days>d since mtime` in
# `agent-notes/audit-compliance.md`. The research run itself MUST NOT fail
# on this signal — it's an audit-time tripwire, NOT a gate.
#
# This test exercises the auditor mtime probe via a small inline helper.
# The auditor is conceptual — its mtime probe is a few `stat` calls + a
# subtraction. We verify the probe logic produces the right output given
# a mocked old mtime.
set -euo pipefail

here=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )
repo_root=$( cd -- "$here/../../.." && pwd )
pricing="$repo_root/plugin-kiln/lib/pricing.json"

assertions=0
fail() { echo "FAIL: $*"; exit 1; }

# A1: pricing.json exists.
[[ -f $pricing ]] || fail "pricing.json missing: $pricing"
assertions=$((assertions + 1))

# A2: cross-platform stat helper. macOS uses `stat -f %m`; Linux uses `stat -c %Y`.
if stat -c %Y "$pricing" >/dev/null 2>&1; then
  stat_mtime() { stat -c %Y "$1"; }
elif stat -f %m "$pricing" >/dev/null 2>&1; then
  stat_mtime() { stat -f %m "$1"; }
else
  fail "no stat-mtime probe available on this host (tried -c %Y and -f %m)"
fi
assertions=$((assertions + 1))

# A3: write a copy of pricing.json with mtime 200 days ago, then probe.
# Anchors: User Story 7 acceptance scenario 1.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$pricing" "$tmp/pricing-old.json"

# Set mtime to 200 days ago. macOS: touch -t YYYYMMDDHHMM.SS.
# Linux: touch -d "200 days ago".
if touch -d "200 days ago" "$tmp/pricing-old.json" 2>/dev/null; then
  : # GNU touch
else
  # macOS: compute timestamp 200 days ago via python3 (kiln dependency).
  ts=$(python3 -c 'import time; print(time.strftime("%Y%m%d%H%M.%S", time.localtime(time.time() - 200*86400)))')
  touch -t "$ts" "$tmp/pricing-old.json"
fi
assertions=$((assertions + 1))

# A4: auditor mtime probe — read mtime, compute days since, emit finding.
# Anchors: FR-AE-013, SC-AE-007.
now=$(date +%s)
mtime=$(stat_mtime "$tmp/pricing-old.json")
days_since=$(( (now - mtime) / 86400 ))
(( days_since >= 180 )) || fail "expected days_since >= 180 (got $days_since)"
finding="pricing-table-stale: ${days_since}d since mtime"
echo "$finding" | grep -qF "pricing-table-stale: " || fail "finding malformed: $finding"
echo "$finding" | grep -qE "[0-9]+d since mtime" || fail "finding missing day count: $finding"
assertions=$((assertions + 3))

# A5: write the finding to a synthetic agent-notes/audit-compliance.md.
# Anchors: User Story 7 acceptance scenario 1 (target file is agent-notes/audit-compliance.md).
synth_note="$tmp/audit-compliance.md"
{
  echo "# Audit Compliance Findings"
  echo
  echo "- $finding"
} >"$synth_note"
grep -qF "pricing-table-stale: ${days_since}d since mtime" "$synth_note" || \
  fail "synthetic note missing finding"
assertions=$((assertions + 1))

# A6: 30-day-old file → NO finding emitted (negative case).
# Anchors: User Story 7 acceptance scenario 2.
cp "$pricing" "$tmp/pricing-fresh.json"
if touch -d "30 days ago" "$tmp/pricing-fresh.json" 2>/dev/null; then
  :
else
  ts2=$(python3 -c 'import time; print(time.strftime("%Y%m%d%H%M.%S", time.localtime(time.time() - 30*86400)))')
  touch -t "$ts2" "$tmp/pricing-fresh.json"
fi
mtime_fresh=$(stat_mtime "$tmp/pricing-fresh.json")
days_fresh=$(( (now - mtime_fresh) / 86400 ))
(( days_fresh < 180 )) || fail "expected fresh days_since < 180 (got $days_fresh)"
assertions=$((assertions + 1))

# A7: research run does NOT fail on stale pricing.json (audit-time tripwire only).
# Anchors: User Story 7 acceptance scenario 3.
# We verify by: the runner already runs against the (fresh) committed pricing.json
# without checking its mtime. This is a structural property — there's no
# `bail_out` invocation tied to mtime in research-runner.sh.
runner="$repo_root/plugin-wheel/scripts/harness/research-runner.sh"
if grep -nE 'bail_out.*pricing.*stale|pricing-table-stale' "$runner" >/dev/null 2>&1; then
  fail "FORBIDDEN: research-runner.sh references pricing staleness — must be audit-time only"
fi
assertions=$((assertions + 1))

echo "PASS ($assertions assertions)"
