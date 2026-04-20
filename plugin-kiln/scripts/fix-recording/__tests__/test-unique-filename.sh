#!/usr/bin/env bash
# test-unique-filename.sh
# Tests FR-015 (same-day collision disambiguation).
# Acceptance scenario: Edge Cases "Same-day same-slug collision" in spec.md.

set -u
LC_ALL=C
export LC_ALL

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script="$here/../unique-filename.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Case (a): empty dir -> base filename.
out=$(bash "$script" "$tmp" "2026-04-20" "auth-bug")
if [ "$out" != "2026-04-20-auth-bug.md" ]; then
  printf 'case-a FAIL: expected base, got %q\n' "$out" >&2
  exit 1
fi

# Case (b): one existing file -> "-2" suffix.
touch "$tmp/2026-04-20-auth-bug.md"
out=$(bash "$script" "$tmp" "2026-04-20" "auth-bug")
if [ "$out" != "2026-04-20-auth-bug-2.md" ]; then
  printf 'case-b FAIL: expected -2, got %q\n' "$out" >&2
  exit 1
fi

# Case (c): existing -2 and -3 -> "-4" suffix.
touch "$tmp/2026-04-20-auth-bug-2.md" "$tmp/2026-04-20-auth-bug-3.md"
out=$(bash "$script" "$tmp" "2026-04-20" "auth-bug")
if [ "$out" != "2026-04-20-auth-bug-4.md" ]; then
  printf 'case-c FAIL: expected -4, got %q\n' "$out" >&2
  exit 1
fi

exit 0
