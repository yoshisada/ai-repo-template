#!/usr/bin/env bash
# Seed-test assertions for kiln-hygiene-backfill-idempotent.
#
# Ref: FR-015 (seed test), SC-002 (idempotence regression test).
#
# CWD = scratch dir (so .kiln/logs/ is the scratch-local logs dir). The skill
# under test (kiln:kiln-hygiene backfill) runs in the same CWD, so it writes
# its backfill preview there.
#
# Test strategy (addresses the subtle idempotence semantics of a propose-don't-
# apply subcommand — see docs/features/.../2026-04-15-legacy-prd/PRD.md in
# fixtures for the full rationale):
#   - Run 1 against the fixtures produces SOME number of hunks (one per legacy
#     PRD). The already-migrated PRD is skipped.
#   - Run 2 is invoked against the SAME file state (no hunks applied).
#     Because idempotence in this subcommand is measured against file state,
#     not applied state, run 2 MUST produce the SAME number of hunks as run 1.
#   - The regression we're guarding against: a future change that causes run 2
#     to produce MORE hunks than run 1 (e.g., non-deterministic table parsing
#     that includes the already-migrated PRD on the second pass).
#
# So this assertion checks: (a) at least two backfill logs exist, (b) the
# hunk count in the newest (run 2) is EQUAL to the hunk count in the
# second-newest (run 1), and (c) the newest log DOES NOT include the
# already-migrated PRD path.
set -euo pipefail

shopt -s nullglob
logs=( .kiln/logs/prd-derived-from-backfill-*.md )

if [[ ${#logs[@]} -lt 2 ]]; then
  echo "FAIL: expected at least 2 backfill logs (run1 + run2), found ${#logs[@]}" >&2
  echo "Logs found:" >&2
  printf '  %s\n' "${logs[@]}" >&2
  exit 1
fi

# Sort by filename (the log filename embeds an ISO-8601 timestamp, so lex
# sort = chronological sort).
IFS=$'\n' sorted=( $(printf '%s\n' "${logs[@]}" | sort) )
unset IFS

run1="${sorted[-2]}"
run2="${sorted[-1]}"

# Count hunks in each run via the `### diff --- ` header pattern (this is
# the exact shape the backfill subcommand writes per SKILL.md §B.2 line 584).
count_hunks() {
  grep -c '^### diff --- ' "$1" 2>/dev/null || echo 0
}

r1=$(count_hunks "$run1")
r2=$(count_hunks "$run2")

echo "run1 log: $run1 — $r1 hunk(s)" >&2
echo "run2 log: $run2 — $r2 hunk(s)" >&2

if [[ "$r1" != "$r2" ]]; then
  echo "FAIL: idempotence broken — run1 emitted $r1 hunks, run2 emitted $r2 hunks (expected equal)" >&2
  exit 1
fi

# Verify the already-migrated PRD is NOT referenced in the newest log.
if grep -q 'docs/features/2026-04-10-migrated-prd/PRD.md' "$run2"; then
  echo "FAIL: run2 log references the already-migrated PRD — idempotence predicate broken" >&2
  grep -n 'docs/features/2026-04-10-migrated-prd/PRD.md' "$run2" >&2
  exit 1
fi

# Also sanity-check: run2 SHOULD reference the legacy PRD (because it has no
# derived_from: frontmatter yet).
if ! grep -q 'docs/features/2026-04-15-legacy-prd/PRD.md' "$run2"; then
  echo "FAIL: run2 log does NOT reference the legacy PRD — unexpected (fixtures set up wrong?)" >&2
  exit 1
fi

# Passing:
echo "PASS: run1=$r1 hunks, run2=$r2 hunks (equal); already-migrated PRD skipped; legacy PRD proposed" >&2
exit 0
