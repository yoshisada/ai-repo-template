#!/usr/bin/env bash
# BEFORE experiment: simulates pre-T092 bg sub-agent making 2 Bash tool calls.
set -eu
SCRATCH="$1"

# Reset scratch state
printf 'shelf_full_sync_counter=0\nshelf_full_sync_threshold=10\n' > "$SCRATCH/.shelf-config"
rm -f "$SCRATCH/.kiln/logs/report-issue-bg-"*.md

PROMPT="You are a background reconciliation sub-agent. Run these steps in order and exit. Do not report progress. Do not add commentary. Do not ask questions.

1. Run this exact bash command and capture stdout:
   bash $SCRATCH/shelf-counter.sh increment-and-decide
   The output is a JSON object: {\"before\":N,\"after\":N,\"threshold\":N,\"action\":\"increment|full-sync\"}.

2. Parse the JSON into variables BEFORE, AFTER, THRESHOLD, ACTION.

3. Run this exact bash command, substituting the parsed values:
   bash $SCRATCH/append-bg-log.sh \"\$BEFORE\" \"\$AFTER\" \"\$THRESHOLD\" \"\$ACTION\" \"\"

4. Exit. Do not do anything else."

cd "$SCRATCH"
START=$(python3 -c 'import time; print(time.time())')
JSON=$(printf '%s' "$PROMPT" | claude --print --output-format=json --dangerously-skip-permissions 2>/dev/null || echo '{}')
END=$(python3 -c 'import time; print(time.time())')
ELAPSED=$(python3 -c "print(round($END - $START, 3))")
printf '%s' "$JSON" > /tmp/perf-before-result.json
python3 -c "
import json, sys
j = json.loads(open('/tmp/perf-before-result.json').read() or '{}')
u = j.get('usage', {}) or {}
print(f\"before_elapsed_sec=$ELAPSED\")
print(f\"duration_ms={j.get('duration_ms', 'NA')}\")
print(f\"duration_api_ms={j.get('duration_api_ms', 'NA')}\")
print(f\"num_turns={j.get('num_turns', 'NA')}\")
print(f\"input_tokens={u.get('input_tokens', 'NA')}\")
print(f\"output_tokens={u.get('output_tokens', 'NA')}\")
print(f\"cache_read_input_tokens={u.get('cache_read_input_tokens', 'NA')}\")
print(f\"cache_creation_input_tokens={u.get('cache_creation_input_tokens', 'NA')}\")
print(f\"total_cost_usd={j.get('total_cost_usd', 'NA')}\")
print(f\"stop_reason={j.get('stop_reason', 'NA')}\")
"
LOGFILE=$(ls "$SCRATCH/.kiln/logs/report-issue-bg-"*.md 2>/dev/null | head -1)
if [ -n "$LOGFILE" ]; then
  echo "log_line_count=$(wc -l < "$LOGFILE" | tr -d ' ')"
else
  echo "log_line_count=0"
fi
