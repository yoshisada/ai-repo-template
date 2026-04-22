#!/usr/bin/env bash
# shelf-counter.sh — counter-gated full-sync decision helper
#
# Subcommands:
#   read                     — print {"counter": N, "threshold": N} (no mutation beyond ensure-defaults)
#   increment-and-decide     — atomic read-increment-decide-writeback under flock
#   ensure-defaults          — idempotently append missing .shelf-config keys
#
# Contract: specs/report-issue-speedup/contracts/interfaces.md §3
# Format: `.shelf-config` is `key = value` lines with padded equals.
# Locking: flock on sibling `${SHELF_CONFIG}.lock`. Fallback: unlocked (±1 drift per FR-006).

set -u

SHELF_CONFIG="${SHELF_CONFIG:-.shelf-config}"
LOCK_FILE="${LOCK_FILE:-${SHELF_CONFIG}.lock}"
DEFAULT_COUNTER="${DEFAULT_COUNTER:-0}"
DEFAULT_THRESHOLD="${DEFAULT_THRESHOLD:-10}"

# Ensure .shelf-config exists — create an empty one if missing so ensure-defaults
# can append. Callers that need slug/base_path are expected to have created it
# via shelf-create or init.
_ensure_file() {
  if [ ! -f "$SHELF_CONFIG" ]; then
    : > "$SHELF_CONFIG"
  fi
}

_has_key() {
  local key="$1"
  grep -qE "^${key}[[:space:]]*=" "$SHELF_CONFIG" 2>/dev/null
}

_ensure_key() {
  local key="$1" default="$2"
  if ! _has_key "$key"; then
    printf '%s = %s\n' "$key" "$default" >> "$SHELF_CONFIG"
  fi
}

_read_key() {
  local key="$1" default="$2"
  local v
  v=$(grep -E "^${key}[[:space:]]*=" "$SHELF_CONFIG" 2>/dev/null | tail -1 \
      | sed -E 's/^[^=]+=[[:space:]]*//' \
      | tr -d ' \t\r')
  if [ -z "${v:-}" ]; then
    v="$default"
  fi
  printf '%s\n' "$v"
}

# Write (or replace) a single key=value line atomically via tempfile+mv.
# Preserves all other lines verbatim (comments, blanks, other keys).
_write_key() {
  local key="$1" val="$2" tmp
  tmp="$(mktemp "${SHELF_CONFIG}.XXXXXX")" || return 1
  awk -v key="$key" -v val="$val" '
    BEGIN { replaced = 0 }
    {
      # Match "<key>" optionally followed by whitespace then "="
      if (!replaced && match($0, "^" key "[[:space:]]*=") ) {
        print key " = " val
        replaced = 1
        next
      }
      print
    }
    END { if (!replaced) print key " = " val }
  ' "$SHELF_CONFIG" > "$tmp" && mv "$tmp" "$SHELF_CONFIG"
}

ensure_defaults() {
  _ensure_file
  _ensure_key "shelf_full_sync_counter" "$DEFAULT_COUNTER"
  _ensure_key "shelf_full_sync_threshold" "$DEFAULT_THRESHOLD"
}

cmd_read() {
  ensure_defaults
  local counter threshold
  counter=$(_read_key "shelf_full_sync_counter" "$DEFAULT_COUNTER")
  threshold=$(_read_key "shelf_full_sync_threshold" "$DEFAULT_THRESHOLD")
  printf '{"counter":%s,"threshold":%s}\n' "$counter" "$threshold"
}

# Critical section — under lock if flock is available.
_increment_and_decide_body() {
  ensure_defaults
  local before threshold after action new_val written_after
  before=$(_read_key "shelf_full_sync_counter" "$DEFAULT_COUNTER")
  threshold=$(_read_key "shelf_full_sync_threshold" "$DEFAULT_THRESHOLD")

  # Defensive: if either is non-integer, fall back to default.
  case "$before" in *[!0-9]*|'') before="$DEFAULT_COUNTER" ;; esac
  case "$threshold" in *[!0-9]*|'') threshold="$DEFAULT_THRESHOLD" ;; esac
  [ "$threshold" -lt 1 ] && threshold="$DEFAULT_THRESHOLD"

  after=$((before + 1))
  if [ "$after" -ge "$threshold" ]; then
    action="full-sync"
    new_val=0
    written_after=0
  else
    action="increment"
    new_val="$after"
    written_after="$after"
  fi

  _write_key "shelf_full_sync_counter" "$new_val"

  printf '{"before":%d,"after":%d,"threshold":%d,"action":"%s"}\n' \
    "$before" "$written_after" "$threshold" "$action"
}

cmd_increment_and_decide() {
  _ensure_file
  if command -v flock >/dev/null 2>&1; then
    # Open lock fd, acquire exclusive lock, run body, release on fd close.
    {
      flock -x 9
      _increment_and_decide_body
    } 9>"$LOCK_FILE"
  else
    _increment_and_decide_body
  fi
}

main() {
  local sub="${1:-}"
  case "$sub" in
    read)                    cmd_read ;;
    increment-and-decide)    cmd_increment_and_decide ;;
    ensure-defaults)         ensure_defaults ;;
    ''|-h|--help|help)
      cat <<EOF
Usage: $0 <subcommand>

Subcommands:
  read                     Print {"counter":N,"threshold":N}
  increment-and-decide     Atomic RMW; print {"before","after","threshold","action"}
  ensure-defaults          Append missing .shelf-config keys (idempotent)

Env overrides:
  SHELF_CONFIG      (default: .shelf-config)
  LOCK_FILE         (default: \$SHELF_CONFIG.lock)
  DEFAULT_COUNTER   (default: 0)
  DEFAULT_THRESHOLD (default: 10)
EOF
      ;;
    *)
      printf 'shelf-counter.sh: unknown subcommand: %s\n' "$sub" >&2
      exit 2
      ;;
  esac
}

main "$@"
