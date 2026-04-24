#!/usr/bin/env bash
# scratch-snapshot.sh — Snapshot the final state of a scratch dir as
#                      `<sha256>  <relative-path>` lines, sorted by path.
#
# Satisfies: FR-012 (post-session diagnostic snapshot)
# Contract:  contracts/interfaces.md §7.4
#
# Usage:
#   scratch-snapshot.sh <scratch-dir> <output-path>
#
# Output format matches `sha256sum` so the file is diff-friendly.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "scratch-snapshot.sh: expected 2 args (scratch-dir output-path), got $#" >&2
  exit 2
fi

scratch_dir=$1
output_path=$2

if [[ ! -d $scratch_dir ]]; then
  echo "scratch-snapshot.sh: scratch-dir does not exist: $scratch_dir" >&2
  exit 1
fi

# Detect sha256 helper (macOS uses `shasum -a 256`; Linux uses `sha256sum`).
if command -v sha256sum >/dev/null 2>&1; then
  sha256_cmd='sha256sum'
elif command -v shasum >/dev/null 2>&1; then
  sha256_cmd='shasum -a 256'
else
  echo "scratch-snapshot.sh: neither sha256sum nor shasum on PATH" >&2
  exit 2
fi

# find + hash + sort by path (for deterministic output per NFR-003).
# Use null-separated find to handle spaces in paths correctly.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

(
  cd "$scratch_dir"
  # find -type f, relative paths (starting with ./), sorted by null-safe sort.
  find . -type f -print0 | sort -z | while IFS= read -r -d '' f; do
    # Normalize leading `./` → ``.
    rel=${f#./}
    hash=$(eval "$sha256_cmd" "'$f'" | awk '{ print $1 }')
    printf '%s  %s\n' "$hash" "$rel"
  done
) > "$tmp"

mv "$tmp" "$output_path"
exit 0
