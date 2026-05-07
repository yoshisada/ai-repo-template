#!/usr/bin/env bash
# Stop hook shim. Fast-paths the no-active-workflow case (saves ~30-50ms
# per fire by skipping node startup + module load); slow path delegates
# to the TS implementation, identical to pre-fast-path behavior.
# FR-007: Stop hook entry point.
set -euo pipefail

# Fast-path: no active wheel workflow → nothing to do. Drain stdin so
# Claude Code's parent write doesn't EPIPE, emit an empty no-decision
# JSON object, and exit before paying node startup cost.
if [[ ! -d .wheel ]]; then
  cat >/dev/null
  echo '{}'
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_HOOK="$PLUGIN_ROOT/dist/hooks/stop.js"

exec node "$DIST_HOOK" "$@"
