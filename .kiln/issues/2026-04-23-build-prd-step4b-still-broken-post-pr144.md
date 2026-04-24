---
title: /kiln:kiln-build-prd Step 4b still broken after PR #144 — two more pipelines leaked prd-created items
type: bug
severity: high
category: workflow
status: prd-created
prd: docs/features/2026-04-23-pipeline-input-completeness/PRD.md
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-kiln/skills/kiln-build-prd/SKILL.md
  - plugin-kiln/rubrics/structural-hygiene.md
date: 2026-04-23
---

# /kiln:kiln-build-prd Step 4b still broken after PR #144 — two more pipelines leaked prd-created items

## Description

The `/kiln:kiln-hygiene` audit (shipped in PR #144) just caught **4 more leaked items** from the two pipelines that merged today (#141 kiln-self-maintenance and #144 kiln-structural-hygiene). Both pipelines ran Step 4b, both silently matched zero issues, both left their backlog/feedback items in `status: prd-created`.

This is the same class of bug as the already-archived `2026-04-23-stale-prd-created-issues-not-archived.md` (which flagged 18 historical leaks). The hygiene audit is doing its job as a safety net — but the underlying Step 4b bug is still live. The prior issue's Part B (external safety net) shipped; Part A (root-cause Step 4b) remains open, and the evidence now says "every build-prd run leaks items."

## Evidence

Items just flagged by `/kiln:kiln-hygiene` and manually archived as a one-off:

| File | PRD | Merged PR |
|---|---|---|
| `.kiln/feedback/2026-04-23-claude-md-should-be-refreshed-audited.md` | `docs/features/2026-04-23-kiln-self-maintenance/PRD.md` | #141 |
| `.kiln/feedback/2026-04-23-feedback-should-interview-me-about.md` | `docs/features/2026-04-23-kiln-self-maintenance/PRD.md` | #141 |
| `.kiln/feedback/2026-04-23-i-think-we-need-to.md` | `docs/features/2026-04-23-kiln-structural-hygiene/PRD.md` | #144 |
| `.kiln/issues/2026-04-23-stale-prd-created-issues-not-archived.md` | `docs/features/2026-04-23-kiln-structural-hygiene/PRD.md` | #144 |

All 4 have a valid `prd:` field pointing at a real PRD file. All 4 PRDs merged to main. Step 4b should have caught all 4. It caught none.

## Reproduction

Every `/kiln:kiln-build-prd` run. 100% repro.

## Expected

Step 4b runs after the audit-pr agent creates the PR and before the retrospective. For every `.kiln/issues/*.md` or `.kiln/feedback/*.md` whose `status` is `prd-created` AND whose `prd:` field matches `$PRD_PATH` for the current build:
- Flip `status: prd-created` → `status: completed`
- Add `completed_date: YYYY-MM-DD` and `pr: #N`
- Move the file to `.kiln/{issues,feedback}/completed/`
- Commit the lifecycle update before proceeding to retrospective

## Actual

Files remain at `status: prd-created`. No commit from Step 4b appears in the branch history. The hygiene audit catches the drift post-merge via the `merged-prd-not-archived` rule.

## Suggested fix vectors (from prior issue's Part A + new evidence)

1. **Add a logging/diagnostic step to Step 4b.** The step currently runs silently. Emit the matched count and the non-matches so we can SEE why matching fails. Today it's a black box.
2. **Path-string normalization.** Compare the issue's `prd:` field text against the `$PRD_PATH` variable Step 4b uses. Likely mismatch on: trailing slash, absolute-vs-relative, leading `./`, case, or `docs/features/` vs `products/` path shape. The clay-ideation-polish feature uses `docs/features/2026-04-22-clay-ideation-polish/PRD.md` while some earlier items may have pointed at different shapes. Must normalize both sides before comparing.
3. **Feedback-side scan missing?** Step 4b's current pseudocode only scans `.kiln/issues/*.md`. But feedback items can also be `prd-created` (and 3 of today's 4 leaked items ARE in `.kiln/feedback/`). If Step 4b isn't even looking at `.kiln/feedback/`, that alone explains the 3 feedback misses. The 4th (issue-side) miss would then be a separate path-match bug.
4. **Smoke test for Step 4b.** Stand up a fixture: 2 issues + 2 feedback items with valid `prd:` fields, invoke the step in isolation, assert all 4 flip. Add to kiln-build-prd's CI/smoke checklist.

## Related

- `2026-04-23-stale-prd-created-issues-not-archived.md` (now archived as completed) — Part B (external safety net) shipped as #144; Part A (root-cause) is this issue's focus.
- The hygiene audit's `merged-prd-not-archived` rule (in PR #144's rubric) is the safety net — this is not a replacement for it, but the upstream fix that would let the safety net fire zero times per pipeline.

## Priority

High. Two pipelines in one day both leaked — the upstream bug is routine, not incidental. Fixing Step 4b means future pipelines self-heal; leaving it broken means every pipeline accumulates 1–4 stale items and the maintainer runs hygiene + manual archive every week.
