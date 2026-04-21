# impl-clay — friction notes

## Summary
Phase C executed cleanly. All 5 task blocks (C1–C5) complete in one commit.

## Renames performed
- `plugin-clay/skills/create-prd/` → `plugin-clay/skills/new-product/` (FR-002) — frontmatter `name` + description updated. Title heading changed from "Create PRD" to "New Product — Create a PRD".
- `plugin-clay/skills/clay-list/` → `plugin-clay/skills/list/` (FR-005) — frontmatter `name` updated.
- `plugin-clay/workflows/clay-sync.json` → `plugin-clay/workflows/sync.json` (FR-006) — `name` field + two `.wheel/outputs/*` paths updated (`clay-sync-products.md` → `sync-products.md`, `clay-sync-research.md` → `sync-research.md`). Two in-instruction "*Synced by clay-sync workflow*" footer strings updated to "*Synced by clay:sync workflow*".
- `plugin-clay/.claude-plugin/plugin.json` workflows array updated.

## Cross-ref updates (FR-007)
- `skills/create-repo/SKILL.md` — 5 hits updated: description `/create-prd` → `/clay:new-product`; step 1 PRD fallback; step 7.5 `/clay:clay-list` → `/clay:list`; step 8 `/clay-list` → `/clay:list` and `clay-sync` → `clay:sync`; step 9 next steps `/create-prd` → `/clay:new-product` and `/build-prd` → `/kiln:build-prd`.
- `skills/idea/SKILL.md` — all `/create-prd` → `/clay:new-product` (replace_all), `/idea-research` → `/clay:idea-research`, `/project-naming` → `/clay:project-naming`, `/build-prd` → `/kiln:build-prd`.
- `skills/list/SKILL.md` — FR-036 comment updated; `named` next-action updated to `/clay:new-product`; `repo-created` next-action updated to `/kiln:build-prd`.
- `skills/new-product/SKILL.md` — next-step prose (mode A/B/C) updated with plugin-prefixed slash commands.
- `skills/idea-research/SKILL.md` and `skills/project-naming/SKILL.md` — verified zero hits for `create-prd`, `clay-list`, `clay-sync`.

## clay-sync resolution
Contract decision (interfaces.md open-question #1) was "rename workflow to `plugin-clay/workflows/sync.json`, do NOT create an owning skill — invocation via `wheel:run clay:sync`." Executed as specified. No new skill created.

## Friction / gotchas
- `git mv` invalidates Edit's read-cache: tool required a fresh `Read` at the new path before Edit would accept it. Worth noting in future implementers' mental model — re-read any file after moving it.
- `plugin-clay/.claude-plugin/plugin.json` was auto-edited multiple times by the version-increment hook between the `Read` and `Edit`, producing a "file has been modified since read" error. Had to re-read twice before Edit succeeded. Not a correctness issue — just needed retries.
- `plugin-clay/package.json` was also auto-bumped by the version hook; I did not touch it but it's staged. Leaving in the commit since it's a byproduct of the hook running over the plugin edits.

## Verification
- `grep -r "create-prd\|clay-list\|clay-sync" plugin-clay/` — 0 hits post-edit.
- `grep -r "/build-prd\|/create-prd\|/clay-list\|/clay-sync" plugin-clay/` — 0 hits post-edit.
- All cross-plugin references within `plugin-clay/` updated to plugin-prefixed form (`clay:`, `kiln:`).
