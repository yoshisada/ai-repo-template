#!/usr/bin/env bash
# test-strip-credentials.sh
# Tests FR-026 (credentials stripped before envelope composition).
# Acceptance scenario: Edge case "Envelope contains credential-looking string"
# (spec.md Edge Cases): .kiln/qa/.env.test lines must be removed from envelope fields.

set -u
LC_ALL=C
export LC_ALL

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script="$here/../strip-credentials.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cd "$tmp"

# Case (a): no .kiln/qa/.env.test — passthrough.
out=$(printf 'line1\nsecret=abc\nline3\n' | bash "$script")
expected=$(printf 'line1\nsecret=abc\nline3')
if [ "$out" != "$expected" ]; then
  printf 'case-a FAIL: expected passthrough\ngot: %s\n' "$out" >&2
  exit 1
fi

# Case (b): credential line present — stripped.
mkdir -p .kiln/qa
printf 'QA_TEST_USER_PASSWORD=hunter2\n' > .kiln/qa/.env.test
input=$(printf 'before\nQA_TEST_USER_PASSWORD=hunter2\nafter\n')
out=$(printf '%s\n' "$input" | bash "$script")
if printf '%s' "$out" | grep -Fq 'QA_TEST_USER_PASSWORD=hunter2'; then
  printf 'case-b FAIL: credential line leaked\ngot: %s\n' "$out" >&2
  exit 1
fi
if ! printf '%s' "$out" | grep -Fq 'before'; then
  printf 'case-b FAIL: unrelated line was stripped\ngot: %s\n' "$out" >&2
  exit 1
fi

# Case (c): env file has only comments/blank lines — NOT treated as filters.
cat > .kiln/qa/.env.test <<'ENV'
# Debug Credentials — DO NOT COMMIT
#

ENV
out=$(printf '# Debug Credentials — DO NOT COMMIT\nplain text\n' | bash "$script")
if ! printf '%s' "$out" | grep -Fq '# Debug Credentials'; then
  printf 'case-c FAIL: comment line was filtered when it should not have been\n' >&2
  exit 1
fi
if ! printf '%s' "$out" | grep -Fq 'plain text'; then
  printf 'case-c FAIL: plain text was lost\n' >&2
  exit 1
fi

exit 0
