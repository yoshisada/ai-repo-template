---
title: 18 stale prd-created issues never archived after their PRDs merged — build-prd Step 4b lifecycle is broken or incomplete
type: bug
severity: high
category: workflow
status: prd-created
prd: docs/features/2026-04-23-kiln-structural-hygiene/PRD.md
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-kiln/skills/kiln-build-prd/SKILL.md
  - plugin-kiln/skills/kiln-doctor/SKILL.md
  - plugin-kiln/templates/kiln-manifest.json
date: 2026-04-23
---

# 18 stale prd-created issues never archived after their PRDs merged

## Description

`/kiln:kiln-doctor` diagnose pass on 2026-04-23 reported **18 backlog items in `status: prd-created` that were never flipped to `completed` and moved to `.kiln/issues/completed/`**. Every one of them had its PRD built, merged, and shipped — but the lifecycle never closed on the `.kiln/issues/` side.

## The bug

`/kiln:kiln-build-prd` Step 4b (Issue Lifecycle Completion) is supposed to:
1. Scan `.kiln/issues/` for items where `status: prd-created` AND `prd:` field matches the PRD path used for the current build.
2. Flip matching items to `status: completed`, add `completed_date`, `pr: #N`.
3. Move them to `.kiln/issues/completed/`.
4. Commit the archival.

For a substantial run of recent pipelines this step either never executed or silently matched zero issues. 18 leaked through.

## The 18 stale items

Spanning 2026-04-02 through 2026-04-23, with `prd:` pointing at PRDs that are already on main:

- 2026-04-02-lobster-workflow-engine-plugin.md
- 2026-04-02-ux-evaluator-nested-screenshot-dir.md
- 2026-04-03-shelf-note-templates.md
- 2026-04-03-shelf-notes-backlinks-tags.md
- 2026-04-03-shelf-sync-close-archived-issues.md
- 2026-04-03-shelf-sync-docs.md
- 2026-04-03-shelf-sync-update-tech-tags.md
- 2026-04-04-add-todo-skill.md
- 2026-04-04-wheel-branch-subroutine-support.md
- 2026-04-04-wheel-cleanup-in-hook.md
- 2026-04-04-wheel-list-skill.md
- 2026-04-04-wheel-skill-activation.md
- 2026-04-07-qa-engineer-test-dedup-efficiency.md
- 2026-04-21-add-feedback-tool-and-rename-issue-to-prd.md
- 2026-04-21-fix-skill-should-prompt-next-step.md
- 2026-04-21-kiln-fix-drop-wheel-plugin-from-recording.md
- 2026-04-21-kiln-fix-step7-recorder-stall-teams.md
- 2026-04-23-claude-md-audit-and-prune.md

## Why the doctor won't catch this

`/kiln:kiln-doctor --cleanup`'s archival rule (from `plugin-kiln/templates/kiln-manifest.json`'s `archive_completed: true`) only matches `status: closed|done`. It deliberately does NOT match `status: prd-created`, because prd-created means "bundled into a PRD, work not yet verified complete." Doctor correctly refuses to archive a prd-created issue on its own authority.

Result: a prd-created issue that genuinely IS completed (its PRD merged, verified green) is trapped. No skill flips it to completed; doctor won't archive it.

## Impact

- Next `/kiln:kiln-distill` run finds 18 "open-ish" items polluting the backlog surface and offers them back as candidates for a new PRD — even though the work is already shipped.
- `/kiln:kiln-next` counts them in its "open work" signal, inflating the apparent backlog.
- The shelf sync (once it runs a full reconciliation) will create or update Obsidian notes for these, polluting the vault dashboard.

## Suggested fix — two-part

### Part A: Root-cause the Step 4b bug

Diagnose WHY Step 4b didn't run or didn't match for these 18 pipelines. Three plausible causes:

1. **Path-matching failure**: Step 4b compares the issue's `prd:` field string against the PRD path string used for the build. If the two strings don't match exactly (trailing slash, absolute vs relative, case, etc.), the match returns empty and the step silently skips all issues.
2. **Step 4b didn't run**: some pipelines may have skipped Step 4b entirely — maybe the team lead (in main chat) never executed it, or the skill body had a conditional that evaluated false.
3. **Pre-rename legacy**: the rename from `/kiln:kiln-issue-to-prd` → `/kiln:kiln-distill` may have broken the `prd:` field format between old and new items. Verify by looking at the 18 files' exact `prd:` strings.

### Part B: Defense in depth — teach doctor to handle this

Give `/kiln:kiln-doctor` (or a new `/kiln:kiln-doctor --archive-merged-prds` subcommand) the ability to:
- Read each `prd-created` item's `prd:` field
- Check if that PRD's feature branch is merged to main (via `gh pr list --state merged` or git log)
- If yes: flip to `status: completed` + `pr: #N` + move to `.kiln/issues/completed/`

This turns the lifecycle-completion step from a single-pipeline responsibility into a general invariant that doctor can enforce. The PRD path → merged-PR resolution is a one-liner via `gh`.

## Immediate one-time cleanup

Independent of the fix: manually flip these 18 to `completed` + archive them, so the backlog surface is clean while the fix is designed. Safe to batch since each PRD IS merged.

## Related

- `.kiln/issues/2026-04-23-claude-md-audit-and-prune.md` is in the list — but its PRD (kiln-self-maintenance, PR #141, merged as ace7972) just landed. So this issue captures the pattern that includes itself.
- Retrospective #142 (kiln-self-maintenance pipeline) flagged "executable skill-test harness" as a top follow-on — an executable harness would have caught Step 4b matching behavior directly.
