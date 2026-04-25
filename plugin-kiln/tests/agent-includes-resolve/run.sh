#!/usr/bin/env bash
# SC-1 + SC-7 fixture for the include resolver.
# Validates: contracts/interfaces.md §1 invariants I-B1..I-B4 + acceptance scenarios 1–6.
# Substrate: tier-2 (run.sh-only). Invoke via `bash plugin-kiln/tests/agent-includes-resolve/run.sh`.
# Exit 0 on PASS, non-zero on FAIL. Last line is a PASS/FAIL summary line.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RESOLVER="$REPO_ROOT/plugin-kiln/scripts/agent-includes/resolve.sh"

if [[ ! -x "$RESOLVER" ]]; then
  echo "FAIL: resolver not executable at $RESOLVER"
  exit 2
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

assert_pass() {
  local name="$1"; shift
  if "$@"; then
    PASS=$((PASS + 1))
    printf '  pass  %s\n' "$name"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n' "$name"
  fi
}

# ---------- Case 1: I-B1 — zero directives → byte-identical (NFR-2) ----------
case_no_op() {
  local f="$TMP/no_directive.md"
  printf 'first line\nsecond line\n# heading\nbody\n' > "$f"
  diff <("$RESOLVER" "$f") "$f" >/dev/null
}
assert_pass "I-B1 zero-directive file is no-op (byte-identical)" case_no_op

# ---------- Case 2: directive on its own line → expansion ----------
case_basic_expansion() {
  local d="$TMP/case2"
  mkdir -p "$d/_shared"
  printf 'expanded body\n' > "$d/_shared/mod.md"
  printf 'before\n<!-- @include _shared/mod.md -->\nafter\n' > "$d/parent.md"
  local out
  out=$("$RESOLVER" "$d/parent.md")
  [[ "$out" == "before"$'\n'"expanded body"$'\n'"after" ]]
}
assert_pass "Acceptance 1: directive on own line expands correctly" case_basic_expansion

# ---------- Case 3: R-2 — directive-shaped text inside fenced code block is NOT expanded ----------
case_fenced_code_block() {
  local d="$TMP/case3"
  mkdir -p "$d/_shared"
  printf 'NEVER_USE\n' > "$d/_shared/mod.md"
  cat > "$d/parent.md" <<'EOF'
Document the syntax:

```
<!-- @include _shared/mod.md -->
```

Done.
EOF
  local out
  out=$("$RESOLVER" "$d/parent.md")
  # Ensure the directive remained literal (no expansion of mod.md inside the fence)
  echo "$out" | grep -q '<!-- @include _shared/mod.md -->' && \
    ! echo "$out" | grep -q 'NEVER_USE'
}
assert_pass "Acceptance 6 / R-2: directive inside fenced code block is preserved" case_fenced_code_block

# ---------- Case 4: missing target → exit 1 with diagnostic ----------
case_missing_target() {
  local d="$TMP/case4"
  mkdir -p "$d"
  printf 'A\n<!-- @include nope.md -->\nB\n' > "$d/parent.md"
  local err exit_code
  err=$("$RESOLVER" "$d/parent.md" 2>&1 >/dev/null)
  exit_code=$?
  [[ $exit_code -eq 1 ]] && \
    echo "$err" | grep -q 'include-target-not-found' && \
    echo "$err" | grep -q 'nope.md'
}
assert_pass "Edge: missing include target → exit 1 with diagnostic" case_missing_target

# ---------- Case 5: recursive include → exit 1 with diagnostic ----------
case_recursive_include() {
  local d="$TMP/case5"
  mkdir -p "$d/_shared"
  printf 'leaf\n' > "$d/_shared/leaf.md"
  printf '<!-- @include leaf.md -->\n' > "$d/_shared/has_directive.md"
  printf 'X\n<!-- @include _shared/has_directive.md -->\nY\n' > "$d/parent.md"
  local err exit_code
  err=$("$RESOLVER" "$d/parent.md" 2>&1 >/dev/null)
  exit_code=$?
  [[ $exit_code -eq 1 ]] && echo "$err" | grep -q 'recursive-include-detected'
}
assert_pass "Acceptance 5 / FR-B-4: recursive include → exit 1" case_recursive_include

# ---------- Case 6: I-B2 / SC-7 — re-invocation byte-identical ----------
case_determinism() {
  local d="$TMP/case6"
  mkdir -p "$d/_shared"
  printf 'shared\n' > "$d/_shared/mod.md"
  printf 'top\n<!-- @include _shared/mod.md -->\nbot\n' > "$d/parent.md"
  local a b
  a=$("$RESOLVER" "$d/parent.md")
  b=$("$RESOLVER" "$d/parent.md")
  [[ "$a" == "$b" ]]
}
assert_pass "I-B2 / SC-7: re-invocation byte-identical (deterministic)" case_determinism

# ---------- Case 7: empty include target → empty expansion (no error) ----------
case_empty_target() {
  local d="$TMP/case7"
  mkdir -p "$d/_shared"
  : > "$d/_shared/empty.md"
  printf 'pre\n<!-- @include _shared/empty.md -->\npost\n' > "$d/parent.md"
  local out
  out=$("$RESOLVER" "$d/parent.md")
  [[ "$out" == "pre"$'\n'"post" ]]
}
assert_pass "Edge: empty include target → empty expansion, no error" case_empty_target

# ---------- Case 8: stdin (`-`) input mode ----------
case_stdin_mode() {
  local d="$TMP/case8"
  mkdir -p "$d/_shared"
  printf 'stdin-shared\n' > "$d/_shared/mod.md"
  local out
  out=$(cd "$d" && printf 'top\n<!-- @include _shared/mod.md -->\nbot\n' | "$RESOLVER" -)
  [[ "$out" == "top"$'\n'"stdin-shared"$'\n'"bot" ]]
}
assert_pass "Stdin mode (-) resolves relative to PWD" case_stdin_mode

# ---------- Summary ----------
TOTAL=$((PASS + FAIL))
echo
if [[ $FAIL -eq 0 ]]; then
  echo "PASS: $PASS/$TOTAL assertions"
  exit 0
else
  echo "FAIL: $FAIL/$TOTAL assertions failed"
  exit 1
fi
