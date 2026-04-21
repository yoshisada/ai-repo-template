# Friction notes — impl-shelf

## What went smoothly
- Bulk `git mv` of all 7 shelf skill directories + 3 workflows in one command worked cleanly.
- Frontmatter edits were mechanical once each SKILL.md was read.
- The `${WORKFLOW_PLUGIN_DIR}/scripts/*.sh` pattern was already used in `sync.json` command steps, so portability was already correct — no changes needed there.

## Phase S grep-gate caveat — false positives to flag for auditor
The tasks.md S6 verification is:
```
grep -rE "shelf-(create|feedback|release|repair|status|sync|update|full-sync)" plugin-shelf/
```
This matches three legitimate non-rename occurrences I did NOT update, because they point at real (still-existing) files or directories:

1. `plugin-shelf/scripts/*.sh` header comments reference `specs/shelf-sync-efficiency/contracts/interfaces.md §N`. That spec directory still exists on disk (`ls specs/ | grep shelf` → `shelf`, `shelf-config-artifact`, `shelf-skills-polish`, `shelf-sync-efficiency`, `shelf-sync-v2`). These are accurate historical contract pointers, not rename targets.
2. `plugin-shelf/scripts/{update,read}-sync-manifest.sh` reference `.shelf-sync.json` (the persisted sync manifest at repo root). This data file is explicitly NOT in the rename table per `contracts/interfaces.md` Table 2 / Table 3 — renaming the on-disk manifest would be a backwards-incompatible data migration outside FR-006 scope.
3. `plugin-shelf/skills/sync/SKILL.md` line 174 has an example string referencing `docs/features/2026-04-03-shelf-sync-v2/PRD.md` — a historical feature slug, not a skill name.
4. `plugin-shelf/docs/PRD.md` is the historical shelf-plugin PRD. It is the document that first proposed `shelf-create`, `shelf-update`, etc. as skill names — rewriting it to say `shelf:create` would be rewriting history. The auditor's X6 grep gate in tasks.md explicitly excludes `docs/`, so this is consistent with intent; Phase S's local verification does not exclude it but should be read as "live refs only."

**Recommendation for auditor (Phase X):** when running the S6 or X6 grep, filter out:
- `plugin-shelf/docs/` (historical PRDs)
- `plugin-shelf/scripts/*.sh` spec-path comments (real dir: `specs/shelf-sync-efficiency/`)
- The literal string `.shelf-sync.json` (data file, not a rename target)
- Example strings referencing historical feature slugs (e.g., `shelf-sync-v2`)

## What I updated beyond the minimal task list
- `plugin-shelf/scripts/generate-sync-summary.sh`: renamed output path from `.wheel/outputs/shelf-full-sync-summary.md` to `.wheel/outputs/sync-summary.md` to match the workflow's terminal summary output and the workflow filename rename. The workflow JSON's `generate-sync-summary` step already points to `sync-summary.md` post-edit; without this script change, the step would write to a stale path.
- `plugin-shelf/workflows/sync.json` self-improve step: updated the list of step-output files the auditor agent reads to reflect the new `sync-summary.md` filename.
- `plugin-shelf/workflows/propose-manifest-improvement.json` reflect-step instructions: updated the example caller names (`report-mistake-and-sync` → `kiln:mistake`, `report-issue-and-sync` → `kiln:report-issue`, `shelf-full-sync` → `shelf:sync`) and the example output path (`shelf-full-sync-summary.md` → `sync-summary.md`). These are references, not dispatch calls — no functional change.

## Untouched-on-purpose
- `plugin-shelf/.claude-plugin/plugin.json` has no `workflows` array, so the tasks.md S2 line "Update `plugin-shelf/.claude-plugin/plugin.json` `workflows` array" was a no-op — confirmed by reading the file.
- `plugin-shelf/workflows/propose-manifest-improvement.json` name field (`propose-manifest-improvement`) left unchanged per Table 2.

## Callouts for other implementers
- `impl-kiln`: the two workflows that Shelf's `propose-manifest-improvement` cites as callers (`report-issue-and-sync`, `report-mistake-and-sync`) are in your plugin — I updated the citations in my plugin's workflow JSON to the expected post-rename names (`kiln:report-issue`, `kiln:mistake`), so if you deviate from those names, my references will go stale.
