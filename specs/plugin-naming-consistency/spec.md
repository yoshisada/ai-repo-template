# Feature Spec: Plugin Naming Consistency

**Branch:** `build/plugin-naming-consistency-20260421`
**Feature slug:** `plugin-naming-consistency`
**PRD:** `docs/features/2026-04-21-plugin-naming-consistency/PRD.md`
**Status:** Specified

## Summary

Rename skills and workflow JSON files across the five plugins (`kiln`, `clay`, `shelf`, `trim`, `wheel`) so that:

1. Two name collisions between `kiln` and `clay` are resolved by deleting `kiln:create-repo` and renaming `clay:create-prd` → `clay:new-product`.
2. The `debug-diagnose` / `debug-fix` skills collapse into inline helpers of `/kiln:fix` (their only real caller) and are removed from the user surface.
3. Redundant plugin-name prefixes on individual skills are dropped (`shelf:shelf-sync` → `shelf:sync`, `trim:trim-pull` → `trim:pull`, `wheel:wheel-run` → `wheel:run`, `clay:clay-list` → `clay:list`).
4. Workflow filenames match their owning skill: `shelf-full-sync.json` → `sync.json`, `report-issue-and-sync.json` → `report-issue.json`, `report-mistake-and-sync.json` → `mistake.json`. The orphan `clay-sync.json` workflow is renamed to `sync.json` to match the FR-005 prefix-drop rule (no owning skill is created — it remains invocable via `wheel:run clay:sync`).
5. Every internal cross-reference is updated in the same change: `CLAUDE.md`, skill `SKILL.md` files, workflow `command` step paths, agent briefs, scaffold/, tests.

Hard cutover. No deprecation shims. Rename-only — no runtime behavior change to any skill.

## User Stories

- **US-001** (maintainer): As the plugin maintainer, when I type `/clay:` in Claude Code I see `new-product` and `create-repo` — no longer `create-prd`.
- **US-002** (maintainer): As the plugin maintainer, when I type `/kiln:` I no longer see `debug-diagnose`, `debug-fix`, or `create-repo`. The `fix` skill still works end-to-end.
- **US-003** (maintainer): As the plugin maintainer, when I type `/shelf:`, `/trim:`, `/wheel:`, `/clay:` I see un-prefixed skill names (`sync`, `pull`, `run`, `list`).
- **US-004** (maintainer): As the plugin maintainer, when I look for the workflow backing a skill, it lives at `<plugin>/workflows/<skill-name>.json`.
- **US-005** (maintainer): As the plugin maintainer, after the rename lands, a repo-wide `grep` for any old name returns zero hits in live code.
- **US-006** (future plugin author): As someone adding a new plugin, I find one explicit naming rule in `CLAUDE.md`: skills drop their plugin prefix in frontmatter; workflows match their owning skill name.

## Functional Requirements

### FR-001 — Remove `kiln:create-repo`
Delete the directory `plugin-kiln/skills/create-repo/` entirely. Update every reference in kiln skills, agent briefs, `CLAUDE.md`, and scaffold files to redirect users to `clay:create-repo` followed by `kiln:init`.

**Known cross-references to update:**
- `CLAUDE.md` line 19 (quick-start example)
- `CLAUDE.md` line 56 (architecture tree)
- `CLAUDE.md` line 190 (Available Commands)
- `plugin-kiln/skills/next/SKILL.md` (mentions create-repo)
- `plugin-kiln/skills/init/SKILL.md` (mentions create-repo)
- `plugin-kiln/skills/create-prd/SKILL.md` (mentions create-repo)
- `plugin-kiln/skills/issue-to-prd/SKILL.md` (mentions create-repo)
- `plugin-kiln/skills/build-prd/SKILL.md` (mentions create-repo)
- `plugin-kiln/agents/continuance.md` (mentions create-repo)
- `plugin-kiln/bin/init.mjs` (mentions create-repo)

### FR-002 — Rename `clay:create-prd` → `clay:new-product`
Rename the directory `plugin-clay/skills/create-prd/` → `plugin-clay/skills/new-product/`. Update its frontmatter `name` field to `new-product`. Update every internal caller.

**Known cross-references to update:**
- `plugin-clay/skills/new-product/SKILL.md` (frontmatter + all self-references)
- `plugin-clay/skills/idea/SKILL.md`
- `plugin-clay/skills/idea-research/SKILL.md`
- `plugin-clay/skills/project-naming/SKILL.md`
- `plugin-clay/skills/create-repo/SKILL.md`
- `plugin-clay/skills/clay-list/SKILL.md` (→ `list`, see FR-005)
- `CLAUDE.md`

### FR-003 — Keep `kiln:create-prd` and `clay:create-repo` as-is
Collisions are resolved by FR-001 and FR-002. These two skill names become unambiguous. No file changes required; listed only for completeness.

### FR-004 — Collapse `debug-diagnose` / `debug-fix` into `kiln:fix`
Move the prose and helper logic from `plugin-kiln/skills/debug-diagnose/SKILL.md` and `plugin-kiln/skills/debug-fix/SKILL.md` into `plugin-kiln/skills/fix/SKILL.md` as inline "diagnose" and "fix" steps (or into helper scripts under `plugin-kiln/scripts/` if the prose would bloat the fix skill beyond ~300 lines). Delete both skill directories. Remove the `/kiln:next` special-case routing that converts blocked `debug-*` commands into `/fix`.

**Known cross-references to update:**
- `plugin-kiln/skills/fix/SKILL.md` (absorb debug-diagnose + debug-fix logic)
- `plugin-kiln/skills/next/SKILL.md` (remove debug-* from block-list and replacement-rules table)
- `plugin-kiln/skills/build-prd/SKILL.md` (remove debug-* references)
- `plugin-kiln/agents/continuance.md` (remove debug-* references)
- `plugin-kiln/agents/debugger.md` (update references)
- `CLAUDE.md` lines 201–202 (remove `/debug-diagnose` and `/debug-fix` from Available Commands)

**Scope constraint:** The fix skill's public behavior MUST remain identical. The debug-trio's logic stays; only the user-facing skill entry points are removed.

### FR-005 — Drop redundant plugin-prefix-inside-plugin on skill names
Rename skills whose current name duplicates the plugin name. Full mapping table lives in `contracts/interfaces.md` (Table 1). After rename, users type `/shelf:sync`, `/trim:pull`, `/wheel:run`, `/clay:list`.

For every renamed skill:
1. Rename the directory: `plugin-<p>/skills/<p>-<name>/` → `plugin-<p>/skills/<name>/`.
2. Update the frontmatter `name:` field in the skill's `SKILL.md`.
3. Update every cross-reference across the repo (see FR-007).

### FR-006 — Workflow filenames match their owning skill
Rename workflow files so each workflow owned by skill `X` is named `X.json`. Full mapping table in `contracts/interfaces.md` (Table 2).

For every renamed workflow:
1. Rename the `.json` file.
2. Update the workflow's `name` field inside the JSON.
3. Update every reference to the old filename in:
   - `plugin-<p>/.claude-plugin/plugin.json` (workflows array)
   - Other workflow JSONs (command step invocations of the workflow)
   - Skill `SKILL.md` files that dispatch the workflow
   - `workflows/tests/` test fixtures
   - `workflows/` top-level copies (if any)

**`clay-sync.json` resolution (open question from PRD):** Survey confirmed no `clay:clay-sync` skill exists and no other skill or workflow dispatches this workflow programmatically. It is an orphan workflow invoked only by the user via `wheel:run clay-sync`. Decision: rename to `plugin-clay/workflows/sync.json` per the FR-005 prefix-drop rule; update the `name` field inside the JSON to `sync`. No new owning skill is created (out of scope per FR-009). Users invoke via `wheel:run clay:sync` going forward.

### FR-007 — Update every internal cross-reference in the same change
Every rename from FR-001, FR-002, FR-004, FR-005, FR-006 MUST update:

- Other skills' `SKILL.md` files that mention the old name.
- Workflow JSON `command` step paths (`${WORKFLOW_PLUGIN_DIR}/workflows/<old>.json`).
- Workflow JSON `name` field inside renamed workflows.
- `plugin-*/.claude-plugin/plugin.json` `workflows` arrays.
- Agent briefs (`plugin-kiln/agents/*.md`) that reference skills by name.
- `CLAUDE.md`'s Quick Start, Architecture tree, Available Commands, and any example snippets.
- `plugin-kiln/scaffold/CLAUDE.md` if it has the same references.
- Test fixtures under `tests/` and `workflows/tests/` that hardcode skill/workflow names.
- `.shelf-sync.json` (project config that may reference workflow filenames).
- Any top-level `workflows/` files that mirror plugin workflows (e.g. `workflows/shelf-full-sync.json`, `workflows/shelf-create.json`, `workflows/shelf-repair.json`, `workflows/report-issue-and-sync.json`).

Cross-reference hotspots are enumerated in `contracts/interfaces.md` (Table 3).

**Acceptance gate:** A repo-wide `grep` for each old name returns zero hits in live code after the feature ships. "Live code" excludes: `.git/`, `specs/` (historical frozen artifacts), `.wheel/history/` (runtime state archives), `.kiln/logs/`, `.kiln/issues/completed/`, `docs/features/` (PRD archives), this spec's own rename tables in `contracts/interfaces.md`.

### FR-008 — Rename is atomic per plugin
Each plugin's rename set (skills + workflows + cross-refs in its own files) is committed as one unit. Commits MUST be ordered so each commit leaves the repo in a consistent state (no dangling references). Per the parallelization in `tasks.md`, phases are:

- **Phase K (kiln)**: FR-001 + FR-004 + FR-006 kiln-side + FR-007 kiln-side.
- **Phase C (clay)**: FR-002 + FR-005 clay-list + clay-sync workflow rename + FR-007 clay-side.
- **Phase S (shelf)**: FR-005 shelf-* + FR-006 shelf workflow renames + FR-007 shelf-side.
- **Phase TW (trim + wheel)**: FR-005 trim-* + FR-005 wheel-* + FR-007 trim-side + wheel-side.
- **Phase X (cross-cutting)**: `CLAUDE.md`, `plugin-kiln/scaffold/`, top-level `workflows/`, grep gate — handled by the auditor.

Because cross-references span plugins, implementers may need a final integration commit that reconciles cross-plugin references in `CLAUDE.md` etc. The auditor owns this.

### FR-009 — No runtime changes
Every renamed skill continues to do exactly what it did before the rename. Any behavioral change spotted during the rename is out of scope and MUST be filed as a separate `.kiln/issues/` entry instead of being addressed in this change.

## Success Criteria

- **SC-001**: `grep -rE "kiln:create-repo|clay:create-prd|kiln:debug-diagnose|kiln:debug-fix|shelf:shelf-(sync|create|feedback|release|repair|status|update)|trim:trim-(design|diff|edit|flows|init|library|pull|push|redesign|verify)|wheel:wheel-(create|init|list|run|status|stop|test)|clay:clay-list|shelf-full-sync|report-issue-and-sync|report-mistake-and-sync" .` — excluding `.git/`, `.wheel/history/`, `.kiln/logs/`, `.kiln/issues/completed/`, `docs/features/`, `specs/`, and the rename table inside `contracts/interfaces.md` — returns **zero hits**.
- **SC-002**: Invoking each renamed skill (`/shelf:sync`, `/trim:pull`, `/wheel:run`, `/clay:list`, `/clay:new-product`, `/kiln:fix`) loads the expected skill. Pre-rename names return "skill not found".
- **SC-003**: The existing `report-issue-and-sync` and `report-mistake-and-sync` workflows execute end-to-end under their new filenames (`report-issue.json`, `mistake.json`). The `shelf-full-sync` workflow executes end-to-end as `sync.json`.
- **SC-004**: `CLAUDE.md`'s Available Commands section lists only post-rename names. No stale references.
- **SC-005**: `kiln:fix` runs the full diagnose→fix→verify flow end-to-end with no `debug-diagnose` or `debug-fix` skill present. All logic previously in those skills is reachable from `fix`.
- **SC-006**: Every plugin's `plugin.json` `workflows` array points at files that actually exist.

## Edge Cases

- **Top-level `workflows/` directory**: the repo has both `plugin-shelf/workflows/shelf-full-sync.json` and a top-level `workflows/shelf-full-sync.json`. These are separate files (the top-level copies exist for wheel-test fixtures, per `workflows/tests/shelf-full-sync.json`). Both MUST be renamed — missing either will break grep gate and/or wheel tests.
- **`.shelf-sync.json`** in the repo root is project runtime state (not a workflow definition); audit whether it references old workflow filenames.
- **`plugin-kiln/bin/init.mjs`** may reference skill directory names when scaffolding consumer projects. Audit for `create-repo` and `debug-*` references.
- **`scaffold/CLAUDE.md`** is shipped to consumers at init time. Any old-name references here would ship broken naming to future consumers.
- **Wheel test fixtures** under `workflows/tests/` hardcode workflow names for validation runs. Renaming must update these in lockstep.
- **Running workflow state files** (`.wheel/history/stopped/state_*.json`) reference old workflow names in their payloads. These are runtime artifacts frozen at write time and are explicitly **excluded** from the grep gate — no migration needed.
- **Plugin version files**: renames trigger `version-increment.sh` hook edits on every touched file. Expected churn; reconcile by bumping the `pr` segment once before starting and letting `edit` accumulate.

## Assumptions

- `yoshisada` is the only active consumer; no external PRs pinned to old names.
- `specs/` files from prior pipelines referencing old skill names are historical artifacts and do not need updating.
- The top-level `workflows/` directory's copies of plugin workflows are either live duplicates (in which case they must be renamed) or stale artifacts (in which case they can be left — but identifying which is out of scope; default to renaming to be safe).

## Dependencies

None. Feature is self-contained within the five plugin directories and repo-root files (`CLAUDE.md`, `workflows/`, `tests/`, `.shelf-sync.json`).

## Risks

- **Dynamic path construction**: if any hook or command-step script builds workflow paths by string concatenation rather than a lookup table, the rename may miss a reference. Mitigation: audit all bash scripts under `plugin-*/hooks/` and `plugin-*/scripts/` that touch `workflows/` before cutover.
- **`/kiln:next` block-list drift**: `next/SKILL.md` has prose about `/debug-diagnose` / `/debug-fix` in both the block-list and replacement-rules table and any nearby explanatory text. Easy to miss one; auditor MUST grep.
- **Plugin cache divergence** (already tracked at `.kiln/issues/2026-04-20-plugin-cache-divergence.md`): consumer caches may still hold old workflow filenames until they refresh. Not in scope to fix here; flag in release notes.

## Out of Scope

- Any behavioral change to any skill (FR-009).
- Deprecation shims or compatibility layers.
- Renaming `clay:create-repo` to `clay:scaffold` — confirmed during specify: keep as-is.
- Creating a new `clay:sync` skill to own the renamed `sync.json` workflow — out of scope; workflow remains invoked via `wheel:run clay:sync`.
- Migrating consumer-repo spec files that reference old skill names.
- Fixing the `docs/PRD.md` placeholder.
