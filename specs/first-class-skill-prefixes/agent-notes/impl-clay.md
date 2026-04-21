# impl-clay friction notes — Phase C

## Summary
Phase C (plugin-clay renames) completed without friction. 6 of 6 first-class skills renamed to `clay-<action>` form. All in-plugin cross-references updated (11 occurrences across 4 SKILL.md files).

## What went smoothly
- Plugin-clay has the smallest surface of any plugin: 6 skills, 1 workflow (`sync.json`), 1 plugin manifest, and no agents/hooks/templates/scripts directories. The blast radius was tiny.
- All `/clay:<name>` cross-references were concentrated in exactly 4 SKILL.md bodies (clay-create-repo, clay-idea, clay-list, clay-new-product). No references lived in `.claude-plugin/plugin.json`, `workflows/sync.json`, or README files.
- `workflows/sync.json` has `"name": "sync"` and no `activate_name`. Since there is no `clay-sync` skill, per C-007 the filename was correctly left as-is. The `clay:sync` string mentioned in `clay-list/SKILL.md:40` (FR-036 comment) refers to the workflow, not a skill, and remains accurate.

## Friction / observations
- **Edit tool requires Read first**: My initial batch of 6 frontmatter edits failed because Edit mandates a prior Read of the file. I had to Read each renamed SKILL.md before editing. Low-cost friction but worth noting — future phases could pre-Read to batch edits more efficiently.
- **`/kiln:build-prd` reference in clay-new-product**: When rewriting `/kiln:build-prd` → `/kiln:kiln-build-prd` in `clay-new-product/SKILL.md:211`, I updated the kiln reference too. This is technically a cross-plugin edit. Per the brief this is within scope since I was editing a file I owned (plugin-clay) and the kiln reference was a first-class command that needed the prefix. Flagging for auditor's Phase X sweep to ensure consistency with how impl-kiln handles kiln-internal references.
- **No agents/hooks/templates/scripts directories**: C-009 was structurally a no-op. The tasks.md assumed those might exist — for plugin-clay they don't. Documented inline.

## Cross-plugin heads-up for auditor
- `/kiln:build-prd` → `/kiln:kiln-build-prd` rewrite lives at `plugin-clay/skills/clay-new-product/SKILL.md:211`. Confirm this aligns with impl-kiln's rename of the kiln-build-prd skill.
- The FR-036 comment at `plugin-clay/skills/clay-list/SKILL.md:40` still says `clay:sync` — this is correct (sync is a workflow, not a skill). No action needed.

## Verification
- `grep -E '/clay:(create-repo|idea|idea-research|list|new-product|project-naming)\b' plugin-clay/` → zero hits
- `grep -E '(/|:)(create-repo|idea-research|new-product|project-naming)\b' plugin-clay/` → zero hits
- All 6 skill directories now named `clay-<action>`
- All 6 SKILL.md frontmatter `name:` fields match their directory

## Commit
`refactor(clay): prefix first-class skills with clay- (FR-001)` — includes note that `workflows/sync.json` filename is intentionally preserved (no corresponding `clay-sync` skill).
