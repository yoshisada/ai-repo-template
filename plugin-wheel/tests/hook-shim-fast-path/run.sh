#!/usr/bin/env bash
# Hook-shim fast-path coverage. Asserts that the bash shims under
# plugin-wheel/hooks/ skip node startup when there's no active wheel
# workflow, while still delegating to node when one IS active.
#
# Why this exists: every claude session that has the wheel plugin
# installed pays a hook tax on every tool call. Pre-fast-path that was
# ~40ms/fire (cold-warm node + module load). Fast-path collapses it to
# ~10ms when .wheel/ doesn't exist (the 99% case for non-wheel sessions).
# This fixture is a regression trap — it asserts on output SHAPE, not
# wall-clock (which is too jittery on shared CI to gate on cleanly).
#
# Coverage: post-tool-use.sh + stop.sh (the two hooks that fire most
# often). The remaining 4 simple shims share the exact same fast-path
# pattern; covering 2 representatively defends the invariant.
#
# Shape contract:
#   Fast-path post-tool-use.sh: exactly `{"hookEventName":"PostToolUse"}`
#   Fast-path stop.sh:          exactly `{}`
#   Slow-path post-tool-use.sh: stderr contains `wheel post-tool-use:`
#                               (the TS hook's activation log line)
# The fast-path branch never emits the slow-path's stderr signature —
# that's the tripwire.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PTU="${REPO_ROOT}/plugin-wheel/hooks/post-tool-use.sh"
STOP="${REPO_ROOT}/plugin-wheel/hooks/stop.sh"

if [[ ! -x "$PTU" || ! -x "$STOP" ]]; then
  echo "FAIL: hook shims missing or not executable" >&2
  exit 1
fi

STAGE="$(mktemp -d -t hook-fast-path-XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
cd "$STAGE"

PASS=0
FAIL=0

# -----------------------------------------------------------------------------
# Assertion 1: post-tool-use.sh fast-path emits the bare PostToolUse
# envelope without invoking node when .wheel/ does not exist AND command
# lacks activate.sh tokens. Tripwire: stderr empty (TS hook always logs
# a "wheel post-tool-use:" line on activate path; absence proves we
# never reached the TS hook).
# -----------------------------------------------------------------------------
echo "[1/4] post-tool-use.sh fast-path (no .wheel/, no activate)"
PAYLOAD='{"session_id":"x","agent_id":"y","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"exit_code":0}}'
stdout_file=$(mktemp); stderr_file=$(mktemp)
echo "$PAYLOAD" | "$PTU" >"$stdout_file" 2>"$stderr_file"; rc=$?
stdout_val=$(cat "$stdout_file")
stderr_val=$(cat "$stderr_file")
rm -f "$stdout_file" "$stderr_file"
if [[ $rc -eq 0 ]] \
  && [[ "$stdout_val" == '{"hookEventName":"PostToolUse"}' ]] \
  && [[ -z "$stderr_val" ]]; then
  echo "  [OK] fast-path output exact + stderr empty (no node invocation)"
  PASS=$((PASS+1))
else
  echo "  [FAIL] rc=$rc" >&2
  echo "  stdout: $stdout_val" >&2
  echo "  stderr: $stderr_val" >&2
  FAIL=$((FAIL+1))
fi

# -----------------------------------------------------------------------------
# Assertion 2: stop.sh fast-path emits `{}` exactly with empty stderr.
# Same tripwire shape — slow-path emits `{"decision":"approve"}` (when
# no state matches) plus stderr noise; fast-path is byte-clean.
# -----------------------------------------------------------------------------
echo "[2/4] stop.sh fast-path (no .wheel/)"
stdout_file=$(mktemp); stderr_file=$(mktemp)
echo '{}' | "$STOP" >"$stdout_file" 2>"$stderr_file"; rc=$?
stdout_val=$(cat "$stdout_file")
stderr_val=$(cat "$stderr_file")
rm -f "$stdout_file" "$stderr_file"
if [[ $rc -eq 0 ]] && [[ "$stdout_val" == '{}' ]] && [[ -z "$stderr_val" ]]; then
  echo "  [OK] fast-path output exact + stderr empty"
  PASS=$((PASS+1))
else
  echo "  [FAIL] rc=$rc stdout='$stdout_val' stderr='$stderr_val'" >&2
  FAIL=$((FAIL+1))
fi

# -----------------------------------------------------------------------------
# Assertion 3: post-tool-use.sh slow-path engages when command contains
# activate.sh, even with no .wheel/ dir (activation creates the dir).
# Tripwire: stderr contains the TS hook's activation log prefix.
# -----------------------------------------------------------------------------
echo "[3/4] post-tool-use.sh slow-path (activate.sh in command, no .wheel/)"
mkdir -p workflows
echo '{"name":"x","steps":[{"id":"s1","type":"command","command":"true"}]}' > workflows/x.json
PAYLOAD_ACTIVATE="{\"session_id\":\"x\",\"agent_id\":\"y\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"${REPO_ROOT}/plugin-wheel/bin/activate.sh x\"},\"tool_response\":{\"exit_code\":0}}"
combined=$(echo "$PAYLOAD_ACTIVATE" | "$PTU" 2>&1); rc=$?
if [[ $rc -eq 0 ]] && grep -q 'wheel post-tool-use:' <<<"$combined"; then
  echo "  [OK] slow-path engaged (TS hook log line present)"
  PASS=$((PASS+1))
else
  echo "  [FAIL] rc=$rc — fast-path incorrectly short-circuited an activation" >&2
  echo "  combined: $combined" >&2
  FAIL=$((FAIL+1))
fi
rm -rf .wheel

# -----------------------------------------------------------------------------
# Assertion 4: stop.sh slow-path engages when .wheel/ exists. The TS hook
# emits a JSON envelope distinct from the fast-path's bare `{}`. The
# specific shape depends on internal state; we just need to confirm the
# fast-path's exact `{}` is NOT the output (i.e. node ran).
# -----------------------------------------------------------------------------
echo "[4/4] stop.sh slow-path (.wheel/ exists)"
mkdir .wheel
stdout_val=$(echo '{"session_id":"x","agent_id":"y"}' | "$STOP" 2>/dev/null || true)
if [[ "$stdout_val" != '{}' ]] && [[ -n "$stdout_val" ]]; then
  echo "  [OK] slow-path engaged (output shape distinct from fast-path)"
  PASS=$((PASS+1))
else
  echo "  [FAIL] output='$stdout_val' — fast-path leaked through with .wheel/ present" >&2
  FAIL=$((FAIL+1))
fi

echo
if (( FAIL == 0 )); then
  echo "PASS: hook-shim-fast-path ($PASS/4 assertions)"
  exit 0
else
  echo "FAIL: hook-shim-fast-path ($FAIL/4 assertions failed)"
  exit 1
fi
