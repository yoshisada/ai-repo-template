#!/usr/bin/env bash
# PreToolUse hook shim for team-name validation.
# Delegates to the TS implementation; preserves the user's session cwd
# (no `cd "$PLUGIN_ROOT"` — that breaks `.wheel/state_*.json` lookup).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_HOOK="$PLUGIN_ROOT/dist/hooks/pre-tool-use-team.js"

exec node "$DIST_HOOK" "$@"
