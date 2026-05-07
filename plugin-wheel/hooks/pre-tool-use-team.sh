#!/usr/bin/env bash
# PreToolUse hook shim for team-name + duplicate-spawn validation.
# Fast-paths the no-active-workflow case so non-team sessions don't pay
# node startup on every TeamCreate/Agent call. Slow path delegates to
# the TS implementation; user's session cwd is preserved (no cd into
# PLUGIN_ROOT — that breaks .wheel/state_*.json lookup).
set -euo pipefail

# Fast-path: no active workflow → no team to guard. Emit empty (no
# decision = allow) and exit before invoking node.
if [[ ! -d .wheel ]]; then
  cat >/dev/null
  echo '{}'
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_HOOK="$PLUGIN_ROOT/dist/hooks/pre-tool-use-team.js"

exec node "$DIST_HOOK" "$@"
