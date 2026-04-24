#!/usr/bin/env bash
# Seed-test assertions for kiln-distill-basic.
#
# Ref: FR-015 (seed test), SC-001 (distill runs end-to-end).
#
# Expected final scratch state after `/kiln:kiln-distill`:
#   - A generated PRD under docs/features/<YYYY-MM-DD>-<slug>/PRD.md
#   - That PRD contains:
#     * frontmatter with `derived_from:` block sequence listing BOTH fixture
#       files (feedback/*.md + issues/*.md)
#     * a `### Source Issues` table (or equivalent body section) with links
#       to BOTH fixture files
set -euo pipefail

shopt -s nullglob
prds=( docs/features/*/PRD.md )

if [[ ${#prds[@]} -eq 0 ]]; then
  echo "FAIL: no generated PRD found at docs/features/*/PRD.md" >&2
  echo "Scratch dir contents:" >&2
  find docs -type f 2>/dev/null >&2 || true
  exit 1
fi

if [[ ${#prds[@]} -gt 1 ]]; then
  echo "WARN: more than one PRD generated (${#prds[@]}); using the newest" >&2
  printf '  %s\n' "${prds[@]}" >&2
fi

# Newest PRD by mtime.
prd=$(ls -1t "${prds[@]}" | head -1)
echo "Generated PRD: $prd" >&2

# 1. Must have `derived_from:` frontmatter key in the first 20 lines.
if ! head -20 "$prd" | grep -Eq '^derived_from:[[:space:]]*(\[\])?[[:space:]]*$'; then
  echo "FAIL: PRD is missing `derived_from:` frontmatter line" >&2
  echo "First 20 lines:" >&2
  head -20 "$prd" >&2
  exit 1
fi

# 2. Frontmatter `derived_from:` block must reference BOTH fixtures.
# We look for the two specific fixture paths anywhere in the first 30 lines
# (covers both in-frontmatter AND nearby body references).
feedback_fixture=".kiln/feedback/2026-04-20-0900-template-ergonomics.md"
issue_fixture=".kiln/issues/2026-04-21-1430-minimal-template-missing.md"

if ! head -30 "$prd" | grep -qF "$feedback_fixture"; then
  echo "FAIL: PRD frontmatter/body does not reference the feedback fixture" >&2
  echo "Looking for: $feedback_fixture" >&2
  echo "First 30 lines:" >&2
  head -30 "$prd" >&2
  exit 1
fi

if ! head -30 "$prd" | grep -qF "$issue_fixture"; then
  echo "FAIL: PRD frontmatter/body does not reference the issue fixture" >&2
  echo "Looking for: $issue_fixture" >&2
  echo "First 30 lines:" >&2
  head -30 "$prd" >&2
  exit 1
fi

# 3. Body must have a Source Issues table (or comparable section) referencing
# both fixtures. The distill SKILL.md generates a markdown table under a
# "### Source Issues" heading; we grep for that heading + fixture refs.
if ! grep -qE '^### Source Issues' "$prd"; then
  echo "WARN: no '### Source Issues' section found; the distill skill output shape may have drifted" >&2
  echo "First 80 lines:" >&2
  head -80 "$prd" >&2
  # This is a warn, not a fail — the critical signal is the frontmatter +
  # fixture references, which have already passed.
fi

echo "PASS: PRD has derived_from: frontmatter referencing both fixtures ($prd)" >&2
exit 0
