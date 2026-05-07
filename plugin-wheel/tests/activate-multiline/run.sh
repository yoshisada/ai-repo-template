#!/usr/bin/env bash
# FR-C2 acceptance test (specs/wheel-as-runtime/spec.md User Story 1).
#
# Asserts: a multi-line Bash tool call whose body contains activate.sh
# anywhere (middle line, last line, embedded in heredoc) activates the
# workflow — state file created + log line emitted.
#
# NFR-2 (silent-failure tripwire): if the hook regresses to pre-flatten
# behavior OR drops command characters silently, this test fails with an
# identifiable error string, NOT a green-but-wrong outcome.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HOOK="${REPO_ROOT}/plugin-wheel/hooks/post-tool-use.sh"
ACTIVATE="${REPO_ROOT}/plugin-wheel/bin/activate.sh"

if [[ ! -x "$HOOK" ]]; then
  echo "FAIL: hook not found or not executable: $HOOK" >&2
  exit 1
fi
if [[ ! -x "$ACTIVATE" ]]; then
  echo "FAIL: activate.sh not found or not executable: $ACTIVATE" >&2
  exit 1
fi

# Work in a disposable staging dir so we don't pollute real .wheel/
STAGE="$(mktemp -d -t activate-multiline-XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
cd "$STAGE"

# A minimal workflow the hook can activate. Seed it into the staging dir's
# local workflows/ so the hook's relative-path lookup (workflows/<name>.json)
# succeeds without depending on `~/.claude/plugins/` discovery — clean CI
# runners have no plugin install, so plugin discovery returns empty and
# bare-name resolution silently fails (the symptom this fixture catches
# would be masked by a "missing prerequisite" failure that looks like
# the FR-C2 invariant break it's actually testing).
WORKFLOW_PATH="${REPO_ROOT}/plugin-wheel/workflows/example.json"
if [[ ! -f "$WORKFLOW_PATH" ]]; then
  echo "FAIL: fixture workflow missing: $WORKFLOW_PATH" >&2
  exit 1
fi

mkdir -p .wheel workflows
cp "$WORKFLOW_PATH" workflows/example.json

# Build the hook-input JSON payload. This is the shape Claude Code's harness
# sends on PostToolUse for a Bash tool call. Use python3 so newlines inside
# tool_input.command are JSON-escaped correctly regardless of shell quoting.
# We run three sub-cases: (1) activate.sh on middle line, (2) last line,
# (3) heredoc-embedded.
FAILURES=0

_run_case() {
  local label="$1"
  local multiline_cmd="$2"
  local shape="${3:-compliant}"   # compliant | literal (non-compliant JSON w/ raw 0x0A)

  # Fresh state-file workspace per case
  rm -f .wheel/state_*.json
  rm -f .wheel/wheel.log .wheel/hook-events.log
  rm -rf .wheel/logs

  local payload
  if [[ "$shape" == "literal" ]]; then
    # Non-compliant JSON: tool_input.command contains literal 0x0A bytes.
    # This is the actual shape Claude Code's harness has been observed to
    # emit. jq rejects (exit 4); FR-C1 fallback uses python3
    # json.loads(strict=False) which accepts.
    payload=$(python3 -c '
import sys
cmd = sys.argv[1]
def _lit(s):
    return s.replace("\\", "\\\\").replace("\"", "\\\"")
print("{\"session_id\":\"test-session\",\"agent_id\":\"test-agent\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"" + _lit(cmd) + "\",\"description\":\"multiline-activate test\"},\"tool_response\":{\"exit_code\":0,\"stdout\":\"\",\"stderr\":\"\"}}")
' "$multiline_cmd")
  else
    payload=$(python3 -c '
import json, sys
cmd = sys.argv[1]
print(json.dumps({
    "session_id": "test-session",
    "agent_id": "test-agent",
    "tool_name": "Bash",
    "tool_input": {"command": cmd, "description": "multiline-activate test"},
    "tool_response": {"exit_code": 0, "stdout": "", "stderr": ""}
}))
' "$multiline_cmd")
  fi

  # Invoke the hook with the payload. The TS hook writes its activation
  # signal to stderr; capture combined stream so we can assert on it.
  local hook_out
  if ! hook_out=$(printf '%s' "$payload" | "$HOOK" 2>&1); then
    echo "FAIL [$label]: hook exited non-zero" >&2
    echo "$hook_out" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  # Primary signal: state file was created. This is the canonical proof
  # that the hook detected activate.sh in the (potentially multi-line)
  # command body and ran the activation path.
  local state_files
  state_files=$(ls .wheel/state_*.json 2>/dev/null || true)
  if [[ -z "$state_files" ]]; then
    echo "FAIL [$label]: no .wheel/state_*.json created — hook silently missed activate.sh in multi-line input (FR-C2 invariant violated)" >&2
    echo "  payload (first 200 chars): $(printf '%s' "$payload" | head -c 200)" >&2
    echo "  hook output: $hook_out" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  # Secondary signal: stderr contains the activation-success line. The TS
  # hook writes `wheel post-tool-use: activate workflow=<name> file=<path>`
  # to stderr; we verify both fragments are present.
  if ! grep -q 'wheel post-tool-use: activate workflow=' <<<"$hook_out"; then
    echo "FAIL [$label]: hook stderr missing activation log line — activation may have completed silently or via a non-canonical path" >&2
    echo "  hook output: $hook_out" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  echo "PASS [$label]"
}

# Case 1: activate.sh on the MIDDLE line of a multi-line command.
# Pre-FR-C1 this silently missed because newlines were flattened before jq
# saw the command string.
_run_case "middle-line" "$(printf 'echo setup\n%s example\necho teardown' "$ACTIVATE")"

# Case 2: activate.sh on the LAST line (this case passed even pre-FR-C1 because
# `grep | tail -1` handles single-line collapse too — acts as a regression guard
# on FR-C4 strict-superset).
_run_case "last-line" "$(printf 'echo setup\necho more-setup\n%s example' "$ACTIVATE")"

# Case 3: activate.sh embedded inside a heredoc body (edge case called out in
# spec.md). The hook must still see it and activate.
_run_case "heredoc-body" "$(printf 'cat <<EOF\nsome content\nEOF\n%s example' "$ACTIVATE")"

# Case 4: **The actual bug shape.** Hook input JSON contains LITERAL newline
# bytes (0x0A) inside tool_input.command, which is non-compliant JSON but
# what Claude Code's harness has been observed to emit. Pre-FR-C1, this was
# handled by flattening every literal newline to a space BEFORE jq parsed —
# which "fixed" jq's complaint but destroyed the command structure, so a
# multi-line command with activate.sh on line 2+ silently missed.
#
# Post-FR-C1, the extractor tries jq first (which still rejects) and falls
# back to python3 json.loads(strict=False) which accepts literal control
# chars. The command survives with newlines intact and activate.sh matches.
_run_case "literal-newlines-in-command-field" "$(printf 'echo before\n%s example\necho after' "$ACTIVATE")" "literal"

if [[ "$FAILURES" -gt 0 ]]; then
  echo "" >&2
  echo "FAIL: $FAILURES case(s) failed — FR-C2 invariant broken" >&2
  exit 1
fi

echo ""
echo "OK: all multi-line activation cases passed (FR-C2)"
