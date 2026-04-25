#!/usr/bin/env bash
# research-runner-axis-no-monotonic-clock/run.sh — SC-AE-009 anchor.
#
# Validates NFR-AE-006 monotonic-clock probe ladder:
# When PATH is stripped of python3, gdate, AND /bin/date is non-functional,
# the probe MUST exit 2 with `Bail out! no monotonic %N-precision clock
# available; install python3 (preferred) or coreutils (gdate)`. NEVER falls
# back to integer-second `date +%s`.
#
# Pure-shell unit fixture per the test substrate hierarchy. Drives
# resolve-monotonic-clock.sh directly with a synthetic empty PATH.
set -euo pipefail

here=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )
repo_root=$( cd -- "$here/../../.." && pwd )
clock="$repo_root/plugin-wheel/scripts/harness/resolve-monotonic-clock.sh"

assertions=0
fail() { echo "FAIL: $*"; exit 1; }

# A1: probe succeeds in normal env (resolves SOME clock).
# Anchors: NFR-AE-006 — at least one rung resolves on a sane host.
out=$(bash "$clock")
case "$out" in
  "python3 -c 'import time; print(time.monotonic())'") ;;
  "gdate +%s.%N") ;;
  "/bin/date +%s.%N") ;;
  *) fail "unexpected probe output: $out" ;;
esac
assertions=$((assertions + 1))

# A2: with PATH=/empty + /bin/date stripped → bail-out.
# Anchors: SC-AE-009 — synthetic test by mocking out python3, gdate, /bin/date.
# Strategy: PATH=/empty BUT we also need /bin/date stripped. Create a tmp
# bin dir with NO matching binaries, set PATH, and run with a fake /bin/date
# by symlinking to /dev/null OR just preventing the rung from resolving.
# Simpler: nuke PATH so command -v fails, AND override /bin/date check by
# placing a no-op shell that exits non-zero. We can't actually remove
# /bin/date on the host, so we exploit the regex check — the script tests
# that /bin/date stdout matches `^[0-9]+\.[0-9]{6,}$`. On macOS this WILL
# match, so we can't trick it without overriding /bin/date itself.
#
# Workaround: invoke the script with PATH set to an empty dir AND a wrapped
# `/bin/date` that intentionally fails — by setting our own PATH and shadowing
# /bin/date with a non-existent path is infeasible. Instead, override the
# binary lookup at the shell level by mocking the script: we copy the script
# into a tmp location, then patch the /bin/date rung to point at a non-existent
# path. This validates the bail-out path through the OTHER two rungs failing.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$clock" "$tmp/clock.sh"
# Replace the /bin/date references with /tmp/nonexistent-date so the rung fails.
sed -i.bak 's|/bin/date|/tmp/nonexistent-date-XXXXX|g' "$tmp/clock.sh"

# Run with a minimal PATH containing only /bin (for `bash` / shell builtins)
# but no python3 / gdate. We additionally re-stub the script so command -v
# python3 always returns false.
sed -i.bak2 's|command -v python3|command -v python3-DOES-NOT-EXIST|g' "$tmp/clock.sh"
sed -i.bak3 's|command -v gdate|command -v gdate-DOES-NOT-EXIST|g' "$tmp/clock.sh"
set +e
out=$(bash "$tmp/clock.sh" 2>&1)
rc=$?
set -e

[[ $rc -eq 2 ]] || fail "expected exit 2 with no clock available, got $rc (output: $out)"
echo "$out" | grep -qF "Bail out! no monotonic %N-precision clock available" || \
  fail "diagnostic missing 'Bail out! no monotonic %N-precision clock available' (output: $out)"
echo "$out" | grep -qF "install python3 (preferred) or coreutils (gdate)" || \
  fail "diagnostic missing remediation hint (output: $out)"
assertions=$((assertions + 3))

# A3: NEVER fall back to integer-second `date +%s` — the diagnostic must NOT
# resolve to anything when all rungs fail.
# Anchors: NFR-AE-007 loud-failure invariant.
echo "$out" | grep -q 'date +%s$' && \
  fail "FORBIDDEN: probe leaked 'date +%s' fallback (loud-failure violation)"
assertions=$((assertions + 1))

# A4: probe is deterministic — running twice on the same host returns the
# same string both times.
# Anchors: NFR-AE-006 (probe order MUST be deterministic).
out1=$(bash "$clock")
out2=$(bash "$clock")
[[ $out1 == $out2 ]] || fail "probe non-deterministic: '$out1' vs '$out2'"
assertions=$((assertions + 1))

echo "PASS ($assertions assertions)"
