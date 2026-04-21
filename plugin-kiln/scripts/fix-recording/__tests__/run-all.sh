#!/usr/bin/env bash
# run-all.sh
# FR-024, FR-030
#
# Entrypoint for fix-recording unit tests. Discovers every `test-*.sh` in this
# directory, runs each under `bash -e`, prints a PASS/FAIL line per test, and
# exits non-zero if any test failed. Pure bash — no bats, no vitest (FR-024).

set -u
LC_ALL=C
export LC_ALL

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

shopt -s nullglob
tests=("$here"/test-*.sh)
shopt -u nullglob

if [ "${#tests[@]}" -eq 0 ]; then
  printf 'run-all: no tests found in %s\n' "$here" >&2
  exit 1
fi

pass=0
fail=0
for t in "${tests[@]}"; do
  name=$(basename "$t")
  if bash -e "$t" >/tmp/fix-recording-test-out.$$ 2>&1; then
    printf 'PASS %s\n' "$name"
    pass=$((pass + 1))
  else
    printf 'FAIL %s\n' "$name"
    sed 's/^/  | /' /tmp/fix-recording-test-out.$$ || true
    fail=$((fail + 1))
  fi
done
rm -f /tmp/fix-recording-test-out.$$

total=$((pass + fail))
printf '\n%d/%d tests passed\n' "$pass" "$total"

if [ "$fail" -ne 0 ]; then
  exit 1
fi
exit 0
