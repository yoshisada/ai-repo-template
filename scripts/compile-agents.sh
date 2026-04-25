#!/usr/bin/env bash
# compile-agents.sh — PostToolUse hook entrypoint for plugin-*/agents/*.md edits.
#
# Reads the PostToolUse JSON envelope from stdin, extracts the edited file
# path, and recompiles the affected plugin's agents/ directory if the path
# matches plugin-*/agents/**/*.md.
#
# Behavior is gated on the presence of a real compiler — see the
# 2026-04-25-agent-prompt-includes roadmap item. Until that ships, this
# script is a structured no-op that logs the trigger and exits 0.
#
# Portability:
#   - Resolves the repo root via ${CLAUDE_PROJECT_DIR} (set by Claude Code
#     for hooks) with a fallback to the script's own location.
#   - Compile destination is overridable via env var
#     KILN_COMPILED_AGENTS_DIR. Default is in-place (sources and compiled
#     output share the same path), per the roadmap item's v1 recommendation.
#   - All paths internal to the script are relative to REPO_ROOT — no
#     hardcoded absolute paths.

set -u

# --- Resolve repo root portably ----------------------------------------------
REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$REPO_ROOT" ]; then
  # Fallback: derive from script location (scripts/compile-agents.sh → repo root)
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
fi

LOG_DIR="$REPO_ROOT/.kiln/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/compile-agents-$(date -u +%Y-%m-%d).log"

log() {
  printf '%s | %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG_FILE"
}

# --- Read PostToolUse JSON envelope from stdin -------------------------------
INPUT="$(cat || true)"
if [ -z "$INPUT" ]; then
  # No envelope (manual invocation or mis-wired hook) — exit cleanly.
  exit 0
fi

# Extract the file path the tool acted on. Edit/Write/MultiEdit all use
# tool_input.file_path. Fall back to grep if jq isn't on PATH.
if command -v jq >/dev/null 2>&1; then
  FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')"
else
  FILE_PATH="$(printf '%s' "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]+)"/\1/')"
  TOOL_NAME="$(printf '%s' "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"tool_name"[[:space:]]*:[[:space:]]*"([^"]+)"/\1/')"
fi

[ -z "$FILE_PATH" ] && exit 0

# --- Match plugin-*/agents/**/*.md ------------------------------------------
# Normalize to a repo-relative path for the regex match.
case "$FILE_PATH" in
  "$REPO_ROOT"/*) REL_PATH="${FILE_PATH#$REPO_ROOT/}" ;;
  /*)             REL_PATH="$FILE_PATH" ;;
  *)              REL_PATH="$FILE_PATH" ;;
esac

if ! [[ "$REL_PATH" =~ ^plugin-[^/]+/agents/.+\.md$ ]]; then
  exit 0
fi

# Identify the plugin (e.g., "plugin-kiln" → "kiln")
PLUGIN_DIR="${REL_PATH%%/agents/*}"
PLUGIN_NAME="${PLUGIN_DIR#plugin-}"

log "trigger | tool=$TOOL_NAME | file=$REL_PATH | plugin=$PLUGIN_NAME"

# --- Resolve compile destination --------------------------------------------
# Override with KILN_COMPILED_AGENTS_DIR if set; default is in-place.
DEST="${KILN_COMPILED_AGENTS_DIR:-$REPO_ROOT/$PLUGIN_DIR/agents}"

# --- Invoke the real compiler if present ------------------------------------
# The compiler ships with the 2026-04-25-agent-prompt-includes roadmap item.
# Expected location: plugin-kiln/scripts/agent-includes/resolve.sh.
COMPILER="$REPO_ROOT/plugin-kiln/scripts/agent-includes/resolve.sh"
if [ -x "$COMPILER" ]; then
  log "invoke  | compiler=$COMPILER | dest=$DEST"
  if "$COMPILER" --plugin "$PLUGIN_NAME" --dest "$DEST" >> "$LOG_FILE" 2>&1; then
    log "result  | ok"
  else
    log "result  | fail (exit=$?) — see lines above"
  fi
  exit 0
fi

# Compiler not yet installed — structured no-op until the roadmap item ships.
log "noop    | compiler not yet installed at $COMPILER (roadmap: 2026-04-25-agent-prompt-includes)"
exit 0
