# Quickstart: Kiln Polish

## What's Changing

1. **`/next` gets a "Suggested next" line** — after the recommendations list, a single prominent line shows the highest-priority command with a reason.

2. **`.kiln/qa/` gets a canonical structure** — five standard subdirectories (`tests/`, `results/`, `screenshots/`, `videos/`, `config/`) with a README.

## Files to Modify

### `/next` Suggested Command (FR-001, FR-002, FR-003)
- `plugin/skills/next/SKILL.md` — Add "Suggested next" output after Step 5, update QA report read paths in Step 2

### QA Directory Structure (FR-004 through FR-008)
- `plugin/bin/init.mjs` — Add QA subdirectories to scaffold
- `plugin/scaffold/qa-readme.md` — New README template for `.kiln/qa/`
- `plugin/skills/qa-setup/SKILL.md` — Update mkdir and output paths
- `plugin/agents/qa-reporter.md` — Update report output paths
- `plugin/agents/ux-evaluator.md` — Update screenshot paths
- `plugin/templates/kiln-manifest.json` — Add QA subdirectory entries
- `plugin/scaffold/gitignore` — Update gitignore paths

## Implementation Order

1. Update `kiln-manifest.json` with QA subdirectory definitions (FR-004)
2. Create `plugin/scaffold/qa-readme.md` (FR-008)
3. Update `init.mjs` to create QA subdirs + copy README (FR-007)
4. Update `/qa-setup` SKILL.md with new paths (FR-005)
5. Update QA agents with canonical output paths (FR-006)
6. Update `/next` SKILL.md to add "Suggested next" output (FR-001, FR-002, FR-003)
7. Update `/next` SKILL.md QA report read paths (consistency)
8. Update gitignore for new canonical paths
