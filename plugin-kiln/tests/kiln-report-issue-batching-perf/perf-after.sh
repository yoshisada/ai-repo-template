#!/usr/bin/env bash
# AFTER experiment: simulates post-T092 bg sub-agent making 1 Bash tool call.
set -eu
SCRATCH="$1"

# Reset scratch state (identical to BEFORE)
printf 'shelf_full_sync_counter=0\nshelf_full_sync_threshold=10\n' > "$SCRATCH/.shelf-config"
rm -f "$SCRATCH/.kiln/logs/report-issue-bg-"*.md

PROMPT="You are a background reconciliation sub-agent. Run this step and exit. Do not report progress. Do not add commentary. Do not ask questions.

1. Run this exact bash command:
   bash $SCRATCH/step-dispatch-background-sync.sh

2. Exit. Do not do anything else."

cd "$SCRATCH"
START=$(python3 -c 'import time; print(time.time())')
printf '%s' "$PROMPT" | claude --print --dangerously-skip-permissions > /tmp/perf-after-stdout.txt 2>&1
END=$(python3 -c 'import time; print(time.time())')
ELAPSED=$(python3 -c "print(round($END - $START, 3))")
echo "after_elapsed_sec=$ELAPSED"
echo "counter_after=$(grep '^shelf_full_sync_counter=' "$SCRATCH/.shelf-config" | cut -d= -f2)"
LOGFILE=$(ls "$SCRATCH/.kiln/logs/report-issue-bg-"*.md 2>/dev/null | head -1)
if [ -n "$LOGFILE" ]; then
  echo "log_line_count=$(wc -l < "$LOGFILE" | tr -d ' ')"
  echo "log_last_line:"
  tail -1 "$LOGFILE"
else
  echo "log_line_count=0 (NO LOG WRITTEN)"
fi
