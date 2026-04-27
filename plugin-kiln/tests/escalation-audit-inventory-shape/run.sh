#!/usr/bin/env bash
# Test: escalation-audit-inventory-shape
#
# Anchors: SC-004 + SC-005 (NFR-003 byte-identical Events) of escalation-audit.
# Validates: FR-011..FR-015 of plugin-kiln/skills/kiln-escalation-audit/SKILL.md
# against contracts/interfaces.md §C.1 + §D.4.
#
# Strategy — extract-and-run:
#   The skill's logic lives in bash code fences inside SKILL.md (skills are
#   markdown the LLM reads + executes). This fixture extracts every ```bash
#   fence into a single concatenated script, runs it inside a scaffolded
#   $TMP dir with stubbed `.wheel/history/` JSON + an empty `.kiln/logs/`,
#   and asserts on the emitted report.
#
# Substrate: tier-2 (run.sh-only — no test.yaml). Invoke directly:
#   bash plugin-kiln/tests/escalation-audit-inventory-shape/run.sh
# Exit 0 on PASS, non-zero on FAIL. Last line is a PASS/FAIL summary.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL="$REPO_ROOT/plugin-kiln/skills/kiln-escalation-audit/SKILL.md"

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL: SKILL.md missing at $SKILL" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
assert() {
  local name="$1"; shift
  if "$@"; then
    PASS=$((PASS + 1))
    printf '  pass  %s\n' "$name"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n' "$name"
  fi
}

# ----------------------------------------------------------------------
# Helper: extract every ```bash ... ``` fence from SKILL.md into one
# concatenated script. Lines outside bash fences are dropped. The
# script's `set -uo pipefail` is reset at the top so individual case
# directories can run independently.
# ----------------------------------------------------------------------
extract_skill_to() {
  local out="$1"
  {
    printf 'set -uo pipefail\n'
    awk '/^```bash$/{flag=1;next} /^```$/{if(flag){flag=0;next}} flag' "$SKILL"
  } > "$out"
}

SKILL_SCRIPT="$TMP/skill.sh"
extract_skill_to "$SKILL_SCRIPT"

# Sanity: the extracted script MUST contain at least one of each ingestor's
# anchor strings (otherwise an upstream SKILL.md edit silently broke the
# fixture and we'd report false PASS).
assert_extract_sane() {
  grep -qF 'WHEEL_TSV' "$SKILL_SCRIPT" \
    && grep -qF 'GIT_TSV' "$SKILL_SCRIPT" \
    && grep -qF 'HOOK_TSV' "$SKILL_SCRIPT" \
    && grep -qF 'REPORT_PATH' "$SKILL_SCRIPT" \
    && grep -qF 'Verdict-tagging deferred' "$SKILL_SCRIPT"
}
assert "extract: SKILL.md bash fences contain all ingestors + report assembly" \
  assert_extract_sane

# ----------------------------------------------------------------------
# Case A: 3 wheel events, 0 git, 0 hook → asserts:
#   - report file at .kiln/logs/escalation-audit-*.md
#   - ## Events has exactly 3 data rows
#   - Summary shows `wheel | 3`, total `**3**`
#   - verdict-deferred placeholder present
# ----------------------------------------------------------------------
case_three_wheel_events() {
  local DIR="$TMP/case_a"
  mkdir -p "$DIR/.wheel/history" "$DIR/.kiln/logs"
  # Three pause events with deterministic ascending started_at timestamps.
  cat > "$DIR/.wheel/history/h1.json" <<'JSON'
{"workflow":"distill-multi-theme","awaiting_user_input":true,"started_at":"2026-04-20T10:00:00Z"}
JSON
  cat > "$DIR/.wheel/history/h2.json" <<'JSON'
{"workflow":"build-prd","awaiting_user_input":true,"started_at":"2026-04-21T11:00:00Z"}
JSON
  cat > "$DIR/.wheel/history/h3.json" <<'JSON'
{"workflow":"shelf-sync","awaiting_user_input":true,"started_at":"2026-04-22T12:00:00Z"}
JSON
  # Init a git repo with no matching commits so the git ingestor returns 0 rows.
  ( cd "$DIR" && git init -q && git config user.email t@t && git config user.name t \
    && git commit --allow-empty -q -m 'seed' )

  # Force-touch wheel files so find -mtime -30 picks them up regardless of
  # original creation time on the host (touch -d sets mtime).
  ( cd "$DIR" && touch .wheel/history/*.json )

  ( cd "$DIR" && bash "$SKILL_SCRIPT" > "$DIR/skill.stdout" 2> "$DIR/skill.stderr" )
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "    skill exited non-zero: $rc" >&2
    sed 's/^/    stderr: /' "$DIR/skill.stderr" >&2
    return 1
  fi

  local report
  report=$(ls "$DIR/.kiln/logs/escalation-audit-"*.md 2>/dev/null | head -1)
  if [[ -z "$report" || ! -f "$report" ]]; then
    echo "    no report file produced" >&2
    return 1
  fi

  # 3 data rows in ## Events table (each starts with `| 2026-`).
  local row_count
  row_count=$(awk '/^## Events/{flag=1;next} /^## /{flag=0} flag && /^\| 2026-/' "$report" | wc -l | tr -d ' ')
  if [[ "$row_count" != "3" ]]; then
    echo "    expected 3 event rows, got $row_count" >&2
    sed 's/^/    rep: /' "$report" >&2
    return 1
  fi

  # Summary count for wheel = 3.
  if ! grep -qE '\| wheel  \|[[:space:]]+3 \|' "$report"; then
    echo "    summary missing 'wheel | 3' row" >&2
    return 1
  fi

  # Total = 3.
  if ! grep -qF '| **Total** | **3** |' "$report"; then
    echo "    summary missing total **3**" >&2
    return 1
  fi

  # Verdict-deferred placeholder (FR-014).
  if ! grep -qF 'Verdict-tagging deferred — see roadmap item 2026-04-24-escalation-audit for design context.' "$report"; then
    echo "    verdict-deferred placeholder missing (FR-014)" >&2
    return 1
  fi

  # Stash report path for the idempotence sub-test.
  echo "$report" > "$DIR/_report_path"
  return 0
}
assert "Case A (FR-015 / SC-004): 3 wheel events → report has 3 events + wheel:3 + verdict-deferred" \
  case_three_wheel_events

# ----------------------------------------------------------------------
# Case A.idem (SC-005 / NFR-003): re-run on unchanged inputs.
# Diff of ## Events block between run-1 and run-2 MUST be empty.
# ----------------------------------------------------------------------
case_idempotent_events_block() {
  local DIR="$TMP/case_a"
  local run1
  run1=$(cat "$DIR/_report_path" 2>/dev/null) || return 1

  # Snapshot run-1 Events block before re-running.
  awk '/^## Events/{flag=1} /^## Notes/{flag=0} flag' "$run1" > "$DIR/events_run1.txt"

  # Re-run the skill (will write a NEW report file with a different timestamp).
  # Sleep just enough to guarantee the filename differs (the H1 timestamp uses
  # second precision); 1s keeps the cache window healthy.
  sleep 1
  ( cd "$DIR" && bash "$SKILL_SCRIPT" > "$DIR/skill2.stdout" 2> "$DIR/skill2.stderr" ) || return 1

  local run2
  run2=$(ls -t "$DIR/.kiln/logs/escalation-audit-"*.md 2>/dev/null | head -1)
  [[ "$run2" != "$run1" ]] || { echo "    second run did not produce a new file" >&2; return 1; }

  awk '/^## Events/{flag=1} /^## Notes/{flag=0} flag' "$run2" > "$DIR/events_run2.txt"
  if ! diff -q "$DIR/events_run1.txt" "$DIR/events_run2.txt" >/dev/null 2>&1; then
    echo "    Events block differs between runs (NFR-003 violated)" >&2
    diff "$DIR/events_run1.txt" "$DIR/events_run2.txt" | sed 's/^/    /' >&2
    return 1
  fi
  return 0
}
assert "Case A.idem (SC-005 / NFR-003): re-run produces byte-identical ## Events block" \
  case_idempotent_events_block

# ----------------------------------------------------------------------
# Case B (FR-013 empty-corpus path): zero events anywhere.
#   - .wheel/history/ exists but is empty → ingestor produces 0 rows.
#   - .kiln/logs/ exists but is empty.
#   - git repo exists with no matching commits.
# Report body MUST contain the literal "No pause events found in the last 30 days".
# ----------------------------------------------------------------------
case_empty_corpus() {
  local DIR="$TMP/case_b"
  mkdir -p "$DIR/.wheel/history" "$DIR/.kiln/logs"
  ( cd "$DIR" && git init -q && git config user.email t@t && git config user.name t \
    && git commit --allow-empty -q -m 'seed' )

  ( cd "$DIR" && bash "$SKILL_SCRIPT" > "$DIR/skill.stdout" 2> "$DIR/skill.stderr" )
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "    skill exited non-zero on empty corpus: $rc" >&2
    sed 's/^/    stderr: /' "$DIR/skill.stderr" >&2
    return 1
  fi

  local report
  report=$(ls "$DIR/.kiln/logs/escalation-audit-"*.md 2>/dev/null | head -1)
  [[ -n "$report" && -f "$report" ]] || { echo "    no report on empty corpus" >&2; return 1; }

  if ! grep -qF 'No pause events found in the last 30 days' "$report"; then
    echo "    empty-corpus body missing literal phrase (FR-013)" >&2
    sed 's/^/    rep: /' "$report" >&2
    return 1
  fi
  if ! grep -qF '(none)' "$report"; then
    echo "    empty-corpus body missing '(none)' for ## Events" >&2
    return 1
  fi
  if ! grep -qF 'Verdict-tagging deferred' "$report"; then
    echo "    empty-corpus body missing verdict-deferred placeholder (FR-014)" >&2
    return 1
  fi
  return 0
}
assert "Case B (FR-013): empty corpus → 'No pause events found in the last 30 days' + verdict-deferred" \
  case_empty_corpus

# ----------------------------------------------------------------------
# Case C: sort determinism — feed events with mixed-source timestamps;
# assert timestamps in ## Events are monotonically non-decreasing.
# ----------------------------------------------------------------------
case_sort_order() {
  local DIR="$TMP/case_c"
  mkdir -p "$DIR/.wheel/history" "$DIR/.kiln/logs"
  cat > "$DIR/.wheel/history/late.json" <<'JSON'
{"workflow":"a","awaiting_user_input":true,"started_at":"2026-04-25T09:00:00Z"}
JSON
  cat > "$DIR/.wheel/history/early.json" <<'JSON'
{"workflow":"b","awaiting_user_input":true,"started_at":"2026-04-23T09:00:00Z"}
JSON
  cat > "$DIR/.wheel/history/mid.json" <<'JSON'
{"workflow":"c","awaiting_user_input":true,"started_at":"2026-04-24T09:00:00Z"}
JSON
  ( cd "$DIR" && touch .wheel/history/*.json )
  ( cd "$DIR" && git init -q && git config user.email t@t && git config user.name t \
    && git commit --allow-empty -q -m 'seed' )

  ( cd "$DIR" && bash "$SKILL_SCRIPT" >/dev/null 2>&1 ) || return 1
  local report
  report=$(ls "$DIR/.kiln/logs/escalation-audit-"*.md 2>/dev/null | head -1)

  # Extract timestamps from event rows; verify ascending sort.
  local ts_list
  ts_list=$(awk '/^## Events/{flag=1;next} /^## /{flag=0} flag && /^\| 2026-/' "$report" \
    | awk -F'|' '{gsub(/ /,"",$2); print $2}')
  local sorted
  sorted=$(printf '%s\n' "$ts_list" | LC_ALL=C sort -s)
  if [[ "$ts_list" != "$sorted" ]]; then
    echo "    events not sorted ASC by timestamp (NFR-003)" >&2
    printf 'observed:\n%s\nexpected:\n%s\n' "$ts_list" "$sorted" | sed 's/^/    /' >&2
    return 1
  fi
  return 0
}
assert "Case C (NFR-003): sort key = (timestamp ASC, source ASC, surface ASC)" \
  case_sort_order

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
echo
if [[ $FAIL -eq 0 ]]; then
  echo "PASS: $PASS/$TOTAL assertions"
  exit 0
else
  echo "FAIL: $FAIL/$TOTAL assertions failed"
  exit 1
fi
