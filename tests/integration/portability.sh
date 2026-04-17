#!/usr/bin/env bash
# tests/integration/portability.sh
# Acceptance Scenario US5#1 (FR-016): every command step in the sub-workflow
# JSON resolves via ${WORKFLOW_PLUGIN_DIR} — NEVER via a repo-relative
# plugin-shelf/scripts/... path. A violation silently breaks consumer repos
# (No such file or directory), so this gate is mandatory.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORKFLOW="$ROOT/plugin-shelf/workflows/propose-manifest-improvement.json"

fail=0

if [ ! -f "$WORKFLOW" ]; then
  printf 'FAIL workflow-exists — %s\n' "$WORKFLOW"; exit 1
fi

# 1. No command step may reference plugin-shelf/scripts/ repo-relative.
violations=$(jq -r '.steps[] | select(.type=="command") | .command' "$WORKFLOW" | grep -F 'plugin-shelf/scripts/' || true)
if [ -n "$violations" ]; then
  printf 'FAIL no-repo-relative-paths — violations:\n%s\n' "$violations"; fail=1
else
  printf 'PASS no-repo-relative-paths\n'
fi

# 2. Every command step MUST include ${WORKFLOW_PLUGIN_DIR}.
cmd_steps=$(jq -r '.steps[] | select(.type=="command") | .command' "$WORKFLOW")
if [ -z "$cmd_steps" ]; then
  printf 'FAIL has-command-steps — no command steps found (should have at least one)\n'; fail=1
fi
missing=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  if ! printf '%s' "$line" | grep -qF '${WORKFLOW_PLUGIN_DIR}'; then
    printf 'FAIL command-uses-workflow-plugin-dir — line: %s\n' "$line"
    missing=1
  fi
done <<< "$cmd_steps"
if [ "$missing" -eq 0 ]; then
  printf 'PASS command-uses-workflow-plugin-dir\n'
else
  fail=1
fi

# 3. Companion check — caller workflows don't need portability fixes themselves
# (they delegate to shelf:propose-manifest-improvement via type:"workflow"
# steps, not command steps), but verify no regression in the sub-workflow
# dispatch script location.
if [ ! -x "$ROOT/plugin-shelf/scripts/write-proposal-dispatch.sh" ]; then
  printf 'FAIL dispatch-script-exists-and-executable\n'; fail=1
else
  printf 'PASS dispatch-script-exists-and-executable\n'
fi

[ "$fail" -eq 0 ]
