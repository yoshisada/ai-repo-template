# Friction Notes — impl-themeA-agents

Owner track: Theme A (FR-A1..FR-A5 + NFR-7).

## Incidents / friction

### Race on `git add` / `git commit` across implementers (T030)
The atomic agent migration (NFR-7, CC-4) was intended to land every rename + every
symlink + the registry seed in **one** commit. What actually happened: another
implementer's `git add -A` (or equivalent broad stage) swept up my `git mv` hunks
alongside their own work, then committed them. Net result: renames landed in their
commit, symlinks + registry landed in mine — **two commits**, briefly half-migrated
on the feature branch.

Consumer impact: zero, because PR-to-main is a squash and the repo state between
the two commits is only visible in feature-branch history. But it violated the
letter of NFR-7 inside the branch.

**What could be improved for future pipelines with parallel implementers**:
1. The pipeline contract needs a rule: *implementers MUST stage only their own
   files by explicit path* — never `git add -A`, `git add .`, or `git add <wide-dir>`.
   The habit in this repo leans toward wide staging; it silently couples commits
   across concurrent workers.
2. Wheel's git-adjacent hooks could optionally lint staged hunks for ownership
   mismatch against the current implementer agent id (if that becomes a first-class
   concept), but that's a bigger pipeline feature.
3. Alternatively, implementers could work in git worktrees — zero risk of
   cross-contamination — at the cost of more coordination overhead.

### Plan.md named archetype agents that don't exist on disk
Plan.md §"Theme A" enumerated 11 canonical agents including `reconciler`,
`writer`, `researcher`, `auditor`. The filesystem only has 10 actual agents, and
none of those archetype names is among them (shipped set: continuance, debugger,
prd-auditor, qa-engineer, qa-reporter, smoke-tester, spec-enforcer, test-runner,
test-watcher, ux-evaluator). Resolution: migrated what's on disk; documented the
discrepancy in T030's note. If the archetypes are actually desired, that's a
follow-on PRD.

## In-flight status
- Phase 1+2.A complete (T001/T002/T003/T010/T011/T012).
- Phase 3 T030 complete (atomic migration, with the split-commit friction above).
- T031 (resolver), T032 (dispatch), T033 (kiln-fix integration), Phase 3 tests next.
