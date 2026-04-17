#!/usr/bin/env bash
# tests/integration/silent-skip.sh
# Acceptance Scenario US1#1+US1#2 (FR-007, FR-020): when the reflect step emits
# {"skip": true}, the dispatch command emits no stderr, writes no file in
# @inbox/open/, and produces an {"action":"skip"} envelope. The MCP agent's
# output file (would be empty on skip) is represented by absence of any write.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DISPATCH="$ROOT/plugin-shelf/scripts/write-proposal-dispatch.sh"
TMP=$(mktemp -d -t silent-skip.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.wheel/outputs" "$TMP/vault-root/inbox/open"
printf '{"skip": true}\n' > "$TMP/.wheel/outputs/propose-manifest-improvement.json"

inbox_before=$(find "$TMP/vault-root/inbox/open" -mindepth 1 | wc -l | tr -d ' ')
stderr_file="$TMP/stderr.log"
stdout_file="$TMP/stdout.log"

(cd "$TMP" && VAULT_ROOT="$TMP/vault-root" bash "$DISPATCH" >"$stdout_file" 2>"$stderr_file")
rc=$?

inbox_after=$(find "$TMP/vault-root/inbox/open" -mindepth 1 | wc -l | tr -d ' ')

fail=0

if [ "$rc" -ne 0 ]; then
  printf 'FAIL exit-0 (rc=%s)\n' "$rc"; fail=1
else
  printf 'PASS exit-0\n'
fi

if [ -s "$stderr_file" ]; then
  printf 'FAIL silent-stderr (stderr=%s)\n' "$(cat "$stderr_file")"; fail=1
else
  printf 'PASS silent-stderr\n'
fi

envelope=$(cat "$stdout_file")
if printf '%s' "$envelope" | jq -e '.action == "skip"' >/dev/null 2>&1; then
  action_keys=$(printf '%s' "$envelope" | jq -r 'keys | join(",")')
  if [ "$action_keys" = "action" ]; then
    printf 'PASS envelope-skip-only\n'
  else
    printf 'FAIL envelope-skip-only — keys=%s\n' "$action_keys"; fail=1
  fi
else
  printf 'FAIL envelope-action-skip — got=%s\n' "$envelope"; fail=1
fi

if [ "$inbox_after" = "$inbox_before" ]; then
  printf 'PASS inbox-unchanged (%s files)\n' "$inbox_after"
else
  printf 'FAIL inbox-unchanged — before=%s after=%s\n' "$inbox_before" "$inbox_after"; fail=1
fi

[ "$fail" -eq 0 ]
