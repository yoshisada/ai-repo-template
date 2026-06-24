#!/usr/bin/env bash
#
# Dogfood harness — drive a kiln/wheel workflow LIVE as the user would, in a
# fresh isolated Claude subprocess, then record cost and surface the output for
# an accuracy judgement.
#
# WHY this exists: JSON-parses-and-validates is not "tested". The product is the
# loop; the loop is only real if a fresh subprocess can run it end-to-end against
# the LOCAL plugin source and produce senior-bar output. See
# docs/features/2026-06-22-kiln-autonomous-rearchitecture/IMPLEMENTATION_PLAN.md §6.
#
# Three isolation guarantees (missing any one re-collides with the parent session):
#   1. env-wipe of CLAUDECODE / AI_AGENT / CLAUDE_CODE_ENTRYPOINT / CLAUDE_CODE_EXECPATH
#   2. unique --session-id
#   3. separate cwd (/tmp scratch dir with its own .wheel/)
# Plus the load-bearing fourth piece for dogfooding LOCAL edits: --plugin-dir points
# at this repo's plugin-<name>/ source, NOT the published ~/.claude/plugins cache.
#
# Usage:
#   plugin-kiln/tests/dogfood/run-scenario.sh <scenario.md> [--budget-usd N] [--model M] [--keep]
#
#   <scenario.md>   prompt file; the fresh subprocess sees ONLY this text, so it must
#                   use concrete absolute paths and literal names (no <placeholders>).
#   --budget-usd N  hard cap passed to claude --max-budget-usd (default 5.00)
#   --model M       model for the run (default sonnet)
#   --keep          do not delete the scratch dir (default: keep; pass --clean to remove)
#   --clean         remove the scratch dir after the run
#
# Output: a markdown log at .kiln/logs/dogfood-<scenario>-<UTC>.md with the cost
# row, the raw result text, and the scratch path for inspection. Accuracy verdict
# is judged by a human/agent reading the output — the harness records, it does not grade.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# ── args ──────────────────────────────────────────────────────────────────────
SCENARIO=""
BUDGET_USD="5.00"
MODEL="sonnet"
CLEAN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --budget-usd) BUDGET_USD="$2"; shift 2 ;;
    --model)      MODEL="$2"; shift 2 ;;
    --keep)       CLEAN=0; shift ;;
    --clean)      CLEAN=1; shift ;;
    -h|--help)    sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)            SCENARIO="$1"; shift ;;
  esac
done

if [ -z "$SCENARIO" ] || [ ! -f "$SCENARIO" ]; then
  echo "ERROR: scenario file not found: '$SCENARIO'" >&2
  echo "Usage: $0 <scenario.md> [--budget-usd N] [--model M] [--clean]" >&2
  exit 2
fi
SCENARIO="$(cd "$(dirname "$SCENARIO")" && pwd)/$(basename "$SCENARIO")"  # absolutize

command -v claude >/dev/null || { echo "ERROR: claude CLI not on PATH" >&2; exit 2; }
command -v jq >/dev/null     || { echo "ERROR: jq not on PATH" >&2; exit 2; }

UUID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
SHORT="${UUID:0:8}"
TESTDIR="/tmp/kiln-dogfood-$SHORT"
SCEN_NAME="$(basename "$SCENARIO" .md)"
# Avoid Date.now() unavailability in the parent harness by stamping via the shell here:
TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_DIR="$REPO_ROOT/.kiln/logs"
LOG="$LOG_DIR/dogfood-$SCEN_NAME-$TS.md"
RESULT_JSON="$TESTDIR/.dogfood-result.json"

mkdir -p "$TESTDIR" "$LOG_DIR"

# Fresh git repo so branch/commit-emitting workflows behave like a real consumer project.
git -C "$TESTDIR" init -q
git -C "$TESTDIR" config user.email "dogfood@kiln.local"
git -C "$TESTDIR" config user.name "kiln dogfood"
git -C "$TESTDIR" commit -q --allow-empty -m "init" 2>/dev/null || true

# Load EVERY plugin from local source so cross-plugin calls (wheel-run, shelf-sync) resolve.
PLUGIN_FLAGS=()
for p in kiln shelf wheel clay trim; do
  PLUGIN_FLAGS+=(--plugin-dir "$REPO_ROOT/plugin-$p")
done

echo "▶ dogfood: $SCEN_NAME"
echo "  scratch:  $TESTDIR"
echo "  model:    $MODEL   budget: \$$BUDGET_USD"
echo "  plugins:  local source (kiln shelf wheel clay trim)"
echo "  session:  $UUID"
echo "  running…"

START_EPOCH="$(date +%s)"

# The three-part isolation + local plugin load. --output-format json gives us the
# cost/usage block. --add-dir lets the subprocess's CLAUDE.md/tools reach the scratch.
env -u CLAUDECODE -u AI_AGENT -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_EXECPATH \
  bash -c "cd '$TESTDIR' && claude --print --dangerously-skip-permissions \
    --model '$MODEL' --session-id '$UUID' --max-budget-usd '$BUDGET_USD' \
    ${PLUGIN_FLAGS[*]} --add-dir '$TESTDIR' \
    --output-format json < '$SCENARIO'" > "$RESULT_JSON" 2>"$TESTDIR/.dogfood-stderr.txt"
RUN_RC=$?

END_EPOCH="$(date +%s)"
ELAPSED=$(( END_EPOCH - START_EPOCH ))

# ── extract cost/usage (tolerant of shape changes / non-JSON on error) ─────────
parse() { jq -r "$1 // empty" "$RESULT_JSON" 2>/dev/null; }
COST_USD="$(parse '.total_cost_usd')"
TOK_IN="$(parse '.usage.input_tokens')"
TOK_OUT="$(parse '.usage.output_tokens')"
TOK_CACHE_R="$(parse '.usage.cache_read_input_tokens')"
NUM_TURNS="$(parse '.num_turns')"
IS_ERROR="$(parse '.is_error')"
RESULT_TEXT="$(parse '.result')"
DUR_MS="$(parse '.duration_ms')"
[ -z "$RESULT_TEXT" ] && RESULT_TEXT="$(cat "$RESULT_JSON" 2>/dev/null | head -c 4000)"
: "${COST_USD:=unknown}" "${TOK_IN:=?}" "${TOK_OUT:=?}" "${NUM_TURNS:=?}" "${IS_ERROR:=?}"

# ── write log ──────────────────────────────────────────────────────────────────
{
  echo "# Dogfood run — $SCEN_NAME"
  echo
  echo "| Field | Value |"
  echo "|---|---|"
  echo "| Scenario | \`$(realpath --relative-to="$REPO_ROOT" "$SCENARIO" 2>/dev/null || echo "$SCENARIO")\` |"
  echo "| Timestamp (UTC) | $TS |"
  echo "| Model | $MODEL |"
  echo "| Budget cap | \$$BUDGET_USD |"
  echo "| Session id | $UUID |"
  echo "| Scratch dir | \`$TESTDIR\` |"
  echo "| Exit rc | $RUN_RC |"
  echo "| is_error | $IS_ERROR |"
  echo
  echo "## Cost (record — review for waste, do not gate)"
  echo
  echo "| Metric | Value |"
  echo "|---|---|"
  echo "| Cost USD | $COST_USD |"
  echo "| Input tokens | $TOK_IN |"
  echo "| Output tokens | $TOK_OUT |"
  echo "| Cache read tokens | ${TOK_CACHE_R:-?} |"
  echo "| Turns | $NUM_TURNS |"
  echo "| Wall time (s) | $ELAPSED |"
  echo "| Reported duration (ms) | ${DUR_MS:-?} |"
  echo
  echo "## Result (judge accuracy against the senior-engineer bar)"
  echo
  echo '```'
  echo "$RESULT_TEXT"
  echo '```'
  echo
  echo "## Scratch artifacts"
  echo
  echo "Inspect the produced project at \`$TESTDIR\` (kept unless --clean)."
  echo "Wheel logs: \`$TESTDIR/.wheel/logs/\` · run artifacts: \`$TESTDIR/.kiln/runs/\`"
  if [ -s "$TESTDIR/.dogfood-stderr.txt" ]; then
    echo
    echo "### stderr (first 2KB)"
    echo '```'
    head -c 2048 "$TESTDIR/.dogfood-stderr.txt"
    echo '```'
  fi
} > "$LOG"

echo "  done (rc=$RUN_RC, ${ELAPSED}s, cost=\$$COST_USD, out=${TOK_OUT}tok)"
echo "  log:     $(realpath --relative-to="$REPO_ROOT" "$LOG" 2>/dev/null || echo "$LOG")"
echo "  scratch: $TESTDIR"

if [ "$CLEAN" = "1" ]; then
  rm -rf "$TESTDIR"
  echo "  cleaned scratch dir"
fi

# rc mirrors the subprocess: non-zero if the run itself errored. Accuracy is judged
# separately by reading the log — a 0 rc does NOT mean the output was good.
exit "$RUN_RC"
