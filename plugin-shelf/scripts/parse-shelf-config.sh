#!/usr/bin/env bash
# parse-shelf-config.sh — defensive `.shelf-config` parser
#
# Emits a structured block on stdout:
#
#   ## SHELF_CONFIG_PARSED
#   slug = <parsed slug or empty>
#   base_path = <parsed base_path or empty>
#   dashboard_path = <parsed dashboard_path or empty>
#   shelf_config_present = <true|false>
#   ## END_SHELF_CONFIG_PARSED
#
# If `.shelf-config` is missing, all four value lines are emitted with empty
# values and `shelf_config_present = false`. This is the downstream
# `obsidian-write` agent's sole input for the path-source decision — no
# ad-hoc parsing elsewhere.
#
# Contract: specs/pipeline-input-completeness/contracts/interfaces.md §3
# Precedent: plugin-shelf/scripts/shelf-counter.sh `_read_key()`
# Portability: invoked as `bash "${WORKFLOW_PLUGIN_DIR}/scripts/parse-shelf-config.sh"`
# per CLAUDE.md plugin-workflow-portability invariant.

set -u

SHELF_CONFIG="${SHELF_CONFIG:-.shelf-config}"

# read_shelf_key <key>: emit the trimmed, quote-stripped value for <key> in
# .shelf-config, or empty string if the file is missing / key is absent.
# - Skips blank lines and comment lines (starting with #) via the key-anchored grep.
# - Strips surrounding whitespace, leading `./` is left alone (paths are treated
#   opaquely here; the consumer decides what to do).
# - Strips surrounding double-quotes OR single-quotes from the value.
# - Handles CRLF line endings via `tr -d '\r'`.
# - `tail -1` — last occurrence wins (matches shelf-counter.sh `_read_key`).
read_shelf_key() {
  local key="$1"
  [ -f "$SHELF_CONFIG" ] || { printf ''; return 0; }
  # Order matters:
  #   1. grep the key-anchored line (skips blanks / `#` lines automatically).
  #   2. tail -1: last occurrence wins.
  #   3. strip CRLF first — otherwise the trailing `\r` prevents `$` from
  #      matching immediately after a closing quote in the quote-strip passes.
  #   4. strip the `key =` prefix (with any whitespace around the `=`).
  #   5. strip surrounding whitespace on the value body.
  #   6. strip surrounding double-quotes, then single-quotes.
  #   7. final trim of any residual space/tab.
  grep -E "^${key}[[:space:]]*=" "$SHELF_CONFIG" 2>/dev/null \
    | tail -1 \
    | tr -d '\r' \
    | sed -E "s/^${key}[[:space:]]*=[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//' \
    | sed -E 's/^"(.*)"$/\1/' \
    | sed -E "s/^'(.*)'\$/\\1/" \
    | tr -d ' \t'
}

present="false"
[ -f "$SHELF_CONFIG" ] && present="true"

echo "## SHELF_CONFIG_PARSED"
echo "slug = $(read_shelf_key slug)"
echo "base_path = $(read_shelf_key base_path)"
echo "dashboard_path = $(read_shelf_key dashboard_path)"
echo "shelf_config_present = ${present}"
echo "## END_SHELF_CONFIG_PARSED"
