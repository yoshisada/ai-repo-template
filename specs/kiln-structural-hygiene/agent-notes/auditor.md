# Auditor Friction Notes — kiln-structural-hygiene

**Agent**: auditor (Task #3)
**Date**: 2026-04-23

## What went well

- **Team-lead brief was tight.** Audit checklist enumerated the exact greps (FR-003, SC-001 discoverability, gh bulk-lookup, kiln-cleanup diff) and the four pre-merge gates (SC-002/003/004/008) deferred as DGs in the PR body. I didn't have to re-derive the plan from spec + contracts.
- **Implementer self-assessment was trustworthy and specific.** Commit messages mapped 1:1 to phases (A rubric, B skill, C doctor 3h, D merged-PRD, E SMOKE + discoverability). SC-001/004/005 self-checks matched my re-verification (grep counts, 0.31 s wall-time, 0 destructive hits).
- **Contracts doc earned its keep.** When I spotted `find -printf` → `| sed` drift, contracts §6 was one obvious place to fix; no cascade through skill bodies.

## Friction

### F-1 — Contract/impl drift surfaced by implementer, not a lint

- Implementer flagged the `-printf` → `| sed` switch in their own friction notes and in the team-lead's handoff. Without that, the drift would have been invisible to me at the artifact-grep layer (both forms produce identical dir basenames). Audit gate didn't catch it because there's no lint that asserts "skill body code blocks match contract code blocks verbatim."
- **Proposed v2**: add a cheap sub-check to `/kiln:kiln-doctor` (or a future `/kiln:kiln-contract-lint`) that greps canonical shell snippets from `contracts/interfaces.md` and asserts each one appears in the referenced skill body. Would have caught this at handoff, not at audit.

### F-2 — "Bulk gh call = exactly 1" grep is ambiguous

- The literal grep `grep -c 'gh pr list' plugin-kiln/skills/kiln-hygiene/SKILL.md` returned **3**, not the "1 or 0" the brief predicted. Two of the three hits are a quoted error string (line 208, `NOTES+=("merged-prd-not-archived: gh pr list returned ...")`) and a prose note (line 390, guidance about not fanning out). I had to read each match to confirm only line 185 is an actual invocation.
- **Proposed v2**: tighten the grep to anchor on the `$` prefix or the bare `gh pr list --state merged` command form, e.g. `grep -cE '^\s*(if !|! |gh) pr list --state merged' SKILL.md`. Or: ask implementers to keep the bulk `gh` call behind a shell function with a grep-anchorable name (`fetch_merged_prs()`), and lint for that single fn definition + its single call site.

### F-3 — Staged version-bump files accumulated pre-audit

- When I arrived, the working tree already had 11 modified files staged (VERSION + 5×2 plugin manifests) from auto-increments triggered during implementer edits. These need to ride in the version-bump commit, not a separate chore. It's harmless but initially looked like contamination.
- **Proposed v2**: have the per-phase commit hook sweep pending auto-increments so the tree is clean at hand-off. Not a v1 blocker — noting for rubric polish.

## Decisions I made on the fly

1. **Contract §6 drift — resolved inline, not blocker.** Tiny forward-fix; semantically identical; aligns contract with already-shipped, BSD-portable impl. Logged as R-1 in `blockers.md`.
2. **Kept the non-kiln-structural-hygiene dirty files (.wheel state, .shelf-config, new .kiln/issues/*.md) out of the audit commit.** They're background noise from other pipelines (`/kiln:kiln-report-issue` bg subroutine) and don't belong in this PR.
3. **SC-002/003/004/008 → PR body as `- [ ]` checkboxes.** Per brief. Full recipes live in `specs/kiln-structural-hygiene/SMOKE.md` so the reviewer can copy-paste.

## For the retrospective agent

- The handoff quality from implementer → auditor here was strong. The 3 flagged items in the team-lead's relay (portability fix, fixtures-are-documentary, SC-008-needs-live-checkout) matched what I actually found. No surprises.
- The biggest audit-time loss: re-reading SKILL.md to confirm the `gh pr list` count. ~3 minutes. F-2 above proposes a fix.
- Total wall-time for audit work: ~8 minutes (greps) + ~2 minutes (contract fix) + ~4 minutes (docs writing). Well under the budget that would prompt me to spawn a sub-agent.
