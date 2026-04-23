# Retrospective friction notes — kiln-capture-fix-polish

**Agent**: retrospective
**Task**: #5
**Date**: 2026-04-22
**PR**: https://github.com/yoshisada/ai-repo-template/pull/135

## Synthesis across four agent-notes

Read: specifier.md, impl-fix-polish.md, impl-feedback-distill.md, auditor.md.

### What worked (cross-cutting)

- **3-decision lock pattern**: specifier and both implementers all independently note that pinning reflect-gate mechanics, skill name, and feedback schema in plan.md before unblocking implementers removed mid-flight judgment calls. Decision 2 (`kiln-distill`) in particular was a "free pick" after `grep -rn distill` confirmed zero collisions — the specifier invested one-shot verification cost so the renamer didn't have to.
- **Parallel-by-area partition**: plan.md's file ownership table predicted the no-overlap split (impl-fix-polish → `kiln-fix/`; impl-feedback-distill → `kiln-feedback/` + `kiln-distill/` + cross-refs). Both implementers confirmed zero merge conflicts on code files. The only shared-write file was `tasks.md` (one transient `File has been modified` race, recovered via re-read).
- **Deterministic grep gates**: auditor called SC-001 / SC-003 / SC-006 "a 10-second confidence gate before even opening the code." Machine-checkable success criteria > prose judgment at audit time.
- **git mv preserved history** on the `kiln-issue-to-prd → kiln-distill` rename (commit `57d9b6f`) — the hard-cutover policy held.
- **Phase F idle-handoff**: impl-fix-polish absorbed T022 (Phase F SMOKE.md) without SendMessage coordination after noticing impl-feedback-distill was idle post-Phase-E. The specifier flagged this coordination seam in advance; it resolved itself.

### What was painful (cross-cutting)

- **Task-brief phantom helpers (task #4 auditor)**: the auditor brief listed 9 fix-recording helpers as "must still exist", but 3 (`validate-reflect-output.sh`, `check-manifest-target-exists.sh`, `derive-proposal-slug.sh`) actually live under `plugin-shelf/scripts/`, not `plugin-kiln/`. impl-fix-polish caught the same mislabel in tasks.md T004 (agent-notes line 5). Root cause: whoever wrote the "must preserve" list inherited it from the team-lead's briefing without running `ls` against the claimed path. One `ls` call in the specifier's FR-004 flow would have prevented two separate agents from having to flag the same drift.
- **Orphan tests after helper deletion (auditor)**: FR-002 deleted `render-team-brief.sh` and `team-briefs/`, but tasks.md didn't require deleting the 3 `__tests__/test-*.sh` files that imported them. `run-all.sh` had 3 failures at audit time. Pattern: any "delete helper X" FR should carry an implicit "and X's test files" corollary.
- **SC-006 self-description trap**: the grep exclusion pattern didn't cover `docs/features/2026-04-22-kiln-capture-fix-polish/PRD.md` — the feature's OWN PRD legitimately contains `kiln-issue-to-prd` as the rename source. Auditor had to judgment-call this as "permanent historical provenance" consistent with SC-006's existing language. Future rename-style SCs should include `docs/features/<this-feature>/` in the exclusion set by default.
- **Breadcrumb policy unstated**: impl-feedback-distill wrote "Renamed from /kiln:kiln-issue-to-prd (Apr 2026)" as a migration note in CLAUDE.md, then stripped it to satisfy the strict SC-006 grep. Plan.md didn't state whether intentional historical breadcrumbs are OK. A hard-rename-policy line would prevent the write-then-strip round-trip.
- **Deferred tool schemas at session start**: impl-feedback-distill had to `ToolSearch select:TaskGet,TaskList,TaskUpdate,SendMessage` before doing anything — undocumented startup cost for any new team member.
- **Noisy working tree at commit time**: background `.wheel/history/*`, `.kiln/logs/*`, `.shelf-config`, `VERSION` churn created broad `git add -A` risk. Both implementers used explicit `git add <paths>` — team brief implicitly required it but never stated it.
- **Step 7 dual-location tracking** (specifier lines 15, 21): the inline fix-note body template HAD to be read from `team-briefs/fix-record.md` BEFORE T004 deleted the briefs dir. Specifier flagged the ordering risk; impl-fix-polish handled it correctly. Could be codified into tasks.md future ordering rule: "read-before-delete" for any template-port-then-delete pattern.

### Open for follow-on

- **Reflect gate efficacy** (Decision 1): deterministic 3-condition file-path predicate. Only validated by real `/kiln:kiln-fix` usage (DG-1..DG-4 pre-merge). Specifier explicitly accepted the false-negative risk — non-template fixes with no `manifest` keyword in commit msg won't trigger reflection. If smoke reveals consistent misses, follow-up is a separate "judgment upgrade" feature, not a regression.
- **Feedback schema sufficiency** (Decision 3): 7 required + 2 optional frontmatter keys. impl-feedback-distill did NOT report wishing for more or fewer fields. Counts as quiet success — re-evaluate after `/kiln:kiln-distill` has consumed feedback items in anger (DG-4 validates read-path).

## Prompt-rewrite proposals for plugin-kiln/skills/kiln-build-prd/

See GitHub issue for exact Current/Proposed pairs.

## Completion

- GitHub issue filed: (URL below after creation).
- Agent-notes file: this file.
