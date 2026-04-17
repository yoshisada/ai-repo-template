#!/usr/bin/env bash
# check-manifest-target-exists.sh
# FR-005
#
# Verifies that the `@manifest/...` target resolves to a readable file AND that
# the `current` text (passed in a temp file) appears verbatim inside it.
#
# Invocation:
#   bash check-manifest-target-exists.sh <target_path> <current_file>
#
# Path resolution rules:
#   1. If $VAULT_ROOT is set and non-empty, resolve @<prefix>/ -> $VAULT_ROOT/<prefix>/.
#   2. Else if .shelf-config in repo root contains `vault_root=<path>`, use that.
#   3. Else exit 1.
#
# Exit:
#   0 — resolved file is readable AND `grep -F -f <current_file>` returns 0.
#   1 — any failure (unresolved path, missing file, no verbatim match).

set -u
LC_ALL=C
export LC_ALL

target="${1:-}"
current_file="${2:-}"

if [ -z "$target" ] || [ -z "$current_file" ]; then
  exit 1
fi
if [ ! -f "$current_file" ]; then
  exit 1
fi

# Resolve vault_root (FR-005 path-resolution rules).
vault_root=""
if [ -n "${VAULT_ROOT:-}" ]; then
  vault_root=$VAULT_ROOT
elif [ -f ".shelf-config" ]; then
  vault_root=$(grep -E '^vault_root[[:space:]]*=' .shelf-config | head -1 | sed 's/^vault_root[[:space:]]*=[[:space:]]*//; s/[[:space:]]*$//' || true)
fi

if [ -z "$vault_root" ]; then
  exit 1
fi

# Target begins with `@manifest/...`. Replace the leading `@` with
# `<vault_root>/` so @manifest/types/foo.md -> $vault_root/manifest/types/foo.md.
case "$target" in
  @*)
    resolved="${vault_root%/}/${target#@}"
    ;;
  *)
    exit 1
    ;;
esac

if [ ! -r "$resolved" ]; then
  exit 1
fi

# FR-005: verbatim match. `grep -F -f <needle_file>` treats each line of the
# needle file as a fixed string — so multi-line `current` strings are matched
# line-by-line (each line of `current` must appear somewhere in the target,
# which is a sufficient verbatim-contains check for practical manifest edits).
if grep -F -f "$current_file" -- "$resolved" >/dev/null 2>&1; then
  exit 0
fi
exit 1
