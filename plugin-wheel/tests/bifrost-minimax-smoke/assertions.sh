#!/usr/bin/env bash
# Bifrost-routed MiniMax smoke — assertions run after claude --print
# exits. Verify the orchestrator (routed via Bifrost to MiniMax) read
# the workflow's agent step, executed it, and wrote the declared
# output file. Content quality is NOT scored — we just want proof of
# round-trip: claude -> Bifrost -> MiniMax -> response -> declared
# output file lands.
set -euo pipefail

OUT=.wheel/outputs/minimax-haiku.md

if [[ ! -f "$OUT" ]]; then
  echo "FAIL: $OUT not created — model never produced the declared output, or wheel didn't dispatch the agent step" >&2
  echo "  scratch contents:" >&2
  ls -la .wheel/outputs/ 2>/dev/null || echo "  (no .wheel/outputs/ dir)" >&2
  exit 1
fi

if [[ ! -s "$OUT" ]]; then
  echo "FAIL: $OUT exists but is empty — model returned no content" >&2
  exit 1
fi

# Sanity: a haiku has 3 lines. Allow some leeway (model may add a
# trailing newline or wrap weirdly) — require ≥3 non-empty lines.
NONEMPTY=$(grep -cE '\S' "$OUT" || true)
if (( NONEMPTY < 3 )); then
  echo "FAIL: $OUT has only $NONEMPTY non-empty lines; haiku needs ≥3" >&2
  cat "$OUT" >&2
  exit 1
fi

echo "PASS: round-trip succeeded — Bifrost-routed MiniMax wrote $NONEMPTY-line artifact"
exit 0
