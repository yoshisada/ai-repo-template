#!/usr/bin/env bash
# run-buildprd-e2e.sh — drive the FULL kiln-build-prd (38 steps, real teams) E2E in an
# interactive tmux claude session (team tools are interactive-only). Autonomous config so no
# checkpoint pauses. Monitors completion via on-disk .wheel/ state.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WHEEL="$REPO/plugin-wheel"
UUID="$(uuidgen | tr '[:upper:]' '[:lower:]')"; SHORT="${UUID:0:8}"
DIR="/tmp/kiln-bp-e2e-$SHORT"; SESS="kilnbp-$SHORT"
mkdir -p "$DIR/workflows" "$DIR/.wheel/inputs" "$DIR/.wheel/outputs"
git -C "$DIR" init -q; git -C "$DIR" config user.email e2e@kiln.local; git -C "$DIR" config user.name e2e

# Stage ALL kiln workflows locally; rewrite teammate plugin refs -> local names so they resolve
# from the scratch workflows/ (uses MY local code, unambiguously).
for f in "$REPO"/plugin-kiln/workflows/*.json; do cp "$f" "$DIR/workflows/"; done
sed -i '' 's/kiln:kiln-implement-worker/kiln-implement-worker/g; s/kiln:kiln-audit-worker/kiln-audit-worker/g' "$DIR/workflows/kiln-build-prd.json"

# Autonomous config (no checkpoint pauses).
( cd "$DIR" && node "$REPO/plugin-kiln/bin/init.mjs" init >/dev/null 2>&1 )
jq '.review_mode="autonomous" | .review_checkpoints=[] | .auto_pr=true | .auto_merge=true | .auto_build=true' \
  "$DIR/.kiln/config.json" > "$DIR/.kiln/config.json.tmp" && mv "$DIR/.kiln/config.json.tmp" "$DIR/.kiln/config.json"

# Seed a trivial real PRD.
mkdir -p "$DIR/docs/features/2026-06-24-slugify"
cat > "$DIR/docs/features/2026-06-24-slugify/PRD.md" <<'EOF'
# PRD: slugify utility
## Overview
A small pure function slugify(text) that converts a string to a URL-safe kebab-case slug.
## User Stories
- US-1: As a developer, I want slugify("Hello World!") to return "hello-world" for clean URLs.
## Functional Requirements
- FR-001: slugify lowercases the input.
- FR-002: slugify replaces any run of non-alphanumeric characters with a single hyphen.
- FR-003: slugify trims leading/trailing hyphens.
## Success Criteria
- SC-001 (FR-001..003): slugify("  Hello, World!! ") returns "hello-world".
EOF
echo "2026-06-24-slugify" > "$DIR/.wheel/inputs/prd-slug.txt"

# Inject wheel hooks (hardcoded path — Claude Code blocks ${CLAUDE_PLUGIN_ROOT} in settings).
sed "s#\${CLAUDE_PLUGIN_ROOT}#$WHEEL#g" "$WHEEL/hooks/hooks.json" > "$DIR/.wheel-hooks-settings.json"
git -C "$DIR" add -A >/dev/null 2>&1; git -C "$DIR" commit -q -m init >/dev/null 2>&1 || true

PROMPT='Drive the kiln-build-prd wheel workflow to completion. ONCE — and only once, at the very start — run the /wheel:wheel-run skill with input kiln-build-prd (Step 1 validate + Step 2 activate.sh) to activate the workflow. Then DRIVE THE LOOP ACTIVELY: each time the Stop hook blocks your turn (you will see "Blocked by hook"), the next instruction is waiting for you — IMMEDIATELY read the file .wheel/.next-instruction.md and do EXACTLY what it says (perform that agent step, OR make that exact spawn call — this Claude Code spawns teammates DIRECTLY via the Agent tool, there is NO TeamCreate tool), then end your turn so the hook advances. NEVER passively wait or say "waiting for hooks" — when blocked, read .wheel/.next-instruction.md and ACT. Repeat until the workflow archives. For agent steps, do the real work the instruction describes (write the spec/plan/code/etc.). For team steps, make the exact Agent spawn calls the instruction gives. Config is autonomous so there are NO approval pauses. HARD RULES (never violate): NEVER run /wheel:wheel-run or activate.sh more than the single time at the start — re-activating FORKS the workflow state into two desynced lineages and breaks the run; if you ever feel lost, the ONLY recovery is to read .wheel/.next-instruction.md (end your turn once first if it looks stale) and act, never to re-activate. Stay in THIS directory, never cd elsewhere; never build/rebuild/modify any plugin or run npm/tsc/node on plugin source; never run wheel-status/wheel-skip/wheel-stop. If a hook prints an error OTHER than the next-instruction block, ignore it. The create-pr step will fail (no git remote) — expected, keep going. Drive patiently through all ~38 steps until it archives, then say DONE.'

echo "▶ build-prd E2E (interactive tmux): $DIR  session=$SESS"
tmux kill-session -t "$SESS" 2>/dev/null || true
tmux new-session -d -s "$SESS" -x 220 -y 50
# CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 is REQUIRED — agent teams are disabled by
# default; without it the implement/audit team steps spawn no teammates.
# --no-chrome: suppress the Chrome-extension browser-tools permission prompt that
# otherwise blocks the fresh interactive session at startup (before activation).
# CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=100000 is REQUIRED for unattended runs: wheel
# drives every step via a Stop-hook block, and team-wait emits many consecutive
# "still waiting" blocks while a teammate works. The default cap is 9 — past it
# Claude Code overrides + ends the turn, idling the workflow. (Manual nudging
# masked this by resetting the consecutive-block counter each nudge.)
tmux send-keys -t "$SESS" "cd $DIR && env -u CLAUDECODE -u AI_AGENT -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_EXECPATH CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=100000 CLAUDE_PLUGIN_ROOT='$WHEEL' claude --no-chrome --dangerously-skip-permissions --model sonnet --session-id $UUID --settings $DIR/.wheel-hooks-settings.json --plugin-dir $REPO/plugin-kiln --plugin-dir $WHEEL" Enter
sleep 20; tmux send-keys -t "$SESS" Enter; sleep 14   # dismiss trust prompt, wait for input box
tmux send-keys -t "$SESS" "$PROMPT"; sleep 3; tmux send-keys -t "$SESS" Enter
echo "  prompt sent; polling .wheel/ for archive (up to ~40 min)…"

ARCHIVED=""; LAST=""
for i in $(seq 1 240); do   # 240 * 10s = 40 min
  sleep 10
  if ls "$DIR"/.wheel/history/*/*.json >/dev/null 2>&1; then ARCHIVED="$(ls "$DIR"/.wheel/history/ 2>/dev/null | tr '\n' ' ')"; break; fi
  CUR=""; for s in "$DIR"/.wheel/state_*.json; do [ -f "$s" ] && CUR="$CUR [$(jq -r '"\(.workflow_name):c\(.cursor)/\(.steps|length):\(.steps[.cursor].id // \"?\")"' "$s" 2>/dev/null)]"; done
  [ "$CUR" != "$LAST" ] && { echo "  [$i]$CUR  src=$(find "$DIR/src" -type f 2>/dev/null | wc -l|tr -d ' ') specs=$(find "$DIR/specs" -name '*.md' 2>/dev/null|wc -l|tr -d ' ')"; LAST="$CUR"; }
done

echo "=== RESULT ==="
echo "archived: ${ARCHIVED:-NONE (still active / truncated — resumable)}"
echo "main workflow final:"; for s in "$DIR"/.wheel/state_*.json "$DIR"/.wheel/history/*/*.json; do [ -f "$s" ] && jq -r '"  \(.workflow_name): cursor=\(.cursor)/\(.steps|length)"' "$s" 2>/dev/null; done | grep build-prd | head -1
echo "artifacts produced:"; find "$DIR/specs" "$DIR/src" -type f 2>/dev/null | sed "s#$DIR/##" | head -30
echo "audit verdicts:"; ls "$DIR"/.wheel/outputs/audit-*-verdict.json 2>/dev/null
echo "summary:"; cat "$DIR"/.kiln/runs/*/summary.md 2>/dev/null | head -30
tmux kill-session -t "$SESS" 2>/dev/null || true
rm -rf "$HOME/.claude/teams/implement" "$HOME/.claude/teams/audit" 2>/dev/null
echo "scratch: $DIR  (session $UUID — resumable if truncated)"
