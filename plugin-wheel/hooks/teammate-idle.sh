#!/usr/bin/env bash
# TeammateIdle hook shim. Fast-paths the no-active-workflow case.
# FR-007: TeammateIdle hook entry point.
set -euo pipefail

if [[ ! -d .wheel ]]; then
  cat >/dev/null
  echo '{}'
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_HOOK="$PLUGIN_ROOT/dist/hooks/teammate-idle.js"

exec node "$DIST_HOOK" "$@"
