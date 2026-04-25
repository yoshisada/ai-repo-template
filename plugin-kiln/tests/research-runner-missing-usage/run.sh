#!/usr/bin/env bash
# research-runner-missing-usage/run.sh — SC-S-007 anchor.
#
# Validates: parse-token-usage.sh exits 2 + emits the documented diagnostic
#            on (a) transcript with no result envelope, (b) result envelope
#            with no `usage` record, AND parses a valid transcript correctly.
#
# Acceptance scenario: spec.md §SC-S-007 — synthetic transcript with stripped
# `usage` envelope MUST cause the parser to exit 2 + emit the documented
# `parse error: usage record missing` diagnostic.
#
# Self-contained — no `claude` CLI dependency. Operates on static fixtures.
set -euo pipefail

here=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )
repo_root=$( cd -- "$here/../../.." && pwd )
parser="$repo_root/plugin-wheel/scripts/harness/parse-token-usage.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

assertions=0
fail() { echo "FAIL: $*"; rm -rf "$tmp"; exit 1; }

# --- Case 1: stripped result envelope (no usage field) -----------------------
# Anchored to: spec acceptance scenario for SC-S-007 (NFR-S-008 loud-failure).
set +e
out=$(bash "$parser" "$here/fixtures/transcript-stripped.ndjson" 2>"$tmp/err1")
rc=$?
set -e
[[ $rc -eq 2 ]] || fail "stripped: expected exit 2, got $rc (stdout: $out)"
grep -qF "parse error: usage record missing" "$tmp/err1" || \
  fail "stripped: missing documented diagnostic (got: $(cat "$tmp/err1"))"
assertions=$((assertions + 1))

# --- Case 2: transcript without ANY result envelope --------------------------
# Anchored to: spec acceptance scenario for SC-S-007 (NFR-S-008 loud-failure).
set +e
out=$(bash "$parser" "$here/fixtures/transcript-empty.ndjson" 2>"$tmp/err2")
rc=$?
set -e
[[ $rc -eq 2 ]] || fail "empty: expected exit 2, got $rc"
grep -qF "parse error: usage record missing" "$tmp/err2" || \
  fail "empty: missing documented diagnostic (got: $(cat "$tmp/err2"))"
assertions=$((assertions + 1))

# --- Case 3: transcript that does not exist ----------------------------------
# Anchored to: spec acceptance scenario for SC-S-007 (NFR-S-008 loud-failure).
set +e
out=$(bash "$parser" "$here/fixtures/no-such-file.ndjson" 2>"$tmp/err3")
rc=$?
set -e
[[ $rc -eq 2 ]] || fail "missing: expected exit 2, got $rc"
assertions=$((assertions + 1))

# --- Case 4: valid transcript parses correctly -------------------------------
# Anchored to: spec FR-S-013 (token-parsing helper).
out=$(bash "$parser" "$here/fixtures/transcript-valid.ndjson")
expected="10 20 0 0 30"
[[ $out == "$expected" ]] || fail "valid: expected '$expected', got '$out'"
assertions=$((assertions + 1))

# --- Case 5: missing arg ----------------------------------------------------
# Anchored to: spec FR-S-013 contract requirement (1 arg required).
set +e
bash "$parser" 2>"$tmp/err5"
rc=$?
set -e
[[ $rc -eq 2 ]] || fail "no-arg: expected exit 2, got $rc"
assertions=$((assertions + 1))

echo "PASS ($assertions assertions)"
