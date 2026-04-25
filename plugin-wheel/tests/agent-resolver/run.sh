#!/usr/bin/env bash
# T040 — Unit tests for plugin-wheel/scripts/agents/resolve.sh (FR-A1, FR-A3).
#
# Covers all five cases enumerated in contracts/interfaces.md §1 "Tests":
#   (a) absolute-path input   -> JSON with source=path
#   (b) repo-relative input   -> JSON with source=path
#   (c) short-name input      -> JSON with source=short-name (registry lookup)
#   (d) unknown-passthrough   -> JSON with source=unknown (I-R1 back-compat)
#   (e) WORKFLOW_PLUGIN_DIR unset + non-absolute input -> exit 1 loud (CC-3)
#
# Plus:
#   (f) empty input           -> exit 1 loud
#   (g) idempotency           -> two calls return byte-identical output (I-R2)
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
out=$("$RESOLVE" "${REPO_ROOT}/plugin-wheel/agents/debugger.md")
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
  rel_out=$("$RESOLVE" plugin-wheel/agents/qa-engineer.md)
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

# --- (c) short-name input ---
out=$("$RESOLVE" debugger)
source_val=$(jq -r '.source' <<<"$out")
subagent_val=$(jq -r '.subagent_type' <<<"$out")
canonical_val=$(jq -r '.canonical_path' <<<"$out")
model_val=$(jq -r '.model_default' <<<"$out")
if [[ "$source_val" == "short-name" && "$subagent_val" == "debugger" \
      && "$canonical_val" == "plugin-wheel/agents/debugger.md" \
      && "$model_val" == "sonnet" ]]; then
  assert_pass "(c) short name 'debugger' → full registry spec"
else
  assert_fail "(c) short name: source=$source_val subagent=$subagent_val canonical=$canonical_val model=$model_val"
fi

# (c) also check a haiku-defaulting agent to prove model_default flows through
out=$("$RESOLVE" spec-enforcer)
model_val=$(jq -r '.model_default' <<<"$out")
if [[ "$model_val" == "haiku" ]]; then
  assert_pass "(c) short name 'spec-enforcer' → model_default=haiku"
else
  assert_fail "(c) spec-enforcer model_default: got $model_val"
fi

# --- (d) unknown name — passthrough (I-R1) ---
out=$("$RESOLVE" not-a-real-agent-name)
source_val=$(jq -r '.source' <<<"$out")
subagent_val=$(jq -r '.subagent_type' <<<"$out")
model_val=$(jq -r '.model_default' <<<"$out")
if [[ "$source_val" == "unknown" && "$subagent_val" == "not-a-real-agent-name" && "$model_val" == "null" ]]; then
  assert_pass "(d) unknown name → source=unknown, subagent echoed, model_default=null"
else
  assert_fail "(d) unknown: source=$source_val subagent=$subagent_val model=$model_val"
fi

# Another canonical unknown: 'general-purpose' (the legacy default spawn) must pass through.
out=$("$RESOLVE" general-purpose)
source_val=$(jq -r '.source' <<<"$out")
subagent_val=$(jq -r '.subagent_type' <<<"$out")
if [[ "$source_val" == "unknown" && "$subagent_val" == "general-purpose" ]]; then
  assert_pass "(d) 'general-purpose' back-compat → passthrough preserved"
else
  assert_fail "(d) general-purpose: source=$source_val subagent=$subagent_val"
fi

# --- (e) WORKFLOW_PLUGIN_DIR unset + non-absolute unresolvable input → exit 1 loud ---
tmp_cwd="$(mktemp -d -t wheel-resolver-e.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '$tmp_cwd'" EXIT
(
  cd "$tmp_cwd"
  # Unset WORKFLOW_PLUGIN_DIR via `env -u`; relative path doesn't exist from this CWD.
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

# --- (g) idempotency (I-R2) ---
a=$("$RESOLVE" debugger)
b=$("$RESOLVE" debugger)
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
