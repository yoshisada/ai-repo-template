#!/usr/bin/env bash
# T040 — Unit tests for plugin-wheel/scripts/agents/resolve.sh (FR-A3, simplified 2026-04-25).
#
# Covers the simplified resolver shape (post-registry-deletion):
#   (a) absolute-path input          -> JSON with source=path
#   (b) repo-relative input          -> JSON with source=path
#   (c) plugin-prefixed name         -> JSON with source=passthrough (e.g. kiln:debugger)
#   (d) bare name (legacy)           -> JSON with source=unknown (back-compat)
#   (e) WORKFLOW_PLUGIN_DIR unset + non-absolute input -> exit 1 loud
#   (f) empty input                  -> exit 1 loud
#   (g) idempotency                  -> two calls return byte-identical output
#
# Exit 0 if all pass, 1 on any failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RESOLVE="${REPO_ROOT}/plugin-wheel/scripts/agents/resolve.sh"

if [[ ! -x "$RESOLVE" ]]; then
  echo "FAIL: resolver not executable at $RESOLVE" >&2
  exit 1
fi

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# --- (a) absolute path ---
out=$("$RESOLVE" "${REPO_ROOT}/plugin-kiln/agents/debugger.md")
source_val=$(jq -r '.source' <<<"$out")
subagent_val=$(jq -r '.subagent_type' <<<"$out")
if [[ "$source_val" == "path" && "$subagent_val" == "debugger" ]]; then
  assert_pass "(a) absolute path → source=path, subagent_type=debugger"
else
  assert_fail "(a) absolute path: got source=$source_val subagent_type=$subagent_val"
fi

# --- (b) repo-relative path ---
(
  cd "$REPO_ROOT"
  rel_out=$("$RESOLVE" plugin-kiln/agents/qa-engineer.md)
  rel_source=$(jq -r '.source' <<<"$rel_out")
  rel_subagent=$(jq -r '.subagent_type' <<<"$rel_out")
  if [[ "$rel_source" == "path" && "$rel_subagent" == "qa-engineer" ]]; then
    echo "PASS: (b) repo-relative path → source=path, subagent_type=qa-engineer"
  else
    echo "FAIL: (b) repo-relative: source=$rel_source subagent=$rel_subagent" >&2
    exit 1
  fi
)
if [[ $? -eq 0 ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); fi

# --- (c) plugin-prefixed name (the canonical form post-2026-04-25 cleanup) ---
out=$("$RESOLVE" kiln:debugger)
source_val=$(jq -r '.source' <<<"$out")
subagent_val=$(jq -r '.subagent_type' <<<"$out")
canonical_val=$(jq -r '.canonical_path' <<<"$out")
if [[ "$source_val" == "passthrough" && "$subagent_val" == "kiln:debugger" && "$canonical_val" == "kiln:debugger" ]]; then
  assert_pass "(c) plugin-prefixed name 'kiln:debugger' → source=passthrough, subagent echoed"
else
  assert_fail "(c) plugin-prefixed: source=$source_val subagent=$subagent_val canonical=$canonical_val"
fi

# Another plugin-prefixed example
out=$("$RESOLVE" shelf:reconciler)
source_val=$(jq -r '.source' <<<"$out")
subagent_val=$(jq -r '.subagent_type' <<<"$out")
if [[ "$source_val" == "passthrough" && "$subagent_val" == "shelf:reconciler" ]]; then
  assert_pass "(c) plugin-prefixed 'shelf:reconciler' → passthrough (no central registry needed)"
else
  assert_fail "(c) shelf:reconciler: source=$source_val subagent=$subagent_val"
fi

# --- (d) bare name → unknown passthrough (legacy back-compat) ---
out=$("$RESOLVE" not-a-real-agent-name)
source_val=$(jq -r '.source' <<<"$out")
subagent_val=$(jq -r '.subagent_type' <<<"$out")
model_val=$(jq -r '.model_default' <<<"$out")
if [[ "$source_val" == "unknown" && "$subagent_val" == "not-a-real-agent-name" && "$model_val" == "null" ]]; then
  assert_pass "(d) bare name → source=unknown, subagent echoed, model_default=null"
else
  assert_fail "(d) bare name: source=$source_val subagent=$subagent_val model=$model_val"
fi

# 'general-purpose' (legacy default spawn) still passes through.
out=$("$RESOLVE" general-purpose)
source_val=$(jq -r '.source' <<<"$out")
subagent_val=$(jq -r '.subagent_type' <<<"$out")
if [[ "$source_val" == "unknown" && "$subagent_val" == "general-purpose" ]]; then
  assert_pass "(d) 'general-purpose' back-compat → passthrough preserved"
else
  assert_fail "(d) general-purpose: source=$source_val subagent=$subagent_val"
fi

# Bare name that happens to match a real agent → still bare (not pre-registered).
# Caller should pass kiln:debugger instead.
out=$("$RESOLVE" debugger)
source_val=$(jq -r '.source' <<<"$out")
if [[ "$source_val" == "unknown" ]]; then
  assert_pass "(d) bare 'debugger' → source=unknown (use kiln:debugger for known-good shape)"
else
  assert_fail "(d) bare 'debugger' should be unknown: source=$source_val"
fi

# --- (e) WORKFLOW_PLUGIN_DIR unset + non-absolute unresolvable input → exit 1 loud ---
tmp_cwd="$(mktemp -d -t wheel-resolver-e.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '$tmp_cwd'" EXIT
(
  cd "$tmp_cwd"
  if env -u WORKFLOW_PLUGIN_DIR "$RESOLVE" some-rel/ghost.md 2>"${tmp_cwd}/err" 1>/dev/null; then
    echo "FAIL: (e) expected exit 1 but got 0" >&2
    exit 1
  fi
  err=$(cat "${tmp_cwd}/err")
  if [[ "$err" == *"WORKFLOW_PLUGIN_DIR unset"* ]]; then
    echo "PASS: (e) WORKFLOW_PLUGIN_DIR unset + unresolvable → exit 1 with identifiable stderr"
  else
    echo "FAIL: (e) stderr missing identifiable string: $err" >&2
    exit 1
  fi
)
if [[ $? -eq 0 ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); fi

# --- (f) empty input → exit 1 loud ---
if "$RESOLVE" "" 2>/dev/null; then
  assert_fail "(f) empty input should have exited 1"
else
  err=$("$RESOLVE" "" 2>&1 >/dev/null || true)
  if [[ "$err" == *"empty input"* ]]; then
    assert_pass "(f) empty input → exit 1 with identifiable stderr"
  else
    assert_fail "(f) empty input: stderr missing identifiable string: $err"
  fi
fi

# --- (g) idempotency ---
a=$("$RESOLVE" kiln:debugger)
b=$("$RESOLVE" kiln:debugger)
if [[ "$a" == "$b" ]]; then
  assert_pass "(g) idempotent: two calls return byte-identical output"
else
  assert_fail "(g) idempotency violated"
fi

# --- Summary ---
echo
echo "--- Results: ${pass} passed, ${fail} failed ---"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
