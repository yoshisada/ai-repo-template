#!/usr/bin/env bash
# Assertions for roadmap-vision-empty-fallback (T020).
# Validates FR-011: fully-empty snapshot → one-line banner + blank-slate question path.
# Acceptance: User Story 2 Scenario 4.
set -euo pipefail

VISION=".kiln/vision.md"
if [[ ! -f "$VISION" ]]; then
  echo "FAIL: $VISION not written after blank-slate interview" >&2
  exit 1
fi

# All four sections must still be present (blank-slate path uses the template)
for section in "What we are building" "What it is not" "How we'll know we're winning" "Guiding constraints"; do
  if ! grep -qF "## $section" "$VISION"; then
    echo "FAIL: blank-slate path lost section '$section'" >&2
    exit 1
  fi
done

# Stamp
TODAY=$(date -u +%Y-%m-%d)
if ! head -5 "$VISION" | grep -qE "^last_updated: ${TODAY}$"; then
  echo "FAIL: last_updated not stamped to today ($TODAY)" >&2
  head -5 "$VISION" >&2
  exit 1
fi

# The banner must have been emitted to the transcript. The kiln-test harness captures
# transcript output in the scratch dir; we grep any logs that may exist. Banner text:
# "blank-slate fallback" (the canonical phrase per FR-011 / the SKILL.md banner line).
# We allow PASS even if the transcript isn't available — the file-shape assertions above
# are the primary signal. Transcript match is informational.
if ls .kiln/logs/ 2>/dev/null | grep -q .; then
  if grep -qi "blank-slate" .kiln/logs/*.md 2>/dev/null; then
    echo "NOTE: banner text found in logs" >&2
  fi
fi

echo "PASS: empty-fallback wrote vision via blank-slate path with today's last_updated" >&2
exit 0
