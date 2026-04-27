#!/usr/bin/env bash
# vision-tooling FR-001 / FR-002 / FR-003 — atomic temp+mv writer for
# .kiln/vision.md.
#
# Per contracts/interfaces.md §"Theme A — vision-write-section.sh":
#   Invocation: vision-write-section.sh <flag> <text>
#   Stdout (success): "vision: wrote <flag> at <YYYY-MM-DD>"
#   Stderr (failure): "vision: <reason>"
#   Exit:
#     0  success
#     2  flag's target section not found in vision.md
#     3  lock contention / temp-write / mv failure (vision.md byte-identical
#        to pre-invocation on any non-zero exit)
#
# Side-effects: reads vision.md, writes vision.md.tmp.<pid> then atomic mv,
# acquires/releases .kiln/.vision.lock, bumps last_updated: BEFORE body
# mutation (single atomic write).
#
# Env:
#   KILN_REPO_ROOT  optional override; defaults to git rev-parse --show-toplevel
#   KILN_VISION_TODAY  optional test-determinism override for the date stamp.
#
# Lock pattern matches plugin-shelf/scripts/shelf-counter.sh — flock-when-
# available, ±1 drift accepted on macOS without flock (NFR-003).

set -euo pipefail

err() { printf 'vision: %s\n' "$*" >&2; }

if [ $# -lt 2 ]; then
  err "vision-write-section requires <flag> <text>"
  exit 1
fi

FLAG="$1"
TEXT="$2"

# Strip leading -- if present so callers may pass either form.
KEY="${FLAG#--}"

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=plugin-kiln/scripts/roadmap/vision-section-flag-map.sh
source "$SELF_DIR/vision-section-flag-map.sh"

if [ -z "${VISION_FLAG_TO_SECTION[$KEY]+x}" ]; then
  err "unknown flag: --${KEY}"
  exit 1
fi
SECTION="${VISION_FLAG_TO_SECTION[$KEY]}"
OP="${VISION_FLAG_OP[$KEY]}"

REPO_ROOT="${KILN_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
VISION_FILE="$REPO_ROOT/.kiln/vision.md"
LOCK_DIR="$REPO_ROOT/.kiln"
LOCK_FILE="$LOCK_DIR/.vision.lock"
TODAY="${KILN_VISION_TODAY:-$(date -u +%Y-%m-%d)}"

if [ ! -f "$VISION_FILE" ]; then
  err ".kiln/vision.md does not exist (run /kiln:kiln-roadmap --vision first)"
  exit 3
fi

mkdir -p "$LOCK_DIR"

# Lock acquisition — flock-when-available; macOS default has no flock.
acquire_lock() {
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    if ! flock -w 5 9; then
      err "could not acquire .vision.lock within 5s"
      exit 3
    fi
  else
    # Best-effort: write a marker file. ±1 drift accepted (NFR-003).
    : > "$LOCK_FILE" 2>/dev/null || true
  fi
}
release_lock() {
  if command -v flock >/dev/null 2>&1; then
    exec 9>&-
  fi
  rm -f "$LOCK_FILE" 2>/dev/null || true
}
trap release_lock EXIT

acquire_lock

# Verify the target section exists. If not, exit 2 BEFORE writing.
if ! grep -Fxq -- "$SECTION" "$VISION_FILE"; then
  err "target section not found in vision.md: ${SECTION}"
  exit 2
fi

TMP="$(mktemp "${VISION_FILE}.tmp.XXXXXX")"
# Cleanup the temp on any non-zero exit so the on-disk vision.md is never
# touched and no stale temps accumulate.
cleanup_tmp() {
  rm -f "$TMP" 2>/dev/null || true
}
trap 'cleanup_tmp; release_lock' EXIT

# Compose the new body in $TMP. Use awk for in-stream section editing —
# deterministic and bash-3.2 compatible.
# - Bump `last_updated:` in the YAML frontmatter to $TODAY (idempotent if
#   already today).
# - Apply OP to the target section.
#   * append-bullet:    insert "- $TEXT" line at end of the section's body
#                       (right before the next `## ` header or EOF).
#   * append-paragraph: insert blank line + $TEXT + blank line at end of body.
#   * replace-body:     drop existing body lines and replace with $TEXT
#                       (preserved verbatim, no leading/trailing blank
#                       collapse beyond a single trailing newline).
awk -v section="$SECTION" -v op="$OP" -v text="$TEXT" -v today="$TODAY" '
  BEGIN {
    in_front = 0; front_seen = 0
    in_section = 0
    section_body = ""
    section_emitted = 0
  }
  # Frontmatter handling — first --- opens, second --- closes. Bump
  # last_updated: line. Lines outside frontmatter are passed through.
  /^---$/ {
    if (front_seen == 0) {
      front_seen = 1; in_front = 1; print; next
    } else if (in_front == 1) {
      in_front = 0; print; next
    }
  }
  in_front == 1 {
    if ($0 ~ /^last_updated:/) {
      print "last_updated: " today
    } else {
      print
    }
    next
  }

  # Body — track when we enter / leave the target section.
  {
    line = $0
    is_header = (line ~ /^## /)
    if (is_header) {
      # Leaving previous section?
      if (in_section == 1) {
        emit_section_body(op, section_body, text)
        section_emitted = 1
        in_section = 0
        section_body = ""
      }
      if (line == section) {
        in_section = 1
        print line
        next
      }
    }
    if (in_section == 1) {
      # Buffer the body until the next header (or EOF).
      section_body = section_body line "\n"
      next
    }
    print line
  }
  END {
    if (in_section == 1) {
      emit_section_body(op, section_body, text)
      section_emitted = 1
    }
    if (section_emitted == 0) {
      # awk can not exit non-zero through the trap; print sentinel and the
      # outer shell will catch it.
      print "__VISION_SECTION_NOT_FOUND__" > "/dev/stderr"
    }
  }

  function emit_section_body(op, body, txt,    n, lines, i, last_idx) {
    # Trim a trailing newline so we can append cleanly.
    sub(/\n$/, "", body)
    if (op == "append-bullet") {
      # Strip trailing blank lines off body, append the bullet, restore one
      # trailing blank line before the next section header.
      gsub(/\n+$/, "", body)
      print body
      print "- " txt
      print ""
    } else if (op == "append-paragraph") {
      gsub(/\n+$/, "", body)
      print body
      print ""
      print txt
      print ""
    } else if (op == "replace-body") {
      print ""
      print txt
      print ""
    } else {
      print body
    }
  }
' "$VISION_FILE" > "$TMP" 2> "${TMP}.stderr"

if grep -Fxq "__VISION_SECTION_NOT_FOUND__" "${TMP}.stderr" 2>/dev/null; then
  rm -f "${TMP}.stderr"
  err "target section not found in vision.md: ${SECTION}"
  exit 2
fi
rm -f "${TMP}.stderr"

# Final atomic move. mv is atomic on the same filesystem (POSIX rename(2)).
if ! mv "$TMP" "$VISION_FILE"; then
  err "atomic mv to .kiln/vision.md failed"
  exit 3
fi
# trap will run cleanup_tmp on the now-deleted $TMP, which is a no-op.

printf 'vision: wrote --%s at %s\n' "$KEY" "$TODAY"
exit 0
