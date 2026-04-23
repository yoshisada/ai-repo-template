# Auditor friction notes — kiln-capture-fix-polish

## What went well

- The three SC grep gates (SC-001 / SC-003 / SC-006) are well-designed machine-checkable contracts. Running them was a 10-second confidence gate before even opening the code.
- `SMOKE.md` as a separate artifact from `blockers.md` is clean — it documents the procedures I can't execute (live `/kiln:*` invocation) without polluting the compliance report.
- `tasks.md` 100% `[X]` at audit time, disjoint file ownership between the two implementers, zero merge conflicts — the Track 1 / Track 2 split in `plan.md` worked as designed.

## Friction / surprises

1. **Task-brief ambiguity on which fix-recording helpers must be preserved.** The auditor brief listed 9 helpers under "Must still contain", but three of them (`validate-reflect-output.sh`, `check-manifest-target-exists.sh`, `derive-proposal-slug.sh`) never existed in `plugin-kiln/scripts/fix-recording/` — they're shelf-side scripts. The team-lead's heads-up flagged this in advance, which saved me chasing phantoms. Recommendation for future runs: when the specifier writes FR-004's "preserve" list, verify each file exists via `ls` before putting it in the brief.

2. **Orphan tests from FR-002.** FR-002 said "delete `render-team-brief.sh`" but not "delete the tests that import it". Result: `run-all.sh` had 3 stale failures (2 directly for the removed helper, 1 portability test pointing to the old `plugin-kiln/skills/fix/` pre-rename path). I fixed it at audit time by deleting all three. Recommendation: when a spec says "delete helper X", the specifier should add a corollary task "and any `__tests__/test-*-X.sh`", or the implementer should grep `__tests__/` for the helper name before marking the delete task complete.

3. **SC-006 historical-vs-live ambiguity around the feature's own PRD.** The raw `grep -rn 'kiln-issue-to-prd' plugin-*/ CLAUDE.md docs/` returned 4 hits, all in `docs/features/2026-04-22-kiln-capture-fix-polish/PRD.md` (this feature's own PRD describing the rename it performs). The brief's exclusion pattern didn't explicitly cover this. I judged them as self-describing historical (the PRD is permanent provenance for the rename), consistent with SC-006's own language "retrospective notes, prior-feature spec bodies". Recommendation: future SC-006-style gates should either include the feature's own PRD in the exclusion pattern or call out explicitly that the originating PRD counts as historical.

## Token / time cost

Audit phase: ~18 min wall time including the `/kiln:audit` skill load, the three grep gates, the test-fix, the version bump, and the PR draft. No wasted cycles chasing phantoms thanks to the team-lead's heads-up.
