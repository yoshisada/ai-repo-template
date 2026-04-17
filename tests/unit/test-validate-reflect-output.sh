#!/usr/bin/env bash
# tests/unit/test-validate-reflect-output.sh
# Unit tests for plugin-shelf/scripts/validate-reflect-output.sh (FR-003..FR-006, FR-018).
# Each assertion validates one acceptance scenario from spec.md.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/plugin-shelf/scripts/validate-reflect-output.sh"
TMP=$(mktemp -d -t validate-reflect.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

assert_verdict() {
  local name="$1" input_json="$2" expected_verdict="$3" expected_reason="${4:-}"
  local file="$TMP/${name}.json"
  printf '%s\n' "$input_json" > "$file"
  local got
  got=$(bash "$SCRIPT" "$file" 2>/dev/null || true)
  local verdict reason
  verdict=$(printf '%s' "$got" | jq -r '.verdict // ""' 2>/dev/null || echo "")
  reason=$(printf '%s' "$got" | jq -r '.reason // ""' 2>/dev/null || echo "")
  if [ "$verdict" = "$expected_verdict" ]; then
    if [ -z "$expected_reason" ] || [ "$reason" = "$expected_reason" ]; then
      printf 'PASS %s\n' "$name"
      pass=$((pass+1))
      return
    fi
  fi
  printf 'FAIL %s — got verdict=%s reason=%s\n' "$name" "$verdict" "$reason"
  fail=$((fail+1))
}

# FR-018: missing file -> skip
missing_output=$(bash "$SCRIPT" "$TMP/does-not-exist.json" 2>/dev/null || true)
if printf '%s' "$missing_output" | jq -e '.verdict=="skip" and .reason=="malformed-or-missing"' >/dev/null 2>&1; then
  printf 'PASS missing-file\n'; pass=$((pass+1))
else
  printf 'FAIL missing-file — got %s\n' "$missing_output"; fail=$((fail+1))
fi

# FR-018: empty file -> skip (scenario: malformed JSON)
: > "$TMP/empty.json"
empty_output=$(bash "$SCRIPT" "$TMP/empty.json" 2>/dev/null || true)
if printf '%s' "$empty_output" | jq -e '.verdict=="skip" and .reason=="malformed-or-missing"' >/dev/null 2>&1; then
  printf 'PASS empty-file\n'; pass=$((pass+1))
else
  printf 'FAIL empty-file — got %s\n' "$empty_output"; fail=$((fail+1))
fi

# FR-018: unparseable -> skip (scenario: Edge Case "reflect output malformed JSON")
printf 'not-json-at-all\n' > "$TMP/bad.json"
bad_output=$(bash "$SCRIPT" "$TMP/bad.json" 2>/dev/null || true)
if printf '%s' "$bad_output" | jq -e '.verdict=="skip" and .reason=="malformed-or-missing"' >/dev/null 2>&1; then
  printf 'PASS malformed-json\n'; pass=$((pass+1))
else
  printf 'FAIL malformed-json — got %s\n' "$bad_output"; fail=$((fail+1))
fi

# FR-003 Acceptance Scenario US1#2: {"skip": true} -> skip/agent-skip
assert_verdict "explicit-skip" \
  '{"skip": true}' \
  "skip" "agent-skip"

# FR-003: missing fields -> skip/missing-field (edge case "Empty field")
assert_verdict "missing-field-target" \
  '{"skip": false, "section":"s", "current":"c", "proposed":"p", "why":"see .wheel/outputs/x.json"}' \
  "skip" "missing-field"

assert_verdict "empty-current" \
  '{"skip": false, "target":"@manifest/types/mistake.md", "section":"s", "current":"", "proposed":"p", "why":"see .wheel/outputs/x.json"}' \
  "skip" "missing-field"

# FR-004 Acceptance Scenario US3#1: out-of-scope path -> skip/out-of-scope
assert_verdict "out-of-scope-plugin" \
  '{"skip": false, "target":"plugin-shelf/skills/shelf-update/SKILL.md", "section":"s", "current":"c", "proposed":"p", "why":"see .wheel/outputs/x.json"}' \
  "skip" "out-of-scope"

# FR-004 edge: @manifest/systems/ is in-vault but wrong subdir -> out-of-scope
assert_verdict "out-of-scope-wrong-subdir" \
  '{"skip": false, "target":"@manifest/systems/projects.md", "section":"s", "current":"c", "proposed":"p", "why":"see .wheel/outputs/x.json"}' \
  "skip" "out-of-scope"

# FR-006 edge case "Generic why": why with no run-evidence token -> skip/why-not-grounded
assert_verdict "generic-why" \
  '{"skip": false, "target":"@manifest/types/mistake.md", "section":"s", "current":"c", "proposed":"p", "why":"looks bad to me"}' \
  "skip" "why-not-grounded"

# FR-003..FR-006 write path: Acceptance Scenario US2#1
assert_verdict "write-types" \
  '{"skip": false, "target":"@manifest/types/mistake.md", "section":"## Required frontmatter", "current":"c", "proposed":"p", "why":"seen in .wheel/outputs/create-mistake-result.md"}' \
  "write"

# US3#3 — @manifest/templates/*.md is a valid target
assert_verdict "write-templates" \
  '{"skip": false, "target":"@manifest/templates/about.md", "section":"top", "current":"c", "proposed":"p", "why":"see .wheel/outputs/x.json for evidence"}' \
  "write"

# US3#2 — @manifest/types/*.md is a valid target
assert_verdict "write-types-mistake" \
  '{"skip": false, "target":"@manifest/types/project-dashboard.md", "section":"top", "current":"c", "proposed":"p", "why":"see .kiln/mistakes/2026-04-16-x.md for rationale"}' \
  "write"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
