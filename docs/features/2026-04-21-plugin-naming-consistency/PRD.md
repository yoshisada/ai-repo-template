# Feature PRD: Plugin Naming Consistency

## Parent Product

This repo hosts the `@yoshisada/kiln`, `@yoshisada/clay`, `@yoshisada/shelf`, `@yoshisada/trim`, and `@yoshisada/wheel` Claude Code plugins. Product identity and workflow conventions are defined in `CLAUDE.md`; `docs/PRD.md` is an unused placeholder.

## Feature Overview

Rename skills and workflow JSON files across all five plugins so that:
1. Two name collisions between `kiln` and `clay` are resolved (one skill removed, one renamed).
2. The `debug-diagnose` / `debug-fix` / `fix` trio collapses to a single user-facing `fix` skill.
3. One canonical convention governs skill-owns-workflow filenames (skill `X` owns `X.json`).
4. Redundant plugin-name prefixes on individual skills are dropped now that the `plugin:skill` dispatch form is the norm.

Hard cutover, no deprecation shims. Every internal cross-reference — `CLAUDE.md`, skill briefs, workflow command steps, tests, docs — is rewritten to the new names in the same change.

## Problem / Motivation

- `/create-prd` and `/create-repo` exist in **both** `kiln` and `clay`. Consumers get ambiguous dispatch and must rely on the `plugin:skill` form to disambiguate — and even then, both skills do subtly different things with the same name.
- `kiln`'s 38 skills live in an unprefixed namespace in frontmatter while the other plugins all prefix (`trim-*`, `wheel-*`, `shelf-*`). Kiln is the outlier, and its flat namespace is the most likely to collide with future consumer-repo custom skills.
- `kiln:debug-diagnose` and `kiln:debug-fix` are internal helpers that leak into the user surface. `/kiln:next` already has special-case routing to hide them from recommendations — a tell that they shouldn't be exposed at all.
- Workflow JSON filenames follow two different conventions (`shelf-full-sync.json` vs `propose-manifest-improvement.json`) with no rule for which to pick.
- Double-prefixing like `shelf:shelf-sync` and `trim:trim-pull` reads awkward now that the plugin namespace already prefixes every dispatch.

These are low-severity individually but compound: consumers can't predict skill names, future plugins have no clear naming rule to follow, and the `/kiln:next` routing shim is a band-aid that should not exist.

## Goals

- Eliminate both cross-plugin skill-name collisions.
- Remove `kiln:debug-diagnose` and `kiln:debug-fix` from the user surface; keep their logic as internal helpers called by `/kiln:fix`.
- Make every kiln skill frontmatter `name` consistent with the rest of the plugin family (either all plugins prefix-in-frontmatter or none do — this feature picks **none do**, since the `plugin:skill` dispatch form already disambiguates).
- Lock one workflow-filename rule: the skill named `X` owns the workflow `X.json`.
- Drop redundant plugin-prefix-inside-a-plugin from skill names (`shelf:shelf-sync` → `shelf:sync`, `trim:trim-pull` → `trim:pull`, `wheel:wheel-run` → `wheel:run`).
- Update every internal cross-reference in the same change — `CLAUDE.md`, other skills' briefs, workflow command steps (`${WORKFLOW_PLUGIN_DIR}/...`), agent instructions, tests, docs.

## Non-Goals

- No behavioral changes to any skill. Rename-only.
- No deprecation shims. Old names hard-fail after the cutover.
- No migration script for consumer-repo artifacts. Consumers are `yoshisada` only at this stage; any cleanup of spec files referencing old names is manual.
- No plugin-level reorganization beyond naming (no merging plugins, no moving skills between plugins).
- No changes to hooks, agents, or templates other than updating string references to renamed skills/workflows.
- The older `docs/PRD.md` placeholder is not filled in by this feature.

## Target Users

The `yoshisada` maintainer (the only current consumer of these plugins). This feature has no end-user impact beyond the maintainer typing fewer awkward command names.

## Core User Stories

- As the plugin maintainer, when I type `/clay:` I see `new-product` and `create-repo` — no longer `create-prd` (which belongs to kiln).
- As the plugin maintainer, when I type `/kiln:` I no longer see `debug-diagnose`, `debug-fix`, or `create-repo`. Only `fix` (the user surface) and `init` (add kiln to existing repo) remain.
- As the plugin maintainer, when I type `/shelf:` I see `sync` instead of `shelf-sync`; same pattern for `trim:pull`, `wheel:run`, etc.
- As the plugin maintainer, when I look for the workflow backing a skill, it lives at `<plugin>/workflows/<skill-name>.json`. No more `-full-sync`, `-and-sync` suffixes.
- As a future plugin author reading `CLAUDE.md`, I find one explicit naming rule: skills drop their plugin prefix, workflows match their skill name.

## Functional Requirements

### FR-001 — Remove `kiln:create-repo`
Delete `plugin-kiln/skills/create-repo/`. Update every reference in kiln skills, `CLAUDE.md`, and any doc that points users at it — redirect to `clay:create-repo` followed by `kiln:init`.

### FR-002 — Rename `clay:create-prd` → `clay:new-product`
Rename the directory `plugin-clay/skills/create-prd/` → `plugin-clay/skills/new-product/`. Update its frontmatter `name` field. Update every internal caller (other clay skills, workflow steps, README).

### FR-003 — Keep `kiln:create-prd` and `clay:create-repo` as-is
Collisions are resolved by FR-001 and FR-002. These two names become unambiguous.

### FR-004 — Collapse `debug-diagnose` / `debug-fix` into `fix`
Move the logic from `plugin-kiln/skills/debug-diagnose/SKILL.md` and `plugin-kiln/skills/debug-fix/SKILL.md` into helpers that `/kiln:fix` calls inline. Delete both skill directories. Remove the `/kiln:next` special-case routing that converts blocked `debug-*` commands into `/fix` (it becomes dead code).

### FR-005 — Drop redundant plugin-prefix-inside-plugin on skill names
Rename skills whose current name duplicates the plugin name. Specifically:

| Plugin | Current skill name | New skill name |
|---|---|---|
| shelf | `shelf-sync` | `sync` |
| shelf | `shelf-create` | `create` |
| shelf | `shelf-feedback` | `feedback` |
| shelf | `shelf-release` | `release` |
| shelf | `shelf-repair` | `repair` |
| shelf | `shelf-status` | `status` |
| shelf | `shelf-update` | `update` |
| trim | `trim-design` | `design` |
| trim | `trim-diff` | `diff` |
| trim | `trim-edit` | `edit` |
| trim | `trim-flows` | `flows` |
| trim | `trim-init` | `init` |
| trim | `trim-library` | `library` |
| trim | `trim-pull` | `pull` |
| trim | `trim-push` | `push` |
| trim | `trim-redesign` | `redesign` |
| trim | `trim-verify` | `verify` |
| wheel | `wheel-create` | `create` |
| wheel | `wheel-init` | `init` |
| wheel | `wheel-list` | `list` |
| wheel | `wheel-run` | `run` |
| wheel | `wheel-status` | `status` |
| wheel | `wheel-stop` | `stop` |
| wheel | `wheel-test` | `test` |
| clay | `clay-list` | `list` |

After this rename, users type `/shelf:sync`, `/trim:pull`, `/wheel:run`, `/clay:list`. The kiln skills already follow this pattern (they are not prefixed).

### FR-006 — Workflow filenames match their owning skill name
For every skill `X` that owns a workflow, the workflow file is `X.json`. Specifically:

| Plugin | Current workflow filename | New workflow filename | Owning skill |
|---|---|---|---|
| shelf | `shelf-full-sync.json` | `sync.json` | `shelf:sync` (renamed per FR-005) |
| shelf | `shelf-create.json` | `create.json` | `shelf:create` |
| shelf | `shelf-repair.json` | `repair.json` | `shelf:repair` |
| shelf | `propose-manifest-improvement.json` | `propose-manifest-improvement.json` (unchanged) | `shelf:propose-manifest-improvement` |
| kiln | `report-issue-and-sync.json` | `report-issue.json` | `kiln:report-issue` |
| kiln | `report-mistake-and-sync.json` | `mistake.json` | `kiln:mistake` |
| clay | `clay-sync.json` | (decide during /specify — tied to `clay-sync` skill if kept, or renamed) | TBD |
| trim | all 8 | (unchanged — already match) | — |
| wheel | `example.json` | `example.json` (unchanged; demo file) | — |

### FR-007 — Update every internal cross-reference in the same change
Every renamed skill or workflow appears in multiple files. Each rename MUST update:
- Other skills' `SKILL.md` that mention the old name.
- Workflow JSON `command` step paths (`${WORKFLOW_PLUGIN_DIR}/workflows/<old>.json`).
- Agent briefs (`plugin-kiln/agents/*.md`) that reference skills by name.
- `CLAUDE.md`'s "Available Commands" section and any example snippets.
- `plugin-kiln/scaffold/` files that get copied into consumer projects.
- Test fixtures or smoke-test scripts that hardcode skill/workflow names.
- `/kiln:next`'s allow-list and block-list (remove the debug-trio entries per FR-004).

A grep for each old name across the repo MUST return zero hits after the feature ships (except inside this PRD and the spec's rename table).

### FR-008 — Rename is atomic per plugin
Each plugin's rename set (skills + workflows + cross-refs) is one commit. No partial renames left in a working branch.

### FR-009 — No runtime changes
Every renamed skill continues to do exactly what it did before the rename. Any behavioral change spotted during the rename is out of scope and filed as a separate `.kiln/issues/` entry.

## Absolute Musts

- **Tech stack**: existing kiln plugin infrastructure. No new dependencies.
- **Zero broken cross-references**: a repo-wide `grep` for every pre-rename name returns zero hits after the feature ships (except in the PRD / spec rename table / git history).
- **Hard cutover**: old names do not work after the cutover. No shims, no warnings — the old name simply doesn't exist.

## Tech Stack

Inherited from product — no additions. This is a rename-only feature touching Markdown (SKILL.md files), JSON (workflow files and plugin.json), and Bash (hook/command-step scripts that reference skill/workflow paths).

## Impact on Existing Features

- **Every kiln-harness consumer must update their muscle memory** — hard cutover by design.
- **`/kiln:next` simplifies** — removes the debug-trio routing shim (FR-004). This is a net simplification, not a new surface.
- **Workflow JSON paths in `${WORKFLOW_PLUGIN_DIR}/workflows/...` change** for renamed workflows. Any hook or script that constructs these paths dynamically needs to be audited.
- **Plugin cache divergence risk** (already tracked at `.kiln/issues/2026-04-20-plugin-cache-divergence.md`): consumer caches may still hold old workflow filenames until they refresh. Not in scope to fix here, but worth flagging in the release notes.

## Success Metrics

- **SC-001**: After the feature ships, `grep -r "kiln:create-repo\|clay:create-prd\|debug-diagnose\|debug-fix\|shelf-sync\b\|trim-pull\|wheel-run\|clay-list\|shelf-full-sync\|report-issue-and-sync\|report-mistake-and-sync" .` (excluding `.git/`, `docs/features/2026-04-21-plugin-naming-consistency/`, and `specs/plugin-naming-consistency/`) returns zero hits.
- **SC-002**: Running `/shelf:sync`, `/trim:pull`, `/wheel:run`, `/clay:list`, `/clay:new-product`, `/kiln:fix` each loads the expected skill. All pre-rename names return "skill not found".
- **SC-003**: The existing `report-issue-and-sync` and `report-mistake-and-sync` workflows still execute end-to-end under their new filenames (`report-issue.json`, `mistake.json`).
- **SC-004**: `CLAUDE.md` "Available Commands" section lists only post-rename names. No stale references.

## Risks / Unknowns

- **Dynamic path construction**: if any hook or command-step script builds workflow paths by string concatenation rather than a lookup table, the rename may miss a reference. Audit all bash scripts that touch `workflows/` at minimum before cutover.
- **`clay-sync` workflow naming**: the clay plugin's single workflow file is `clay-sync.json`. Its owning skill is TBD pending a closer read of `plugin-clay/` during `/kiln:specify`. Flagged as an open question.
- **`/kiln:next` block-list drift**: the skill's prose about `/debug-diagnose` / `/debug-fix` needs to come out of the block-list, the replacement-rules table, and any nearby explanatory text. Easy to miss one.

## Assumptions

- The `yoshisada` maintainer is the only active consumer of these plugins; no external PR is currently pinned to an old skill name.
- Spec files under `specs/` that reference old skill names (from prior pipelines) are historical artifacts and do not need to be updated. Only live code/skills/workflows/docs do.
- The kiln-plugin `version` 4th-segment auto-increment will fire on every renamed file edit; that's expected churn, not a bug.

## Open Questions

- **`plugin-clay/skills/clay-sync/`** — does this skill exist, and if so does its name pattern need to match FR-005? Pending during `/kiln:specify` file survey. (The workflow `clay-sync.json` exists; the skill directory list showed `clay-list`, `create-prd`, `create-repo`, `idea`, `idea-research`, `project-naming` — no `clay-sync` skill. The workflow may be orphaned or called from `clay:idea`. Resolve during specify.)
- Should `clay:create-repo` also drop to just `clay:scaffold` or similar, for parity with "skills drop their plugin prefix"? Current direction is keep `clay:create-repo` since it's a unique action name, not a redundant prefix. Confirm during specify.
