# PRD Audit Blockers — kiln-structural-hygiene

**Audit date**: 2026-04-23
**Auditor**: auditor (Task #3)
**Compliance summary**: PRD→Spec 100% (8/8 FRs, 4/4 NFRs traced). Spec→Code: all 8 FRs implemented + 4 NFRs enforceable. Spec→Test: fixtures documentary (shell-runnable assertions, not `tests/harness.sh`) — matches `/kiln:kiln-claude-audit` precedent. Net: **100% PRD coverage, 0 open blockers, 4 pre-merge gates (smoke) deferred to PR body**.

## Resolved inline (this audit)

### R-1 — Contract §6 / impl drift: `find -printf` → BSD-portable `| sed`

- **Source of drift**: Contract §6 specified GNU-only `find ... -printf '%f\n'`; implementer switched both `plugin-kiln/skills/kiln-hygiene/SKILL.md` (line 135) and `plugin-kiln/skills/kiln-doctor/SKILL.md` (line 268) to `find ... | sed 's:^\./::'` during Phase C to unblock macOS (BSD `find` has no `-printf`).
- **Constitution Article VII**: "interface contracts are the single source of truth — update the contract, not the code."
- **Resolution**: Contract §6 updated to the BSD-portable form (this audit). Semantics unchanged — both produce top-level directory basenames without the `./` prefix. Tiny forward-fix rather than a follow-on blocker.

## Open blockers

None.

## Pre-merge gates (deferred to PR body — require live env)

These four SCs are not runnable from inside an agent session because they need live `gh` auth, historical git checkouts, or wall-clock timing in the reviewer's shell. Full recipes in `specs/kiln-structural-hygiene/SMOKE.md`.

- **DG-1 (SC-002)**: 3-item fixture (2 merged PRs + 1 control) → preview flags exactly the 2.
- **DG-2 (SC-003)**: `PATH=` stub gh → every `merged-prd-not-archived` row marked `inconclusive`, exit 0, Notes line present.
- **DG-3 (SC-004)**: `/usr/bin/time -p` on isolated 3h block → <2 s. Implementer's self-measure: 0.31 s (5.3× under budget).
- **DG-4 (SC-008)**: `git checkout 574f220^` → audit flags all 18 items from `.kiln/issues/2026-04-23-stale-prd-created-issues-not-archived.md`.

## Implementer self-assessments already confirmed

- **SC-001** ✅ rubric exists, 3 required rules present, 28 external references grep from non-skill locations (CLAUDE.md + specs/ + docs/ + .kiln/).
- **SC-005** ✅ grep gate passes (0 hits for destructive ops on .kiln/issues|feedback from kiln-hygiene + kiln-doctor SKILL bodies).
- **SC-007** ✅ `git diff main -- plugin-kiln/skills/kiln-cleanup/` returns zero-byte diff; kiln-cleanup untouched.
- **gh bulk-lookup** ✅ exactly 1 `gh pr list` invocation in skill body (line 185); 2 other hits are a quoted error string + prose note.

## v2 follow-on gaps (not blockers)

- **Executable fixture harness**: fixtures are documentary (README.md + shell-runnable assertions). Matches `/kiln:kiln-claude-audit`'s precedent — no `tests/harness.sh`. Tracked as a v2 rubric gap.
- **Per-item cherry-pick for merged-PRD block**: Decision 4 locks strict bundle-accept for v1. v2 may add `--except <file>` based on usage data.
