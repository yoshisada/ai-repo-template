#!/usr/bin/env bash
# SubagentStop hook shim. Fast-paths the no-active-workflow case.
# FR-007: SubagentStop hook entry point.
set -euo pipefail

# Fast-path: no active workflow → no team to coordinate. Emit empty +
# exit before paying node startup.
if [[ ! -d .wheel ]]; then
  cat >/dev/null
  echo '{}'
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_HOOK="$PLUGIN_ROOT/dist/hooks/subagent-stop.js"

exec node "$DIST_HOOK" "$@"
