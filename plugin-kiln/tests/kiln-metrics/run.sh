#!/usr/bin/env bash
# plugin-kiln/tests/kiln-metrics/run.sh
#
# Theme D regression / contract substrate. Pure-shell (run.sh-only) per
# per-test-substrate-hierarchy convention from PR #189 — kiln-test cannot
# discover this fixture (substrate gap B-1 in PRs #166/#168). Invoke directly:
#
#   bash plugin-kiln/tests/kiln-metrics/run.sh
#
# Citing: SC-007 (8 rows + column shape + stdout==log), SC-008 (missing
# extractor → unmeasurable + exit 0), FR-018 (each extractor invocable in
# isolation), FR-019 (timestamped log + no overwrite). NFR-004 (≥80% coverage
# via assertion-block count).
#
# What this proves: the orchestrator + render-row + 8 extractors honour the
# Theme D contract under: (1) all-extractors-present happy path, (2) one
# extractor missing, (3) one extractor crashing, (4) two runs at distinct
# timestamps producing distinct log files. Each extractor is also exercised
# standalone to assert FR-018 isolation.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SCRIPTS_DIR="$REPO_ROOT/plugin-kiln/scripts/metrics"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

assert() {
  local label="$1"
  shift
  if "$@"; then
    PASS=$((PASS + 1))
    echo "PASS: $label"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
  fi
}

# ---------------------------------------------------------------------------
# Setup: fake repo root with deterministic fixtures so extractors return known
# (or unmeasurable) values without depending on this repo's live state.
# ---------------------------------------------------------------------------
mkdir -p "$TMP/.kiln/logs" \
         "$TMP/.kiln/roadmap/items/declined" \
         "$TMP/.kiln/feedback" \
         "$TMP/.kiln/mistakes" \
         "$TMP/docs/features/2026-04-27-x" \
         "$TMP/.wheel/history" \
         "$TMP/.trim"

# Init a real git history so signal (a) extractor can run `git log` cleanly.
( cd "$TMP" && git init -q && \
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m "init" )

# Seed deterministic content for each extractor surface.
cat > "$TMP/docs/features/2026-04-27-x/PRD.md" <<'PRD'
---
derived_from:
  - .kiln/feedback/x.md
---
PRD body.
PRD

touch "$TMP/.kiln/feedback/x.md"
touch "$TMP/.kiln/roadmap/items/declined/2026-04-27-decline-considered-and-declined.md"
touch "$TMP/.shelf-config"
touch "$TMP/.kiln/mistakes/2026-04-27-thing.md"

# Fresh hook log so signal (e) is on-track.
cat > "$TMP/.kiln/logs/hook-2026-04-27.log" <<'LOG'
2026-04-27 block: src/ edit refused (no spec)
LOG

# Fresh kiln-test verdict so signal (g) is on-track.
cat > "$TMP/.kiln/logs/kiln-test-fixture.md" <<'VER'
# verdict
PASS
VER

# Fresh wheel history with one escalation event so signal (b) is on-track (<=10).
cat > "$TMP/.wheel/history/2026-04-27.jsonl" <<'HIST'
{"event":"escalation","reason":"precedent absent"}
HIST

# Make sure mtimes for find -mtime -90 / -mtime -30 land inside the windows.
touch -t "$(date -u +%Y%m%d)0000.00" \
  "$TMP/.kiln/logs/hook-2026-04-27.log" \
  "$TMP/.kiln/logs/kiln-test-fixture.md" \
  "$TMP/.wheel/history/2026-04-27.jsonl" 2>/dev/null || true

export KILN_REPO_ROOT="$TMP"

# ---------------------------------------------------------------------------
# Block 1 — render-row.sh contract.
# ---------------------------------------------------------------------------
ROW="$(bash "$SCRIPTS_DIR/render-row.sh" "(a)" "1" ">=1" "on-track" "ev")"
assert "render-row emits pipe-delimited row" \
  test "$ROW" = "| (a) | 1 | >=1 | on-track | ev |"

assert "render-row escapes embedded pipes" \
  bash -c '[[ "$(bash "'"$SCRIPTS_DIR"'/render-row.sh" s a "tg|t" on-track "ev|cite")" == *"tg\\|t"*"ev\\|cite"* ]]'

if bash "$SCRIPTS_DIR/render-row.sh" "(a)" "1" ">=1" "no-such-status" "ev" >/dev/null 2>&1; then
  assert "render-row rejects unknown status (exit 2)" false
else
  RC=$?
  assert "render-row rejects unknown status (exit 2)" test "$RC" -eq 2
fi

# ---------------------------------------------------------------------------
# Block 2 — FR-018: each extract-signal-<x>.sh runs standalone and emits one
# tab-separated row line. Per signal × 8 = 8 assertions here.
# ---------------------------------------------------------------------------
for s in a b c d e f g h; do
  OUT="$(bash "$SCRIPTS_DIR/extract-signal-$s.sh" 2>/dev/null || true)"
  # The extractor MUST emit at least one line whose first tab-separated field
  # is the signal id literal "($s)".
  FIRST_FIELD="$(printf '%s\n' "$OUT" | head -n1 | awk -F'\t' '{print $1}')"
  assert "extract-signal-$s.sh emits a row with signal id ($s)" \
    test "$FIRST_FIELD" = "($s)"
done

# ---------------------------------------------------------------------------
# Block 3 — orchestrator happy path: 8 rows, prescribed columns, stdout==log.
# ---------------------------------------------------------------------------
export KILN_METRICS_NOW="2026-04-27-120000"

STDOUT_FILE="$TMP/orchestrator-stdout.txt"
bash "$SCRIPTS_DIR/orchestrator.sh" > "$STDOUT_FILE"
LOG_PATH="$TMP/.kiln/logs/metrics-$KILN_METRICS_NOW.md"

assert "orchestrator wrote log at deterministic timestamp path" test -f "$LOG_PATH"

# SC-007: stdout == log file contents, byte-identical.
assert "stdout matches log file (SC-007)" \
  cmp -s "$STDOUT_FILE" "$LOG_PATH"

# SC-007: 8 row lines (columns matching `| (x) |`).
ROW_COUNT="$(grep -cE '^\| \([a-h]\) \|' "$LOG_PATH" || true)"
assert "orchestrator emits exactly 8 signal rows (SC-007)" \
  test "$ROW_COUNT" -eq 8

# SC-007: rows appear in (a)..(h) order.
ORDER="$(grep -oE '^\| \([a-h]\) \|' "$LOG_PATH" | tr -d ' |()' | tr -d '\n')"
assert "rows in (a)..(h) order" \
  test "$ORDER" = "abcdefgh"

# Header line shape.
assert "header column line present (FR-016)" \
  grep -q '^| signal | current_value | target | status | evidence |$' "$LOG_PATH"

# Every row carries one of the three permitted status values.
INVALID_STATUS="$(grep -E '^\| \([a-h]\) \|' "$LOG_PATH" \
  | awk -F'|' '{ gsub(/^ +| +$/, "", $5); print $5 }' \
  | grep -vxE 'on-track|at-risk|unmeasurable' || true)"
assert "every row has status in {on-track,at-risk,unmeasurable}" \
  test -z "$INVALID_STATUS"

# ---------------------------------------------------------------------------
# Block 4 — SC-008: missing extractor → unmeasurable + exit 0.
# ---------------------------------------------------------------------------
SAVED="$(mktemp)"
mv "$SCRIPTS_DIR/extract-signal-c.sh" "$SAVED"
trap 'mv "$SAVED" "'"$SCRIPTS_DIR"'/extract-signal-c.sh" 2>/dev/null; rm -rf "$TMP"' EXIT

KILN_METRICS_NOW="2026-04-27-130000" \
  bash "$SCRIPTS_DIR/orchestrator.sh" >"$TMP/missing-out.txt"
RC=$?
assert "orchestrator exits 0 even when an extractor file is missing (SC-008)" \
  test "$RC" -eq 0

assert "missing-extractor row carries 'unmeasurable' (SC-008)" \
  grep -qE '^\| \(c\) \|.* unmeasurable .*' "$TMP/missing-out.txt"

# Restore.
mv "$SAVED" "$SCRIPTS_DIR/extract-signal-c.sh"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Block 5 — extractor that crashes is converted to unmeasurable.
# ---------------------------------------------------------------------------
SAVED2="$(mktemp)"
mv "$SCRIPTS_DIR/extract-signal-c.sh" "$SAVED2"
cat > "$SCRIPTS_DIR/extract-signal-c.sh" <<'BAD'
#!/usr/bin/env bash
echo "boom" >&2
exit 7
BAD
chmod +x "$SCRIPTS_DIR/extract-signal-c.sh"
trap 'mv "$SAVED2" "'"$SCRIPTS_DIR"'/extract-signal-c.sh" 2>/dev/null; rm -rf "$TMP"' EXIT

KILN_METRICS_NOW="2026-04-27-140000" \
  bash "$SCRIPTS_DIR/orchestrator.sh" >"$TMP/crash-out.txt"
RC=$?
assert "orchestrator exits 0 when an extractor crashes (FR-017)" \
  test "$RC" -eq 0
assert "crashing extractor row tagged unmeasurable (FR-017)" \
  grep -qE '^\| \(c\) \|.* unmeasurable .*' "$TMP/crash-out.txt"

# Restore.
mv "$SAVED2" "$SCRIPTS_DIR/extract-signal-c.sh"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Block 6 — FR-019: distinct timestamps produce distinct log files; existing
# log is not overwritten.
# ---------------------------------------------------------------------------
KILN_METRICS_NOW="2026-04-27-150000" bash "$SCRIPTS_DIR/orchestrator.sh" >/dev/null
KILN_METRICS_NOW="2026-04-27-150100" bash "$SCRIPTS_DIR/orchestrator.sh" >/dev/null

assert "first log persisted at metrics-2026-04-27-150000.md (FR-019)" \
  test -f "$TMP/.kiln/logs/metrics-2026-04-27-150000.md"
assert "second log persisted at metrics-2026-04-27-150100.md (FR-019)" \
  test -f "$TMP/.kiln/logs/metrics-2026-04-27-150100.md"

# Same timestamp re-run must NOT overwrite — orchestrator suffixes -2.
KILN_METRICS_NOW="2026-04-27-150000" bash "$SCRIPTS_DIR/orchestrator.sh" >/dev/null
assert "same-timestamp re-run suffixes -2 (FR-019 no-overwrite)" \
  test -f "$TMP/.kiln/logs/metrics-2026-04-27-150000-2.md"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "---"
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if (( FAIL > 0 )); then
  echo "FAIL: kiln-metrics fixture"
  exit 1
fi
echo "PASS: kiln-metrics fixture"
exit 0
