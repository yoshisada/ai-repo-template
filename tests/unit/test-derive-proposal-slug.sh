#!/usr/bin/env bash
# tests/unit/test-derive-proposal-slug.sh
# Unit tests for plugin-shelf/scripts/derive-proposal-slug.sh (FR-010).
# Validates deterministic slug derivation per Acceptance Scenario US2#3.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/plugin-shelf/scripts/derive-proposal-slug.sh"

pass=0
fail=0

assert_slug() {
  local name="$1" input="$2" expected="$3"
  local got
  got=$(printf '%s' "$input" | bash "$SCRIPT" 2>/dev/null || true)
  if [ "$got" = "$expected" ]; then
    printf 'PASS %s\n' "$name"
    pass=$((pass+1))
  else
    printf 'FAIL %s — input=%s expected=%s got=%s\n' "$name" "$input" "$expected" "$got"
    fail=$((fail+1))
  fi
}

assert_exit_code() {
  local name="$1" input="$2" expected_code="$3"
  printf '%s' "$input" | bash "$SCRIPT" >/dev/null 2>&1
  local got=$?
  if [ "$got" = "$expected_code" ]; then
    printf 'PASS %s\n' "$name"
    pass=$((pass+1))
  else
    printf 'FAIL %s — input=%s expected_code=%s got=%s\n' "$name" "$input" "$expected_code" "$got"
    fail=$((fail+1))
  fi
}

# Acceptance Scenario US2#3 — exact example from the spec.
assert_slug "spec-example-us2-3" \
  "Add a \`status_label\` field to the project dashboard type so shelf status skills stop hard-coding labels" \
  "add-status-label-field-project-dashboard-type-so"

# FR-010 determinism: same input twice -> same slug
first=$(printf 'Evidence in .wheel/outputs/foo.json shows a schema gap' | bash "$SCRIPT" 2>/dev/null)
second=$(printf 'Evidence in .wheel/outputs/foo.json shows a schema gap' | bash "$SCRIPT" 2>/dev/null)
if [ -n "$first" ] && [ "$first" = "$second" ]; then
  printf 'PASS determinism\n'; pass=$((pass+1))
else
  printf 'FAIL determinism — first=%s second=%s\n' "$first" "$second"; fail=$((fail+1))
fi

# FR-010: plain sentence, lowercase, stop-words stripped
assert_slug "plain-sentence" \
  "The quick brown fox jumps over the lazy dog" \
  "quick-brown-fox-jumps-over-lazy-dog"

# FR-010: stop-words-only input -> empty after stripping -> exit 1
assert_exit_code "stopwords-only-exit-1" \
  "the a an is of in on at to" \
  "1"

# FR-010: truncation never mid-word — output must end on a word boundary and
# length must be ≤50.
long_in="Consider the possibility that the manifest schema should include additional metadata fields for granular tracking and observability in long-running workflows"
long_out=$(printf '%s' "$long_in" | bash "$SCRIPT" 2>/dev/null)
if [ "${#long_out}" -le 50 ] && [ -n "$long_out" ] && [ "${long_out: -1}" != '-' ]; then
  printf 'PASS truncation-word-boundary (len=%d, out=%s)\n' "${#long_out}" "$long_out"
  pass=$((pass+1))
else
  printf 'FAIL truncation-word-boundary — len=%d out=%s\n' "${#long_out}" "$long_out"
  fail=$((fail+1))
fi

# FR-010 edge: empty stdin -> exit 1
assert_exit_code "empty-stdin-exit-1" "" "1"

# FR-010: punctuation-heavy input -> all non-alnum collapsed to single hyphens
assert_slug "punctuation-collapse" \
  "Fix: foo.bar!! (see @.wheel/outputs/evidence.json)" \
  "fix-foo-bar-see-wheel-outputs-evidence-json"

# FR-010: multi-line input handled
multi_out=$(printf 'Line one evidence\nLine two citation /path/to/.wheel/x.json' | bash "$SCRIPT" 2>/dev/null)
if [ -n "$multi_out" ] && printf '%s' "$multi_out" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
  printf 'PASS multi-line (out=%s)\n' "$multi_out"; pass=$((pass+1))
else
  printf 'FAIL multi-line — out=%s\n' "$multi_out"; fail=$((fail+1))
fi

# FR-010: unicode input — non-alphanumeric in the C locale collapses to `-`
unicode_out=$(printf 'Proposál façade at /path/.wheel/x.md' | bash "$SCRIPT" 2>/dev/null)
if [ -n "$unicode_out" ] && ! printf '%s' "$unicode_out" | grep -q '^-\|-$\|--'; then
  printf 'PASS unicode (out=%s)\n' "$unicode_out"; pass=$((pass+1))
else
  printf 'FAIL unicode — out=%s\n' "$unicode_out"; fail=$((fail+1))
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
