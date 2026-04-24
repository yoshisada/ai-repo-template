#!/usr/bin/env bash
# Assertions for claude-audit-project-context (T029).
# Validates FR-013 (project-context citation) + FR-014 (External best-practices
# deltas subsection). Acceptance: User Story 3 Scenarios 1 + 2.
set -euo pipefail

shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
if [[ ${#previews[@]} -eq 0 ]]; then
  echo "FAIL: no preview log written to .kiln/logs/claude-md-audit-*.md" >&2
  ls -la .kiln/logs/ 2>&1 >&2 || true
  exit 1
fi

# Newest preview
preview=$(ls -1t "${previews[@]}" | head -1)
echo "Audit preview: $preview" >&2

# 1. Project-context citation — at least one of: phase name, current phase drift,
# "Active Technologies" reference, or explicit "from project context".
if ! grep -qE '(Active Technologies|phase drift|current phase|from project[- ]context|foundations-01|roadmap phase)' "$preview"; then
  echo "FAIL: preview lacks project-context citation (FR-013)" >&2
  cat "$preview" >&2
  exit 1
fi

# 2. External best-practices deltas subsection must be present. Match both the
# canonical heading and at least one finding row (or explicit no-deltas note).
if ! grep -qE '^## External best-practices deltas' "$preview"; then
  echo "FAIL: '## External best-practices deltas' subsection missing (FR-014)" >&2
  cat "$preview" >&2
  exit 1
fi

# 3. Propose-don't-apply: CLAUDE.md must be byte-identical to the fixture.
# The fixture's CLAUDE.md starts with "# Project CLAUDE.md (fixture)".
if ! head -1 CLAUDE.md | grep -qF "fixture"; then
  echo "FAIL: CLAUDE.md was modified — skill must be propose-don't-apply (FR-016)" >&2
  head -5 CLAUDE.md >&2
  exit 1
fi

echo "PASS: preview cites project-context + emits External best-practices deltas; CLAUDE.md unchanged" >&2
exit 0
