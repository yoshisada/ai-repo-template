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
printf '%s' "$PROMPT" | claude --print --dangerously-skip-permissions > /tmp/perf-before-stdout.txt 2>&1
END=$(python3 -c 'import time; print(time.time())')
ELAPSED=$(python3 -c "print(round($END - $START, 3))")
echo "before_elapsed_sec=$ELAPSED"
echo "counter_after=$(grep '^shelf_full_sync_counter=' "$SCRATCH/.shelf-config" | cut -d= -f2)"
LOGFILE=$(ls "$SCRATCH/.kiln/logs/report-issue-bg-"*.md 2>/dev/null | head -1)
if [ -n "$LOGFILE" ]; then
  echo "log_line_count=$(wc -l < "$LOGFILE" | tr -d ' ')"
  echo "log_last_line:"
  tail -1 "$LOGFILE"
else
  echo "log_line_count=0 (NO LOG WRITTEN)"
fi
