#!/usr/bin/env bash
# check-existing-mistakes.sh — list existing mistake artifacts for duplicate detection.
#
# Invoked by plugin-kiln/workflows/report-mistake-and-sync.json step "check-existing-mistakes".
# Output is captured by wheel to .wheel/outputs/check-existing-mistakes.txt and passed as
# context to the next step's agent so it can skip filenames that would collide.
#
# Contract: specs/mistake-capture/contracts/interfaces.md §3.
set -euo pipefail

echo "## Existing Local Mistakes (.kiln/mistakes/)"
if [ -d .kiln/mistakes ]; then
  shopt -s nullglob
  files=(.kiln/mistakes/*.md)
  shopt -u nullglob
  if [ "${#files[@]}" -eq 0 ]; then
    echo "(none)"
  else
    for f in "${files[@]}"; do
      echo "$f"
    done
  fi
else
  echo "(none)"
fi

echo "---"
echo "## Recent Session Mistakes (@manifest/recent-session-mistakes/)"
if [ -d "@manifest/recent-session-mistakes" ]; then
  shopt -s nullglob
  session_files=("@manifest/recent-session-mistakes"/*.md)
  shopt -u nullglob
  if [ "${#session_files[@]}" -eq 0 ]; then
    echo "(none)"
  else
    for f in "${session_files[@]}"; do
      echo "$f"
    done
  fi
else
  echo "(not present)"
fi
