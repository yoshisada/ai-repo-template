#!/usr/bin/env bash
# run-team-e2e.sh — drive a wheel TEAM workflow E2E in an INTERACTIVE claude session.
#
# WHY: `claude --print` (headless) does NOT expose the TeamCreate/Agent team tools, so team
# workflows can't EXECUTE headless. A real PTY-backed interactive session DOES have them. This
# launches interactive `claude` inside tmux (real TTY), sends the driving prompt once, lets the
# model auto-drive the team workflow via wheel's Stop-hook loop, and monitors COMPLETION via the
# on-disk .wheel/ state (not the TUI). Wheel hooks are injected via --settings (same as the
# headless E2E recipe).
#
# Usage: run-team-e2e.sh [--keep]
# Verifies: a 2-member team (kiln-team-smoke) runs each teammate, team-wait collects, archives.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WHEEL="$REPO_ROOT/plugin-wheel"
FIX="$SCRIPT_DIR/fixtures"

UUID="$(uuidgen | tr '[:upper:]' '[:lower:]')"; SHORT="${UUID:0:8}"
DIR="/tmp/kiln-team-e2e-$SHORT"; SESS="kilnteam-$SHORT"
mkdir -p "$DIR/workflows"
git -C "$DIR" init -q; git -C "$DIR" config user.email e2e@kiln.local; git -C "$DIR" config user.name e2e

# Stage the team workflow + worker locally; rewrite the teammate ref to the unprefixed local name.
sed 's/kiln:kiln-team-smoke-worker/kiln-team-smoke-worker/g' "$FIX/kiln-team-smoke.json" > "$DIR/workflows/kiln-team-smoke.json"
cp "$FIX/kiln-team-smoke-worker.json" "$DIR/workflows/kiln-team-smoke-worker.json"
# Hardcode the absolute wheel path: Claude Code BLOCKS ${CLAUDE_PLUGIN_ROOT} in settings.json
# hooks (it's a plugin-only var), and the block hits teammate sub-agent contexts hardest.
sed "s#\${CLAUDE_PLUGIN_ROOT}#$WHEEL#g" "$WHEEL/hooks/hooks.json" > "$DIR/.wheel-hooks-settings.json"
git -C "$DIR" add -A >/dev/null 2>&1; git -C "$DIR" commit -q -m init >/dev/null 2>&1 || true

# Single-line prompt (no embedded newlines — multi-line send-keys can submit prematurely).
PROMPT='Drive the kiln-team-smoke wheel workflow to completion. First run the /wheel:wheel-run skill with input kiln-team-smoke (its Step 1 validate + Step 2 activate.sh). Then loop: do ONE hook-directed action, END YOUR TURN, obey the next Stop-hook additionalContext, repeat until the workflow archives. When a hook tells you to call TeamCreate or spawn teammate Agents, make those exact tool calls. HARD RULES (never violate): stay in THIS directory — never cd anywhere else; never build/rebuild/modify any plugin; never run npm/tsc/node on plugin source; never read or debug hook source. If a hook PRINTS AN ERROR, IGNORE it entirely and just end your turn — the workflow advances on its own; a hook error is NOT yours to fix. Never run wheel-status or wheel-stop. Your ONLY job is to make the exact tool calls the hooks request, ending your turn after each. Keep going until it finishes, then say DONE.'

echo "▶ team E2E (interactive/tmux): $DIR  session=$SESS"
tmux kill-session -t "$SESS" 2>/dev/null || true
tmux new-session -d -s "$SESS" -x 220 -y 50
# Launch interactive claude (real TTY -> team tools). Env-wipe the 4 collision vars; keep teams env.
tmux send-keys -t "$SESS" "cd $DIR && env -u CLAUDECODE -u AI_AGENT -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_EXECPATH CLAUDE_PLUGIN_ROOT='$WHEEL' claude --dangerously-skip-permissions --model sonnet --session-id $UUID --settings $DIR/.wheel-hooks-settings.json --plugin-dir $REPO_ROOT/plugin-kiln --plugin-dir $WHEEL" Enter
sleep 20  # boot to the "trust this folder?" prompt
tmux send-keys -t "$SESS" Enter   # accept "1. Yes, I trust this folder" (default-selected)
sleep 14  # welcome screen -> input box ready
# Submit the driving prompt: type the text, brief pause, then Enter (separate, so it isn't eaten).
tmux send-keys -t "$SESS" "$PROMPT"
sleep 3
tmux send-keys -t "$SESS" Enter
echo "  prompt sent; polling .wheel/ state for archive…"

ARCHIVED=""; CUR=""
for i in $(seq 1 60); do   # up to ~10 min (60 * 10s)
  sleep 10
  if ls "$DIR"/.wheel/history/*/*.json >/dev/null 2>&1; then
    ARCHIVED="$(ls -d "$DIR"/.wheel/history/*/ 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"; break
  fi
  if ls "$DIR"/.wheel/state_*.json >/dev/null 2>&1; then
    CUR="$(jq -r '"cursor=\(.cursor)/\(.steps|length) \(.steps[.cursor].id)/\(.steps[.cursor].status)"' "$DIR"/.wheel/state_*.json 2>/dev/null | head -1)"
    echo "  [$i] $CUR"
  fi
done

echo "=== RESULT ==="
echo "archived: ${ARCHIVED:-NONE (still active or stalled)}"
echo "teammate outputs:"; ls "$DIR"/.wheel/outputs/team-smoke-*.txt 2>/dev/null && cat "$DIR"/.wheel/outputs/team-smoke-*.txt 2>/dev/null
echo "team-wait summary:"; cat "$DIR"/.wheel/outputs/team-smoke-summary.json 2>/dev/null | head -c 500
echo; echo "final state/history:"; for s in "$DIR"/.wheel/state_*.json "$DIR"/.wheel/history/*/*.json; do [ -f "$s" ] && jq -r '"  cursor=\(.cursor)/\(.steps|length) steps=\([.steps[].status]|join(\",\"))"' "$s" 2>/dev/null; done
echo "=== TUI tail (for debugging) ==="; tmux capture-pane -t "$SESS" -p -S -40 2>/dev/null | tail -20
tmux kill-session -t "$SESS" 2>/dev/null || true
rm -rf "$HOME/.claude/teams/smoke" 2>/dev/null || true
echo "scratch: $DIR"
