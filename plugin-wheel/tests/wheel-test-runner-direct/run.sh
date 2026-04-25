#!/usr/bin/env bash
# wheel-test-runner-direct/run.sh — proves wheel-test-runner.sh is consumable
# WITHOUT /kiln:kiln-test or any plugin-kiln/scripts/ in the call chain.
#
# Satisfies: FR-R3-1, FR-R3-2, NFR-R-1, NFR-R-2, SC-R-4
# Contract:  specs/wheel-test-runner-extraction/contracts/interfaces.md §6
# Pattern:   tier-2 run.sh-only fixture (run via `bash run.sh`).
#
# === Mutation tripwire (NFR-R-2) =============================================
# This fixture asserts on the exact shape of wheel-test-runner.sh's output.
# A deliberate mutation that silently changes the runner — e.g.,
#   - editing `plugin-wheel/scripts/harness/wheel-test-runner.sh` to print
#     `TAP version 14 ` (trailing space) on the header line, OR
#   - changing the exit-code convention (e.g., bail-out exiting 1 instead of 2),
#     OR
#   - dropping the `Bail out!` literal prefix in bail_out(),
# would be caught here:
#   - Assertion 1 (Form A) checks for the literal `1..0` line with no trailing
#     whitespace; a trailing space on the TAP header propagates to plan lines.
#   - Assertion 5 (`Bail out!` on bad input) requires both the literal prefix
#     AND exit code 2 — both regress on the mutations above.
# Manual reproduction: edit wheel-test-runner.sh's `printf 'TAP version 14\n'`
# to `printf 'TAP version 14 \n'` and re-run this fixture; it MUST FAIL.
# =============================================================================
#
# Non-kiln-coupling invariant (FR-R3-2): `git grep -nF 'plugin-kiln/scripts/'`
# against this run.sh MUST return zero matches. We're allowed to reference
# `plugin-kiln/tests/...` ONLY as test INPUT (not as a runtime dependency)
# but in this fixture we use synthetic plugin-foo/plugin-bar dirs in /tmp,
# avoiding even that.

set -uo pipefail

repo_root=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/../../.." &> /dev/null && pwd )
runner="$repo_root/plugin-wheel/scripts/harness/wheel-test-runner.sh"

passed=0
failed=0
total=0

note() { printf '  · %s\n' "$*"; }
ok()   { printf '  [OK] %s\n' "$*"; passed=$((passed+1)); total=$((total+1)); }
fail() { printf '  [FAIL] %s\n' "$*"; failed=$((failed+1)); total=$((total+1)); }

if ! command -v claude >/dev/null 2>&1; then
  echo "wheel-test-runner-direct: claude CLI not on PATH; the runner requires it."
  echo "PASS: wheel-test-runner-direct (0/0 assertions passed; skipped — claude unavailable)"
  exit 0
fi

# Set up two SEPARATE synthetic scratch trees in tmp:
#   $tmpdir/single/plugin-foo/  — single-plugin tree, used for Form A auto-detect
#   $tmpdir/alt/plugin-bar/     — separate tree for KILN_TEST_REPO_ROOT test
# Keeping them in different parent dirs prevents Form A's auto-detect from
# tripping the multi-plugin ambiguity branch.
tmpdir=$(mktemp -d -t wheel-test-runner-direct.XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/single/plugin-foo/skills" "$tmpdir/alt/plugin-bar/skills"
echo "# foo" > "$tmpdir/single/plugin-foo/skills/.gitkeep"
echo "# bar" > "$tmpdir/alt/plugin-bar/skills/.gitkeep"

echo "wheel-test-runner-direct: 5 structural assertions against $runner"
echo "  scratch root: $tmpdir"
echo

# -----------------------------------------------------------------------------
# Assertion 1 — Form A (auto-detect plugin), 0-test plugin → `1..0`, exit 0.
# Exercises: arg parsing (0 args), check_claude_on_path, auto_detect_plugin,
#            config-load, discovery, TAP header emission, exit-code aggregation.
# -----------------------------------------------------------------------------
echo "[1/5] Form A — auto-detect plugin (single sibling, no tests)"
out=$(cd "$tmpdir/single" && bash "$runner" 2>&1); rc=$?
# Auto-detect should find plugin-foo, run 0 tests → `1..0`, exit 0.
if [[ $rc -eq 0 ]] && grep -qx 'TAP version 14' <<<"$out" && grep -qx '1\.\.0' <<<"$out"; then
  ok "Form A: exit=0, 'TAP version 14' header, '1..0' plan line"
else
  fail "Form A: rc=$rc; output=$(printf '%s' "$out" | head -3 | tr '\n' '|')"
fi

# -----------------------------------------------------------------------------
# Assertion 2 — Form B (`<plugin>`), explicit name, 0-test plugin → `1..0`, exit 0.
# Exercises: arg parsing (1 arg), explicit plugin-resolution, discovery.
# -----------------------------------------------------------------------------
echo "[2/5] Form B — explicit <plugin> arg"
out=$(cd "$tmpdir/single" && bash "$runner" foo 2>&1); rc=$?
if [[ $rc -eq 0 ]] && grep -qx 'TAP version 14' <<<"$out" && grep -qx '1\.\.0' <<<"$out"; then
  ok "Form B: exit=0, TAP header + '1..0' plan line"
else
  fail "Form B: rc=$rc; output=$(printf '%s' "$out" | head -3 | tr '\n' '|')"
fi

# -----------------------------------------------------------------------------
# Assertion 3 — Form C (`<plugin> <test>`), nonexistent test → Bail out! exit 2.
# Exercises: arg parsing (2 args), filtered-discovery, bail-out on missing test.
# -----------------------------------------------------------------------------
echo "[3/5] Form C — <plugin> <nonexistent-test> bails out"
out=$(cd "$tmpdir/single" && bash "$runner" foo nonexistent-test 2>&1); rc=$?
if [[ $rc -eq 2 ]] && grep -qE "^Bail out! test 'nonexistent-test' not found" <<<"$out"; then
  ok "Form C: exit=2, 'Bail out!' for missing test"
else
  fail "Form C: rc=$rc; output=$(printf '%s' "$out" | head -3 | tr '\n' '|')"
fi

# -----------------------------------------------------------------------------
# Assertion 4 — KILN_TEST_REPO_ROOT honored.
# Exercises: env-var override of repo_root for plugin-discovery (FR-R1-6).
# Run from /tmp (no plugin-* siblings) but set env var to $tmpdir → plugin found.
# -----------------------------------------------------------------------------
echo "[4/5] KILN_TEST_REPO_ROOT honored"
out=$(cd / && KILN_TEST_REPO_ROOT="$tmpdir/alt" bash "$runner" bar 2>&1); rc=$?
if [[ $rc -eq 0 ]] && grep -qx 'TAP version 14' <<<"$out" && grep -qx '1\.\.0' <<<"$out"; then
  ok "KILN_TEST_REPO_ROOT: env var redirected discovery"
else
  fail "KILN_TEST_REPO_ROOT: rc=$rc; output=$(printf '%s' "$out" | head -3 | tr '\n' '|')"
fi

# -----------------------------------------------------------------------------
# Assertion 5 — Bail out! on bad input (nonexistent plugin).
# Exercises: explicit plugin-resolution failure path.
# Per contracts §6 + EC-4: bail-out shape is `Bail out! ...` + exit 2.
# -----------------------------------------------------------------------------
echo "[5/5] Bail out! on bad input (nonexistent plugin)"
out=$(cd "$tmpdir/single" && bash "$runner" nonexistent-plugin 2>&1); rc=$?
if [[ $rc -eq 2 ]] && grep -qE "^Bail out! plugin dir does not exist" <<<"$out"; then
  ok "Bail out! on bad plugin: exit=2, literal 'Bail out!' prefix preserved"
else
  fail "Bail out! on bad plugin: rc=$rc; output=$(printf '%s' "$out" | head -3 | tr '\n' '|')"
fi

echo
if [[ $failed -eq 0 ]]; then
  echo "PASS: wheel-test-runner-direct ($passed/$total assertions passed)"
  exit 0
else
  echo "FAIL: wheel-test-runner-direct ($failed/$total assertions failed)"
  exit 1
fi
