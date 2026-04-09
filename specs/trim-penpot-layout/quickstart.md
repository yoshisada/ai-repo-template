# Quickstart: Trim Penpot Layout & Auto-Flows

## What This Feature Changes

This feature modifies agent instruction text in existing trim workflow JSON files and skill Markdown files. There is no new runtime code, no new files to create, and no new infrastructure.

## Files to Modify

1. **Workflow JSON files** (6 files in `plugin-trim/workflows/`):
   - Modify the `instruction` field of agent steps to include positioning rules
   - Add new `discover-flows` agent steps to push, pull, and design workflows
   - Add Components page instructions to push and design workflows

2. **Skill SKILL.md files** (3 files in `plugin-trim/skills/`):
   - Update report templates to mention Components page and flow discovery

## How to Verify

After making changes, run each trim command on a consumer project and verify:

1. `/trim-push` — Components appear with spacing, Components page created, flows discovered
2. `/trim-pull` — Pulled frames have spacing, flows inferred from Penpot pages
3. `/trim-design` — Design pages separated by route, Components page created, flows from PRD
4. `/trim-redesign` — Redesigned frames don't overlap
5. `/trim-edit` — Edited frames maintain spacing
6. `/trim-library-sync` — Synced components maintain spacing

## Key Contracts

See `contracts/interfaces.md` for the exact text to add to each file. The contracts define 7 changes:
1. Positioning rules (all 6 workflows)
2. Page separation (push + design)
3. Components page bento grid (push + design)
4. Flow discovery — push (new step)
5. Flow discovery — pull (new step)
6. Flow discovery — design (new step)
7. Skill report updates (3 skills)
