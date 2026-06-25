#!/usr/bin/env bash
# run-workflow-e2e.sh — drive a kiln WHEEL WORKFLOW end-to-end in an isolated subprocess
# with wheel's hooks actually ACTIVE (so the workflow advances step-by-step).
#
# WHY this is different from run-scenario.sh: wheel workflows are driven by wheel's
# PostToolUse/Stop hooks. A bare `--plugin-dir` subprocess does NOT fire those hooks (the
# wheel test fixtures document this), so workflows never advance there. This runner force-
# injects wheel's hooks via `claude --settings` (with CLAUDE_PLUGIN_ROOT pointed at the LOCAL
# plugin-wheel so the hook commands resolve), giving the subprocess a live wheel hook
# environment — the same thing that makes /wheel:wheel-run work in a real session.
#
# Usage: run-workflow-e2e.sh <workflow-name> <prompt-file> [--budget-usd N] [--model M] [--keep]
#   <workflow-name>  e.g. kiln-mistake-record (must exist at plugin-kiln/workflows/<name>.json)
#   <prompt-file>    the as-the-user prompt driving + reporting on the run
# Writes a log to .kiln/logs/e2e-<workflow>-<UTC>.md and keeps the scratch for inspection.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WHEEL_DIR="$REPO_ROOT/plugin-wheel"

WF=""; PROMPT=""; BUDGET="6.00"; MODEL="sonnet"; CLEAN=0; INIT_KILN=0; SEED_CONFIG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --budget-usd) BUDGET="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --keep) CLEAN=0; shift ;;
    --clean) CLEAN=1; shift ;;
    --init-kiln) INIT_KILN=1; shift ;;  # scaffold .kiln config + force autonomous mode (no checkpoint pauses)
    --seed-config) SEED_CONFIG="$2"; shift 2 ;;  # write this JSON to .kiln/config.json BEFORE the run (deterministic)
    *) if [ -z "$WF" ]; then WF="$1"; elif [ -z "$PROMPT" ]; then PROMPT="$1"; fi; shift ;;
  esac
done

WF_FILE="$REPO_ROOT/plugin-kiln/workflows/${WF}.json"
[ -f "$WF_FILE" ] || { echo "ERROR: workflow not found: $WF_FILE" >&2; exit 2; }
[ -f "$PROMPT" ] || { echo "ERROR: prompt file not found: $PROMPT" >&2; exit 2; }
PROMPT="$(cd "$(dirname "$PROMPT")" && pwd)/$(basename "$PROMPT")"
command -v claude >/dev/null || { echo "ERROR: claude not on PATH" >&2; exit 2; }

UUID="$(uuidgen | tr '[:upper:]' '[:lower:]')"; SHORT="${UUID:0:8}"
TESTDIR="/tmp/kiln-e2e-$SHORT"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$REPO_ROOT/.kiln/logs/e2e-${WF}-${TS}.md"
mkdir -p "$TESTDIR/workflows" "$TESTDIR/.wheel/inputs" "$TESTDIR/.wheel/outputs" "$REPO_ROOT/.kiln/logs"

# Real consumer-ish project: git + the workflow available under ./workflows (local discovery).
git -C "$TESTDIR" init -q
git -C "$TESTDIR" config user.email "e2e@kiln.local"; git -C "$TESTDIR" config user.name "kiln e2e"
cp "$WF_FILE" "$TESTDIR/workflows/${WF}.json"
# Co-locate any kiln sub-workflows the target may invoke (teammates / type:workflow steps).
for dep in "$REPO_ROOT"/plugin-kiln/workflows/*.json; do cp "$dep" "$TESTDIR/workflows/" 2>/dev/null || true; done
if [ "$INIT_KILN" = 1 ]; then
  ( cd "$TESTDIR" && node "$REPO_ROOT/plugin-kiln/bin/init.mjs" init >/dev/null 2>&1 )
  # Force autonomous mode so checkpoint (approval) steps don't pause a headless run.
  if [ -f "$TESTDIR/.kiln/config.json" ]; then
    jq '.review_mode="autonomous" | .review_checkpoints=[] | .auto_pr=true | .auto_merge=true | .auto_build=true' \
      "$TESTDIR/.kiln/config.json" > "$TESTDIR/.kiln/config.json.tmp" && mv "$TESTDIR/.kiln/config.json.tmp" "$TESTDIR/.kiln/config.json"
  fi
fi
if [ -n "$SEED_CONFIG" ]; then mkdir -p "$TESTDIR/.kiln"; printf '%s' "$SEED_CONFIG" > "$TESTDIR/.kiln/config.json"; fi
git -C "$TESTDIR" add -A >/dev/null 2>&1; git -C "$TESTDIR" commit -q -m init >/dev/null 2>&1 || true

# Force-inject wheel's hooks. ${CLAUDE_PLUGIN_ROOT} in the hook commands is bash-expanded at
# run time from the env var we export below -> resolves to the LOCAL plugin-wheel.
SETTINGS="$TESTDIR/.wheel-hooks-settings.json"
# Hardcode the absolute wheel path — Claude Code blocks ${CLAUDE_PLUGIN_ROOT} in settings.json hooks.
sed "s#\${CLAUDE_PLUGIN_ROOT}#$WHEEL_DIR#g" "$WHEEL_DIR/hooks/hooks.json" > "$SETTINGS"

echo "▶ e2e: $WF"
echo "  scratch: $TESTDIR   model: $MODEL   budget: \$$BUDGET"
echo "  wheel hooks: injected via --settings (CLAUDE_PLUGIN_ROOT -> local plugin-wheel)"
echo "  running…"
START="$(date +%s)"

( cd "$TESTDIR"
  env -u CLAUDECODE -u AI_AGENT -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_EXECPATH \
    CLAUDE_PLUGIN_ROOT="$WHEEL_DIR" \
    claude --print --dangerously-skip-permissions \
      --model "$MODEL" --session-id "$UUID" --max-budget-usd "$BUDGET" \
      --plugin-dir "$REPO_ROOT/plugin-kiln" --plugin-dir "$REPO_ROOT/plugin-wheel" --plugin-dir "$REPO_ROOT/plugin-shelf" \
      --settings "$SETTINGS" --add-dir "$TESTDIR" \
      --output-format json < "$PROMPT"
) > "$TESTDIR/.result.json" 2>"$TESTDIR/.stderr.txt"
RC=$?
ELAPSED=$(( $(date +%s) - START ))

RESULT="$(jq -r '.result // empty' "$TESTDIR/.result.json" 2>/dev/null)"; [ -z "$RESULT" ] && RESULT="$(head -c 3000 "$TESTDIR/.result.json")"
COST="$(jq -r '.total_cost_usd // "?"' "$TESTDIR/.result.json" 2>/dev/null)"

{
  echo "# E2E run — $WF"
  echo; echo "scratch: \`$TESTDIR\`  ·  rc=$RC  ·  ${ELAPSED}s  ·  cost=\$$COST  ·  $TS"
  echo
  echo "## Wheel state evidence (did the workflow advance via hooks?)"
  echo '```'
  echo "state files:"; ls -1 "$TESTDIR"/.wheel/state_*.json 2>/dev/null || echo "  (none)"
  echo "history archives:"; ls -1 "$TESTDIR"/.wheel/history/*/*.json 2>/dev/null | tail -3 || echo "  (none)"
  echo "wheel.log tail:"; tail -15 "$TESTDIR"/.wheel/logs/wheel.log 2>/dev/null || echo "  (no wheel.log)"
  echo "cursor / step status:"; for s in "$TESTDIR"/.wheel/state_*.json "$TESTDIR"/.wheel/history/*/*.json; do [ -f "$s" ] && jq -r '"  cursor=\(.cursor) steps=\([.steps[].status]|join(","))"' "$s" 2>/dev/null; done | tail -3
  echo '```'
  echo; echo "## Produced outputs"
  echo '```'; find "$TESTDIR/.wheel/outputs" "$TESTDIR/.kiln" -type f 2>/dev/null | sed "s#$TESTDIR/##" | head -40; echo '```'
  echo; echo "## Model result"
  echo '```'; echo "$RESULT"; echo '```'
  if [ -s "$TESTDIR/.stderr.txt" ]; then echo; echo "## stderr (2KB)"; echo '```'; head -c 2048 "$TESTDIR/.stderr.txt"; echo '```'; fi
} > "$LOG"

echo "  done (rc=$RC, ${ELAPSED}s, cost=\$$COST)"
echo "  log: $(realpath --relative-to="$REPO_ROOT" "$LOG" 2>/dev/null || echo "$LOG")"
echo "  scratch: $TESTDIR"
[ "$CLEAN" = 1 ] && rm -rf "$TESTDIR"
exit "$RC"
