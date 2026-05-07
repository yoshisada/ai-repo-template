#!/usr/bin/env bash
# SessionStart hook shim. Fast-paths the no-active-workflow case (the
# primary purpose of session-start is workflow resume; without a .wheel/
# dir there's nothing to resume).
# FR-007: SessionStart hook entry point.
set -euo pipefail

if [[ ! -d .wheel ]]; then
  cat >/dev/null
  echo '{}'
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_HOOK="$PLUGIN_ROOT/dist/hooks/session-start.js"

exec node "$DIST_HOOK" "$@"
