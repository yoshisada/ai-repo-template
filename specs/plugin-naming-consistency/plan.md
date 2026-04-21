# Implementation Plan: Plugin Naming Consistency

**Spec:** [spec.md](./spec.md)
**Contracts:** [contracts/interfaces.md](./contracts/interfaces.md)
**Status:** Planned

## Technical Approach

This is a rename-only change. The "contract" for parallel implementers is not a function signature set — it is the **rename mapping tables** in `contracts/interfaces.md`. Every implementer and auditor MUST conform exactly to those tables.

No new files are created except `scripts/` helpers split out from `debug-diagnose` / `debug-fix` if the prose would bloat `fix/SKILL.md`. No public APIs change. No runtime behavior changes.

### Strategy

**Parallel-by-plugin.** Each plugin directory (`plugin-kiln/`, `plugin-clay/`, `plugin-shelf/`, `plugin-trim/` + `plugin-wheel/`) is disjoint file-set territory for one implementer. Cross-cutting files (`CLAUDE.md`, `plugin-kiln/scaffold/`, top-level `workflows/`, `tests/`) are handled last by the auditor/integration phase.

Each phase commits atomically per plugin. Cross-plugin references (e.g., shelf skill mentions a wheel workflow) are resolved by whichever phase owns the file containing the reference — implementers do NOT edit files outside their plugin directory. The integration commit in Phase X picks up leftover cross-plugin references in `CLAUDE.md` and scaffolds.

### Technique per rename type

| Rename | Technique |
|---|---|
| Skill directory rename | `git mv plugin-X/skills/old/ plugin-X/skills/new/` + edit frontmatter `name:` in `SKILL.md`. |
| Skill deletion (FR-001, FR-004) | `git rm -r plugin-X/skills/old/`. |
| Workflow filename rename | `git mv plugin-X/workflows/old.json plugin-X/workflows/new.json` + edit `"name"` field inside JSON. |
| Cross-reference update | Grep the target old name; use Edit tool with precise strings to update each occurrence. Prefer `replace_all` within a file when safe. |

### Absorbing debug-diagnose / debug-fix into fix (FR-004)

Read the current `plugin-kiln/skills/fix/SKILL.md`. If it is <= 250 lines after absorption, inline the logic directly. Otherwise factor the diagnose and fix steps into helper scripts under `plugin-kiln/scripts/fix-debug-diagnose.sh` and `plugin-kiln/scripts/fix-debug-fix.sh` and have the fix skill invoke them. The inline vs. helper decision is the Phase K implementer's call — both satisfy FR-004.

Either way, `plugin-kiln/skills/fix/SKILL.md` MUST end up with no references to the deleted `/debug-diagnose` or `/debug-fix` skill names; it either implements the behavior itself or calls local scripts.

### Handling `/kiln:next` block-list (FR-004)

`plugin-kiln/skills/next/SKILL.md` has a block-list and a replacement-rules table for `/debug-diagnose` and `/debug-fix`. Both entries come out. Check for surrounding prose that explains the block-list — that also comes out.

## Phases

Each phase is one atomic commit (or two, if FR-004 debug absorption is large enough to warrant separation).

### Phase K — kiln (owner: impl-kiln)
- FR-001: delete `plugin-kiln/skills/create-repo/`.
- FR-004: absorb debug-diagnose + debug-fix into `plugin-kiln/skills/fix/SKILL.md` (with helper scripts if needed); delete both skill dirs; update `plugin-kiln/skills/next/SKILL.md` block-list.
- FR-006: rename `plugin-kiln/workflows/report-issue-and-sync.json` → `report-issue.json`; rename `report-mistake-and-sync.json` → `mistake.json`; update `name` fields; update `plugin-kiln/.claude-plugin/plugin.json`; update `plugin-kiln/skills/report-issue/SKILL.md` and `plugin-kiln/skills/mistake/SKILL.md` dispatch paths.
- FR-007: update kiln-internal cross-references (skills mentioning removed/renamed items); update `plugin-kiln/agents/*.md`; update `plugin-kiln/bin/init.mjs`.

**Files outside kiln that may need touching (defer to Phase X):** `CLAUDE.md`, top-level `workflows/report-issue-and-sync.json` if it exists.

Commit message: `refactor(kiln): rename/remove skills and workflows (FR-001, FR-004, FR-006, FR-007)`.

### Phase C — clay (owner: impl-clay)
- FR-002: rename `plugin-clay/skills/create-prd/` → `new-product/`; update frontmatter and all clay-internal callers.
- FR-005: rename `plugin-clay/skills/clay-list/` → `list/`; update frontmatter.
- FR-006: rename `plugin-clay/workflows/clay-sync.json` → `sync.json`; update `name` field inside JSON; update `plugin-clay/.claude-plugin/plugin.json` workflows array.
- FR-007: update clay-internal cross-references (every clay skill mentioning `create-prd`, `clay-list`, or `clay-sync`).

Commit message: `refactor(clay): rename create-prd→new-product, clay-list→list, clay-sync→sync (FR-002, FR-005, FR-006, FR-007)`.

### Phase S — shelf (owner: impl-shelf)
- FR-005: rename 7 skills (`shelf-create`, `shelf-feedback`, `shelf-release`, `shelf-repair`, `shelf-status`, `shelf-sync`, `shelf-update` → `create`, `feedback`, `release`, `repair`, `status`, `sync`, `update`). Update frontmatter for each.
- FR-006: rename workflows:
  - `shelf-full-sync.json` → `sync.json` (+ update `name` field).
  - `shelf-create.json` → `create.json` (+ update `name` field).
  - `shelf-repair.json` → `repair.json` (+ update `name` field).
  - `propose-manifest-improvement.json` — unchanged (skill name is already prefix-free).
- FR-007: update shelf-internal cross-references (skills dispatching workflows, workflow command steps invoking other workflows, agent prose); update `plugin-shelf/.claude-plugin/plugin.json`; update `plugin-shelf/scripts/*.sh` if any hardcode workflow names; update `plugin-shelf/status-labels.md`.

Commit message: `refactor(shelf): drop shelf- prefix from skills and workflows (FR-005, FR-006, FR-007)`.

### Phase TW — trim + wheel (owner: impl-trim-wheel)
- FR-005 (trim): rename 10 skills (`trim-design`, `trim-diff`, `trim-edit`, `trim-flows`, `trim-init`, `trim-library`, `trim-pull`, `trim-push`, `trim-redesign`, `trim-verify` → drop `trim-` prefix).
- FR-005 (wheel): rename 7 skills (`wheel-create`, `wheel-init`, `wheel-list`, `wheel-run`, `wheel-status`, `wheel-stop`, `wheel-test` → drop `wheel-` prefix).
- FR-006: trim workflows already match their skills (`trim-design.json` → `design.json`, etc.); wheel has only `example.json` (unchanged). For trim, rename all 8 workflow files to match the new skill names (`trim-design.json` → `design.json`, etc.), update `name` fields, update `plugin-trim/.claude-plugin/plugin.json`. For `trim-library-sync.json` — this is owned by the renamed `library` skill; rename to `library-sync.json` if the skill's sync mode dispatches it, or evaluate whether to collapse. **Resolution:** `trim-library-sync.json` stays named `library-sync.json` (its owning skill is `trim:library` and it is dispatched as a sub-mode "sync" — not a separate skill). Per FR-006 the filename matches "the owning skill plus a mode suffix"; acceptable exception.
- FR-007: update trim/wheel-internal cross-references, including `plugin-trim/templates/trim-config.tpl` if it hardcodes skill names; update `plugin-wheel/lib/*.sh` and `plugin-wheel/hooks/*.sh` if any hardcode workflow/skill names; update `plugin-wheel/skills/wheel-test/lib/runtime.sh`; update `plugin-trim/.claude-plugin/plugin.json` and `plugin-wheel/.claude-plugin/plugin.json`.

**Cross-dependency note:** shelf skills and shelf workflows may reference `wheel:wheel-run`; those references live in shelf files and are Phase S's job to update (per "whichever phase owns the file" rule). Phase TW owns wheel's internal files only.

Commit message: `refactor(trim,wheel): drop plugin-prefix from skills and workflows (FR-005, FR-006, FR-007)`.

### Phase X — cross-cutting + gate (owner: auditor)
- Update `CLAUDE.md` (Quick Start, Architecture tree, Available Commands, Active Technologies).
- Update `plugin-kiln/scaffold/CLAUDE.md` if it mirrors the above.
- Update top-level `workflows/` copies (if they are live):
  - `workflows/shelf-full-sync.json` → `sync.json`
  - `workflows/shelf-create.json` → `create.json`
  - `workflows/shelf-repair.json` → `repair.json`
  - `workflows/report-issue-and-sync.json` → `report-issue.json`
  - `workflows/tests/shelf-full-sync.json` → evaluate: if it is a wheel-test fixture that references the shelf-full-sync filename by design, leave the reference name but update internals; otherwise rename.
- Update `tests/` integration/unit tests that hardcode skill or workflow names.
- Update `.shelf-sync.json` if it references old filenames.
- Run the grep gate (see SC-001 in spec).
- Smoke-test: invoke `/kiln:fix` with a mock issue, dispatch `/wheel:run sync` (was `shelf-full-sync`), ensure no "skill not found" for renamed names and no hits for old names.

Commit message: `refactor(docs,scaffold,tests): update cross-plugin references for naming consistency (FR-007)`.

## Technical Risks

1. **Grep false-positives from historical artifacts**: `.wheel/history/`, `.kiln/logs/`, `specs/`, `docs/features/` all contain old names. The grep gate MUST exclude these or it will fail spuriously. The exclude list is enumerated in spec.md SC-001 and `contracts/interfaces.md` Table 3.

2. **`/kiln:next` prose drift**: the block-list table and surrounding prose in `plugin-kiln/skills/next/SKILL.md` mention `debug-*` in multiple places. Phase K must do a careful read, not a single regex replace.

3. **Dynamic workflow path construction**: If any bash script concatenates `"workflows/" + name + ".json"`, those sites need individual audits. Most known call sites use the static `${WORKFLOW_PLUGIN_DIR}/workflows/<name>.json` pattern, which requires explicit edit per site.

4. **Cross-plugin agent briefs**: `plugin-kiln/agents/continuance.md` and `plugin-kiln/agents/debugger.md` reference skills across all plugins. Phase K owns these files, so Phase K implementer must update references to shelf/trim/wheel skills even though those plugins are Phase S and Phase TW territory. This is the one exception to "own your plugin only" — agent briefs are global.

5. **Version file churn**: every file edit increments the VERSION 4th segment. Expected, not a bug. Optionally bump `pr` once at start.

## Rollback

If the cutover breaks in production (the maintainer's personal repo), the revert is a single `git revert` on the Phase X merge commit, followed by sequential reverts of Phase K/C/S/TW. Each phase commit leaves the repo in a consistent state (per FR-008), so partial revert is safe.
