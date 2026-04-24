#!/usr/bin/env bash
# watcher-poll.sh — Capture one poll-tick snapshot of a running test session.
#
# Satisfies: FR-006 poll mechanism
# Contract:  contracts/interfaces.md §7.10
#
# Usage:
#   watcher-poll.sh <scratch-dir> <subprocess-pid> <transcript-path>
#
# Stdout: one-line JSON snapshot:
#   {"alive":<bool>,"exit":<int|null>,"scratch_mtime":<epoch>,
#    "scratch_file_count":<int>,"transcript_bytes":<int>,"transcript_lines":<int>}
# Stderr: diagnostics only.
# Exit:   0 always (unless arg error → 2).
#
# Called by watcher-runner.sh on each poll tick. The runner computes diffs
# between consecutive snapshots to classify (healthy/stalled).
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "watcher-poll.sh: expected 3 args (scratch-dir subprocess-pid transcript-path), got $#" >&2
  exit 2
fi

scratch_dir=$1
subprocess_pid=$2
transcript_path=$3

# Subprocess liveness via /proc or `kill -0`.
alive=false
exit_code=null
if kill -0 "$subprocess_pid" 2>/dev/null; then
  alive=true
fi

# Scratch dir latest-mtime + file count.
scratch_mtime=0
scratch_file_count=0
if [[ -d $scratch_dir ]]; then
  # macOS stat differs from GNU stat. `find -newer` + touch ref is more portable
  # but for mtime alone, use stat with fallback.
  if stat -f '%m' "$scratch_dir" >/dev/null 2>&1; then
    # macOS/BSD stat.
    # We want the max mtime of any file under scratch_dir, not just the dir's own.
    scratch_mtime=$(find "$scratch_dir" -type f -exec stat -f '%m' {} \; 2>/dev/null | sort -nr | head -1)
  else
    # GNU stat.
    scratch_mtime=$(find "$scratch_dir" -type f -exec stat -c '%Y' {} \; 2>/dev/null | sort -nr | head -1)
  fi
  [[ -z $scratch_mtime ]] && scratch_mtime=0
  scratch_file_count=$(find "$scratch_dir" -type f 2>/dev/null | wc -l | tr -d ' ')
fi

# Transcript bytes + line count.
transcript_bytes=0
transcript_lines=0
if [[ -f $transcript_path ]]; then
  if stat -f '%z' "$transcript_path" >/dev/null 2>&1; then
    transcript_bytes=$(stat -f '%z' "$transcript_path")
  else
    transcript_bytes=$(stat -c '%s' "$transcript_path")
  fi
  transcript_lines=$(wc -l < "$transcript_path" | tr -d ' ')
fi

printf '{"alive":%s,"exit":%s,"scratch_mtime":%s,"scratch_file_count":%s,"transcript_bytes":%s,"transcript_lines":%s}\n' \
  "$alive" "$exit_code" "$scratch_mtime" "$scratch_file_count" "$transcript_bytes" "$transcript_lines"
