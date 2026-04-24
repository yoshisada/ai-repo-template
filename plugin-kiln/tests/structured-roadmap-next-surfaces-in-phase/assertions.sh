#!/usr/bin/env bash
# T055 — kiln-next renders "Active phase items" section when in-phase items exist.
# FR-033 / contract §8.

set -euo pipefail

# The harness captures skill output into the scratch dir. Prefer the explicit
# logs/next-output.md the initial-message asked for; fall back to any
# .kiln/logs/next-*.md or the harness transcript.
output=""
if [[ -f ".kiln/logs/next-output.md" ]]; then
  output=$(cat .kiln/logs/next-output.md)
elif compgen -G ".kiln/logs/next-*.md" >/dev/null; then
  output=$(cat .kiln/logs/next-*.md)
fi

# Fallback: search all transcripts / markdown files in the scratch dir.
if [[ -z "$output" ]]; then
  output=$(find . -maxdepth 4 -type f \( -name '*.md' -o -name '*.txt' -o -name 'transcript*' \) \
            -exec grep -l -i 'Active phase items' {} + 2>/dev/null | head -1 | xargs -I{} cat "{}" 2>/dev/null || true)
fi

if [[ -z "$output" ]]; then
  echo "FAIL: no kiln-next output captured in scratch dir" >&2
  find . -maxdepth 3 -type f 2>/dev/null >&2 || true
  exit 1
fi

if ! grep -qi 'Active phase items' <<<"$output"; then
  echo "FAIL: kiln-next output missing 'Active phase items' section" >&2
  printf '%s\n' "$output" | head -80 >&2
  exit 1
fi

if ! grep -qF "2026-04-23-planning-surface" <<<"$output"; then
  echo "FAIL: 'Active phase items' section missing the in-phase item id" >&2
  printf '%s\n' "$output" | head -80 >&2
  exit 1
fi

echo "PASS: kiln-next surfaced the in-phase item" >&2
exit 0
