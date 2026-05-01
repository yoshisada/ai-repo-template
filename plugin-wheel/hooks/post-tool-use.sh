#!/usr/bin/env bash
# True shell shim: delegates to TypeScript implementation only
# FR-007: PostToolUse hook entry point
# T020: Phase 4 fallback - invokes native node binary
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_HOOK="$PLUGIN_ROOT/dist/hooks/post-tool-use.js"

# Execute from repo root so .wheel state files are created in the right place
# (the calling user's session cwd, not inside plugin-wheel/)
exec node "$DIST_HOOK" "$@"