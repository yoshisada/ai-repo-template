#!/usr/bin/env bash
# scratch-create.sh — Create an isolated scratch dir for one test invocation.
#
# Satisfies: FR-003 (scratch dir `/tmp/kiln-test-<uuid>/`), NFR-004 (isolation)
# Contract:  contracts/interfaces.md §7.5 + §4 (scratch-dir invariants)
#
# Usage:
#   scratch-create.sh
#
# Args: none
#
# Stdout: absolute path of the created scratch dir (e.g., /tmp/kiln-test-<uuid>/)
# Stderr: diagnostics
# Exit:   0 on success, 2 on UUID collision after 3 retries or uuidgen failure
set -euo pipefail

# UUIDv4 regex per contracts §4.
UUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'

gen_uuid() {
  # FR-003: UUIDv4 via uuidgen (available on macOS + every Linux we care about).
  if ! command -v uuidgen >/dev/null 2>&1; then
    echo "scratch-create.sh: uuidgen not on PATH" >&2
    exit 2
  fi
  local u
  u=$(uuidgen | tr '[:upper:]' '[:lower:]')
  # FR-003 / contracts §4: validate UUIDv4 shape.
  if ! [[ $u =~ $UUID_RE ]]; then
    echo "scratch-create.sh: uuidgen produced non-UUIDv4: $u" >&2
    exit 2
  fi
  printf '%s' "$u"
}

# contracts §4 collision handling: retry up to 3 times, fail inconclusive on 4th.
for attempt in 1 2 3 4; do
  uuid=$(gen_uuid)
  path="/tmp/kiln-test-${uuid}"
  if [[ ! -e $path ]]; then
    mkdir -p "$path"
    chmod 700 "$path"  # scratch dir is user-private
    printf '%s\n' "$path"
    exit 0
  fi
  echo "scratch-create.sh: collision at $path (attempt $attempt), retrying..." >&2
done

echo "scratch-create.sh: 4 consecutive UUID collisions — aborting (exit 2)" >&2
exit 2
