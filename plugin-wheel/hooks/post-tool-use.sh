#!/usr/bin/env bash
# PostToolUse hook shim. Fast-paths the no-active-workflow + no-activation
# case (the 99% case for any session that has the wheel plugin installed
# but isn't currently driving a workflow). Slow path delegates to the TS
# implementation, identical to pre-fast-path behavior.
# FR-007: PostToolUse hook entry point.
set -euo pipefail

# Read stdin once; we need it for both the fast-path's activate-detection
# grep and the slow-path's downstream node invocation. Tool-call payloads
# are small (KB), so the round-trip through a shell variable is cheap.
INPUT=$(cat)

# Fast-path: no active wheel workflow AND command body has no
# activate.sh/deactivate.sh tokens. Saves ~30-50ms per fire by skipping
# node startup + module load. The activate-detection grep is the same
# substring search the TS hook would do later — short-circuiting it here
# avoids the cold start.
if [[ ! -d .wheel ]] && ! grep -qE 'activate\.sh|deactivate\.sh' <<<"$INPUT"; then
  echo '{"hookEventName":"PostToolUse"}'
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_HOOK="$PLUGIN_ROOT/dist/hooks/post-tool-use.js"

exec node "$DIST_HOOK" <<<"$INPUT"
