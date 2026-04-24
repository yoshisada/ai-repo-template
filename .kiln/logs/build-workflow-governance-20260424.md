# Pipeline Report: build/workflow-governance-20260424

| Step | Status | Details |
|------|--------|---------|
| Specify | Done | 13 FRs, 5 NFRs, 4 user stories, 6 success criteria, 8 clarifications |
| Plan | Done | 5 phases, 2 implementer tracks; pi-hash algorithm spec'd in Clarification 7 |
| Research | Skipped | No external dependencies |
| Tasks | Done | 43 tasks, parallelization across impl-governance + impl-pi-apply |
| Commit | Done | spec/plan/contracts/tasks committed in ea0320b |
| Implementation | Done (with anomaly) | Both implementers completed; commit a340652 had attribution sweep — impl-governance's `git add -A` pulled in impl-pi-apply's staged work; corrected by adf5a24 |
| Visual QA | Skipped | Plugin source repo, no visual surface |
| Audit | Pass (replacement) | Original auditor stalled 8h with zero output; replaced by auditor-2 which completed in one turn — 100% compliance (13/13 FRs, 5/5 NFRs, 6/6 SCs); 4/4 smoke scenarios PASS; zero blockers |
| PR | Created | https://github.com/yoshisada/ai-repo-template/pull/159 |
| Retrospective | Done | https://github.com/yoshisada/ai-repo-template/issues/160 |
| Continuance | Skipped | User to invoke /kiln:kiln-next manually |

**Branch**: build/workflow-governance-20260424 (from main)
**PR**: https://github.com/yoshisada/ai-repo-template/pull/159
**Retrospective**: https://github.com/yoshisada/ai-repo-template/issues/160
**Compliance**: 100% per auditor-2
**Blockers**: 0
**Smoke Test**: PASS (a/b/c/d all green)

## Pipeline incidents

### 1. Git-add-all sweep (HIGH severity, captured in retro)
Commit `a340652` has a misleading docs-flavored message ("complementary /plan enum-check follow-on") but its payload is 15 files belonging to impl-pi-apply (skill + 6 helper scripts + test fixtures + kiln-next FR-013 integration). Root cause: impl-governance ran `git add -A && git commit` while impl-pi-apply had work staged in the shared working tree. Work is preserved in git history; attribution is wrong. Retro proposed banning `git add -A` / `git add .` in implementer prompts when running parallel.

### 2. Original auditor 8-hour stall (HIGH severity, captured in retro)
The first `auditor` agent went idle ~8 hours after impl-pi-apply finished, producing zero artifacts and ignoring two team-lead check-ins. Replaced with `auditor-2`, which completed the entire audit + smoke + PR in a single turn. Retro proposed (a) shrinking the stall-detection window from 10 min to 5 min and (b) eliminating the `/audit` skill + bespoke procedure overlay in the auditor prompt as a likely contributor.

### 3. PRD self-referential grandfathering (MEDIUM severity, captured in retro)
The PRD bundled `.kiln/issues/2026-04-24-prd-requires-roadmap-item-source.md` directly — but that issue argues against bundling raw issues directly. Two of the three source issues (FR-001/FR-002) describe already-shipped work (commit `86e3585`), making ~23% of the PRD's FRs no-ops. Retro proposed adding a "source-issue freshness" check to `/kiln:kiln-distill` that detects already-shipped work at bundle time.

## Commit log
```
7bfe284 docs(workflow-governance): retrospective friction note
5a32220 docs(workflow-governance): audit report + reconciled blockers
adf5a24 docs(workflow-governance): Phase 4 landing provenance (FR-009..FR-013)
a340652 docs(workflow-governance): complementary /plan enum-check follow-on  ← payload mismatch
d6856e6 docs(workflow-governance): CLAUDE.md recent changes + command list
e8f86c9 feat(workflow-governance): distill gate refuses un-promoted sources (FR-004/005/007/008)
a95cdef docs(workflow-governance): add contract-drift addendum to specifier friction note
00609b6 feat(workflow-governance): /kiln:kiln-roadmap --promote path (FR-006)
62188dc test(workflow-governance): add require-feature-branch-build-prefix fixture (FR-003)
ea0320b docs(workflow-governance): spec + plan + contracts + tasks (specifier pass)
```

## Team roster
- specifier — 1 task, completed cleanly
- impl-governance — 1 task, completed (attribution sweep noted)
- impl-pi-apply — 1 task, completed (staged work absorbed by sibling, self-corrected with adf5a24)
- auditor — 1 task, **stalled** (replaced)
- auditor-2 — replacement, completed in single turn
- retrospective — 1 task, completed (9 prompt-rewrite proposals filed in #160)
