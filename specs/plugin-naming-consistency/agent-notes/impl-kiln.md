# Agent Friction Notes: impl-kiln

**Feature**: plugin-naming-consistency
**Phase**: K (kiln plugin renames)

## What Was Confusing

- The plan.md said "helper scripts under plugin-kiln/scripts/fix-debug-diagnose.sh and fix-debug-fix.sh", implying `.sh` files. The old `/debug-diagnose` and `/debug-fix` skills are actually instructional Markdown (not executable bash), so `.sh` was the wrong extension. I placed them as `plugin-kiln/scripts/debug/diagnose.md` and `fix.md` instead — the content is a procedure for an agent to follow, not something to exec. Consider updating plan.md for future rename refactors.
- The contract table (Table 2) lists `shelf:shelf-full-sync` → `shelf:sync`. Two kiln workflow files (now `report-issue.json` and `mistake.json`) contained `"workflow": "shelf:shelf-full-sync"` sub-workflow references. I updated those per the "whichever phase owns the file" rule. The task text didn't call these out explicitly — only the `"name"` field change was mentioned.
- The `next/SKILL.md` block-list had `/debug-diagnose` and `/debug-fix` plus `/create-repo` in the whitelist. I dropped the two debug entries from blocked + replacement-rules entirely (since no skills map there anymore) and changed `/create-repo` → `/clay:create-repo` in the whitelist (still a valid cross-plugin command). The task said "remove any `create-repo` references (FR-001)" which was ambiguous — should the whitelist entry be removed (blocking a still-valid command) or redirected? I chose redirect to `clay:create-repo` to preserve the cold-start recommendation.

## Where I Got Stuck

- The version-increment hook auto-bumped `plugin-kiln/.claude-plugin/plugin.json` version mid-edit (from `...064` → `...065`). Expected per the plan's technical-risks section but surprising to see the plugin manifest itself changing version during this PR.

## What Hooks Fired

- `version-increment.sh` (PreToolUse, Edit/Write): fired on every edit as expected. Bumped VERSION's 4th segment multiple times during Phase K.
- `require-spec.sh`: did NOT fire — no edits to `src/`, only `plugin-kiln/` and `specs/` paths.
- `block-env-commit.sh`: did NOT fire.

## What Cross-Refs Were Hardest to Find

- `shelf:shelf-full-sync` embedded as a raw string inside a JSON `instruction` prose field (mistake.json's large agent instruction contained it). `Grep` found it but a pure JSON-schema walker wouldn't — the string lives inside user-facing prose, not a structural field. Flagging because similar landmines may live in other workflows.
- `debug-fix loop` appeared in a fix/SKILL.md sentence describing the loop behavior, not as a literal slash-command. I kept the word "debug loop" but dropped "debug-fix loop" to avoid the skill-name hit. This kind of naming-drift requires reading context, not just grepping.

## What Could Be Improved

- Plan.md should clarify that "helper scripts" in this context may be instructional Markdown, not bash — and mention the pattern `plugin-X/scripts/<feature>/<step>.md` for agent-procedural content versus `plugin-X/scripts/<feature>/<step>.sh` for shell-exec content.
- The rename tables should list cross-workflow sub-workflow references as a distinct column, so implementers know to update `"workflow": "old-name"` inside JSON command-step children at the same time as the file rename. I found it via Grep but the task checklist didn't call it out.
- A checklist item "grep the plugin for the OLD name of OTHER plugins' renamed items" would have saved me one pass — I had to do that grep myself to catch the `shelf-full-sync` internal references.
