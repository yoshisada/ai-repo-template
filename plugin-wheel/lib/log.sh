#!/usr/bin/env bash
# log.sh — Wheel hook logging helper
#
# Writes pipe-delimited log entries to .wheel/logs/wheel.log in the CWD.
# Format:
#   ISO_TIMESTAMP|VERSION|PID|HOOK|PHASE|SESSION|STATE_FILE|KEY=VAL KEY=VAL...
#
# Logging is always on. Disable by setting WHEEL_LOG_DISABLED=1.
#
# Usage:
#   source "${WHEEL_LIB_DIR}/log.sh"
#   wheel_log_init "post-tool-use"        # called once at hook entry
#   wheel_log "enter" "tool_name=Bash"    # phase + message
#   wheel_log "resolved" "cursor=1 step_type=workflow"
#   wheel_log "dispatch" "fn=dispatch_workflow action=activate_child child=tests/count-to-100"
#   wheel_log "exit" "result=block reason=activated_child"
#
# Globals set by wheel_log_init (used by wheel_log):
#   WHEEL_LOG_HOOK     — hook name (e.g. "post-tool-use")
#   WHEEL_LOG_SESSION  — first 8 chars of session id (from WHEEL_LOG_SESSION_FULL)
#   WHEEL_LOG_STATE    — resolved state file path (caller sets via wheel_log_set_state)
#   WHEEL_LOG_VERSION  — plugin version (from plugin.json, cached)

: "${WHEEL_LOG_HOOK:=unknown}"
: "${WHEEL_LOG_SESSION:=?}"
: "${WHEEL_LOG_STATE:=?}"
: "${WHEEL_LOG_VERSION:=}"

# Resolve and cache the plugin version from plugin.json.
# Searches up from the sourcing script's directory for .claude-plugin/plugin.json.
_wheel_log_resolve_version() {
  if [[ -n "$WHEEL_LOG_VERSION" ]]; then
    return 0
  fi
  # WHEEL_LIB_DIR should be set to plugin-wheel/lib
  local plugin_json=""
  if [[ -n "${WHEEL_LIB_DIR:-}" ]]; then
    local candidate="$(cd "$WHEEL_LIB_DIR/.." 2>/dev/null && pwd)/.claude-plugin/plugin.json"
    if [[ -f "$candidate" ]]; then
      plugin_json="$candidate"
    fi
  fi
  if [[ -n "$plugin_json" ]]; then
    WHEEL_LOG_VERSION=$(jq -r '.version // "unknown"' "$plugin_json" 2>/dev/null || echo "unknown")
  else
    WHEEL_LOG_VERSION="unknown"
  fi
  export WHEEL_LOG_VERSION
}

# Initialize logging context for this hook invocation.
# Params: $1 = hook name (e.g. "post-tool-use")
#         $2 = session id (optional; shortened to first 8 chars)
wheel_log_init() {
  WHEEL_LOG_HOOK="${1:-unknown}"
  if [[ -n "${2:-}" ]]; then
    WHEEL_LOG_SESSION="${2:0:8}"
  fi
  _wheel_log_resolve_version
  export WHEEL_LOG_HOOK WHEEL_LOG_SESSION
}

# Set (or update) the resolved state file path for subsequent log calls.
# Params: $1 = state file path (or "?" if unresolved)
wheel_log_set_state() {
  WHEEL_LOG_STATE="${1:-?}"
  export WHEEL_LOG_STATE
}

# Write a log entry.
# Params: $1 = phase (e.g. "enter", "resolved", "dispatch", "exit")
#         $2 = message (key=val pairs, space-separated)
wheel_log() {
  [[ "${WHEEL_LOG_DISABLED:-0}" == "1" ]] && return 0
  local phase="${1:-}"
  local msg="${2:-}"
  local log_dir=".wheel/logs"
  local log_file="${log_dir}/wheel.log"
  mkdir -p "$log_dir" 2>/dev/null || return 0
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
    "$ts" "${WHEEL_LOG_VERSION:-unknown}" "$$" "${WHEEL_LOG_HOOK}" \
    "$phase" "${WHEEL_LOG_SESSION}" "${WHEEL_LOG_STATE}" "$msg" \
    >> "$log_file" 2>/dev/null || true
}
