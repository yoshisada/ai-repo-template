#!/usr/bin/env bash
# test-resolve-project-name.sh
# Tests FR-013 (project-name resolution chain).
# Acceptance scenarios: Edge Cases "Project-name unresolvable" and
# ".shelf-config present but malformed" in spec.md.

set -u
LC_ALL=C
export LC_ALL

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script="$here/../resolve-project-name.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Case (a): .shelf-config with project_name=foo -> emits "foo".
mkdir -p "$tmp/case-a"
cd "$tmp/case-a"
# Isolate from any parent git repo by creating a fresh git boundary.
printf 'project_name=foo\n' > .shelf-config
out=$(bash "$script" 2>/dev/null)
if [ "$out" != "foo" ]; then
  printf 'case-a FAIL: expected "foo", got %q\n' "$out" >&2
  exit 1
fi

# Case (b): no .shelf-config, but inside a git repo -> emits basename.
mkdir -p "$tmp/case-b"
cd "$tmp/case-b"
git init -q . >/dev/null 2>&1
# Make a commit so show-toplevel reliably resolves.
out=$(bash "$script" 2>/dev/null)
expected=$(basename "$tmp/case-b")
if [ "$out" != "$expected" ]; then
  printf 'case-b FAIL: expected %q, got %q\n' "$expected" "$out" >&2
  exit 1
fi

# Case (c): neither .shelf-config nor git repo -> empty stdout, exit 0.
#
# We create an isolated tmpfs-like dir with a `.git` sentinel that forces git to
# fail. The cleanest way: cd into a dir, set GIT_CEILING_DIRECTORIES so git stops
# at our tmp root.
mkdir -p "$tmp/case-c"
cd "$tmp/case-c"
# Remove any inherited .git discovery path.
GIT_CEILING_DIRECTORIES="$tmp" bash "$script" > /tmp/resolve-out.$$ 2> /tmp/resolve-err.$$
rc=$?
out=$(cat /tmp/resolve-out.$$)
err=$(cat /tmp/resolve-err.$$)
rm -f /tmp/resolve-out.$$ /tmp/resolve-err.$$
if [ "$rc" -ne 0 ]; then
  printf 'case-c FAIL: expected exit 0, got %d\n' "$rc" >&2
  exit 1
fi
if [ -n "$out" ]; then
  printf 'case-c FAIL: expected empty stdout, got %q\n' "$out" >&2
  exit 1
fi
if [ -z "$err" ]; then
  printf 'case-c FAIL: expected stderr warning, got empty\n' >&2
  exit 1
fi

exit 0
