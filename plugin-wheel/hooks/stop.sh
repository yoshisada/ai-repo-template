#!/usr/bin/env bash
# Shell shim: delegates to TypeScript implementation
# FR-007: Stop hook entry point
# T020: Phase 4 fallback - invokes native node binary
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_HOOK="$PLUGIN_ROOT/dist/hooks/stop.js"

exec node --import tsx "$DIST_HOOK" "$@"