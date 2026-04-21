# Contracts: Plugin Naming Consistency

**Spec:** [../spec.md](../spec.md)
**Plan:** [../plan.md](../plan.md)

## Purpose

This feature has **no public API surface**. Its "contract" is the full rename mapping. Every parallel implementer (Phase K, C, S, TW, X) MUST conform to these three tables exactly. Deviating from the mapping — even by one skill name — breaks the grep gate and cross-plugin references.

If a rename is missing from these tables or seems wrong, STOP and surface the ambiguity. Do not improvise.

---

## Table 1 — Skill rename table

**FR-001 (deletion), FR-002, FR-004 (deletion), FR-005.**

For each skill: the directory move, the frontmatter `name:` field change, and which FR drives it.

| FR | Plugin | Action | Old path | New path | Old frontmatter `name` | New frontmatter `name` |
|---|---|---|---|---|---|---|
| FR-001 | kiln | **delete** | `plugin-kiln/skills/create-repo/` | *(deleted)* | `create-repo` | *(none)* |
| FR-002 | clay | rename | `plugin-clay/skills/create-prd/` | `plugin-clay/skills/new-product/` | `create-prd` | `new-product` |
| FR-004 | kiln | **delete** | `plugin-kiln/skills/debug-diagnose/` | *(deleted; logic absorbed into `fix/`)* | `debug-diagnose` | *(none)* |
| FR-004 | kiln | **delete** | `plugin-kiln/skills/debug-fix/` | *(deleted; logic absorbed into `fix/`)* | `debug-fix` | *(none)* |
| FR-005 | clay | rename | `plugin-clay/skills/clay-list/` | `plugin-clay/skills/list/` | `clay-list` | `list` |
| FR-005 | shelf | rename | `plugin-shelf/skills/shelf-create/` | `plugin-shelf/skills/create/` | `shelf-create` | `create` |
| FR-005 | shelf | rename | `plugin-shelf/skills/shelf-feedback/` | `plugin-shelf/skills/feedback/` | `shelf-feedback` | `feedback` |
| FR-005 | shelf | rename | `plugin-shelf/skills/shelf-release/` | `plugin-shelf/skills/release/` | `shelf-release` | `release` |
| FR-005 | shelf | rename | `plugin-shelf/skills/shelf-repair/` | `plugin-shelf/skills/repair/` | `shelf-repair` | `repair` |
| FR-005 | shelf | rename | `plugin-shelf/skills/shelf-status/` | `plugin-shelf/skills/status/` | `shelf-status` | `status` |
| FR-005 | shelf | rename | `plugin-shelf/skills/shelf-sync/` | `plugin-shelf/skills/sync/` | `shelf-sync` | `sync` |
| FR-005 | shelf | rename | `plugin-shelf/skills/shelf-update/` | `plugin-shelf/skills/update/` | `shelf-update` | `update` |
| FR-005 | trim | rename | `plugin-trim/skills/trim-design/` | `plugin-trim/skills/design/` | `trim-design` | `design` |
| FR-005 | trim | rename | `plugin-trim/skills/trim-diff/` | `plugin-trim/skills/diff/` | `trim-diff` | `diff` |
| FR-005 | trim | rename | `plugin-trim/skills/trim-edit/` | `plugin-trim/skills/edit/` | `trim-edit` | `edit` |
| FR-005 | trim | rename | `plugin-trim/skills/trim-flows/` | `plugin-trim/skills/flows/` | `trim-flows` | `flows` |
| FR-005 | trim | rename | `plugin-trim/skills/trim-init/` | `plugin-trim/skills/init/` | `trim-init` | `init` |
| FR-005 | trim | rename | `plugin-trim/skills/trim-library/` | `plugin-trim/skills/library/` | `trim-library` | `library` |
| FR-005 | trim | rename | `plugin-trim/skills/trim-pull/` | `plugin-trim/skills/pull/` | `trim-pull` | `pull` |
| FR-005 | trim | rename | `plugin-trim/skills/trim-push/` | `plugin-trim/skills/push/` | `trim-push` | `push` |
| FR-005 | trim | rename | `plugin-trim/skills/trim-redesign/` | `plugin-trim/skills/redesign/` | `trim-redesign` | `redesign` |
| FR-005 | trim | rename | `plugin-trim/skills/trim-verify/` | `plugin-trim/skills/verify/` | `trim-verify` | `verify` |
| FR-005 | wheel | rename | `plugin-wheel/skills/wheel-create/` | `plugin-wheel/skills/create/` | `wheel-create` | `create` |
| FR-005 | wheel | rename | `plugin-wheel/skills/wheel-init/` | `plugin-wheel/skills/init/` | `wheel-init` | `init` |
| FR-005 | wheel | rename | `plugin-wheel/skills/wheel-list/` | `plugin-wheel/skills/list/` | `wheel-list` | `list` |
| FR-005 | wheel | rename | `plugin-wheel/skills/wheel-run/` | `plugin-wheel/skills/run/` | `wheel-run` | `run` |
| FR-005 | wheel | rename | `plugin-wheel/skills/wheel-status/` | `plugin-wheel/skills/status/` | `wheel-status` | `status` |
| FR-005 | wheel | rename | `plugin-wheel/skills/wheel-stop/` | `plugin-wheel/skills/stop/` | `wheel-stop` | `stop` |
| FR-005 | wheel | rename | `plugin-wheel/skills/wheel-test/` | `plugin-wheel/skills/test/` | `wheel-test` | `test` |

**Totals:** 3 deletions, 25 renames. Skills not in this table stay as-is (e.g., kiln's `fix`, `specify`, `plan`, etc.; clay's `idea`, `idea-research`, `project-naming`, `create-repo`; shelf's `propose-manifest-improvement`; wheel has no non-listed skills; trim has no non-listed skills).

**Kiln's name-stays-as-is set** (already prefix-free): `analyze`, `analyze-issues`, `audit`, `build-prd`, `checklist`, `clarify`, `constitution`, `coverage`, `create-prd`, `fix`, `implement`, `init`, `issue-to-prd`, `kiln-cleanup`, `kiln-doctor`, `mistake`, `next`, `plan`, `qa-audit`, `qa-checkpoint`, `qa-final`, `qa-pass`, `qa-pipeline`, `qa-setup`, `report-issue`, `reset-prd`, `resume`, `roadmap`, `specify`, `tasks`, `taskstoissues`, `todo`, `ux-audit-scripts`, `ux-evaluate`, `version`. Note `kiln-cleanup` and `kiln-doctor` keep the `kiln-` prefix because it's not redundant inside the kiln plugin (`kiln:kiln-doctor` reads odd but these names are action-verbs, not "noun dropped", and renaming to just `doctor` / `cleanup` is out of scope for this PRD — only the skills explicitly listed in FR-005 are renamed).

---

## Table 2 — Workflow rename table

**FR-006.**

| Plugin | Action | Old path | New path | Old `name` field (inside JSON) | New `name` field | Owning skill |
|---|---|---|---|---|---|---|
| kiln | rename | `plugin-kiln/workflows/report-issue-and-sync.json` | `plugin-kiln/workflows/report-issue.json` | `report-issue-and-sync` | `report-issue` | `kiln:report-issue` |
| kiln | rename | `plugin-kiln/workflows/report-mistake-and-sync.json` | `plugin-kiln/workflows/mistake.json` | `report-mistake-and-sync` | `mistake` | `kiln:mistake` |
| clay | rename | `plugin-clay/workflows/clay-sync.json` | `plugin-clay/workflows/sync.json` | `clay-sync` | `sync` | *(no owning skill; orphan workflow, invoked via `wheel:run clay:sync`)* |
| shelf | rename | `plugin-shelf/workflows/shelf-full-sync.json` | `plugin-shelf/workflows/sync.json` | `shelf-full-sync` | `sync` | `shelf:sync` (renamed per FR-005) |
| shelf | rename | `plugin-shelf/workflows/shelf-create.json` | `plugin-shelf/workflows/create.json` | `shelf-create` | `create` | `shelf:create` |
| shelf | rename | `plugin-shelf/workflows/shelf-repair.json` | `plugin-shelf/workflows/repair.json` | `shelf-repair` | `repair` | `shelf:repair` |
| shelf | unchanged | `plugin-shelf/workflows/propose-manifest-improvement.json` | *(unchanged)* | `propose-manifest-improvement` | *(unchanged)* | `shelf:propose-manifest-improvement` |
| trim | rename | `plugin-trim/workflows/trim-design.json` | `plugin-trim/workflows/design.json` | `trim-design` | `design` | `trim:design` |
| trim | rename | `plugin-trim/workflows/trim-diff.json` | `plugin-trim/workflows/diff.json` | `trim-diff` | `diff` | `trim:diff` |
| trim | rename | `plugin-trim/workflows/trim-edit.json` | `plugin-trim/workflows/edit.json` | `trim-edit` | `edit` | `trim:edit` |
| trim | rename | `plugin-trim/workflows/trim-pull.json` | `plugin-trim/workflows/pull.json` | `trim-pull` | `pull` | `trim:pull` |
| trim | rename | `plugin-trim/workflows/trim-push.json` | `plugin-trim/workflows/push.json` | `trim-push` | `push` | `trim:push` |
| trim | rename | `plugin-trim/workflows/trim-redesign.json` | `plugin-trim/workflows/redesign.json` | `trim-redesign` | `redesign` | `trim:redesign` |
| trim | rename | `plugin-trim/workflows/trim-verify.json` | `plugin-trim/workflows/verify.json` | `trim-verify` | `verify` | `trim:verify` |
| trim | rename | `plugin-trim/workflows/trim-library-sync.json` | `plugin-trim/workflows/library-sync.json` | `trim-library-sync` | `library-sync` | `trim:library` (library+sync sub-mode) |
| wheel | unchanged | `plugin-wheel/workflows/example.json` | *(unchanged)* | `example` | *(unchanged)* | *(demo fixture; no owning skill)* |

**Top-level `workflows/` copies** (outside plugin dirs — duplicates kept for wheel-test fixtures or dev convenience). Phase X renames these to match:
- `workflows/shelf-full-sync.json` → `workflows/sync.json` (or delete if redundant — auditor decides)
- `workflows/shelf-create.json` → `workflows/create.json`
- `workflows/shelf-repair.json` → `workflows/repair.json`
- `workflows/report-issue-and-sync.json` → `workflows/report-issue.json`
- `workflows/tests/shelf-full-sync.json` → `workflows/tests/sync.json` (audit: the wheel-test runner may look this up by a fixed name — check `plugin-wheel/skills/test/lib/runtime.sh` first).

**Totals:** 14 workflow renames, 2 unchanged (propose-manifest-improvement, example), 5 top-level duplicates to reconcile.

---

## Table 3 — Cross-reference hotspots

**FR-007.** Files that are known to reference renamed skills/workflows. Implementers MUST grep each of these for the old names they touch and update every hit.

### Root-level files
- `CLAUDE.md` — Quick Start, Architecture tree, Available Commands, Active Technologies sections. Covers all five plugins.
- `.shelf-sync.json` — project runtime state; may reference workflow filenames.

### Kiln
- `plugin-kiln/.claude-plugin/plugin.json` — if `workflows` array lists files.
- `plugin-kiln/CLAUDE.md` — if present.
- `plugin-kiln/skills/next/SKILL.md` — block-list + replacement-rules table for `debug-*`, plus `create-repo` references.
- `plugin-kiln/skills/fix/SKILL.md` — absorbs debug-diagnose + debug-fix (FR-004).
- `plugin-kiln/skills/build-prd/SKILL.md` — may reference `debug-diagnose`, `debug-fix`, `create-repo`.
- `plugin-kiln/skills/init/SKILL.md` — mentions `create-repo`.
- `plugin-kiln/skills/create-prd/SKILL.md` — mentions `create-repo`.
- `plugin-kiln/skills/issue-to-prd/SKILL.md` — mentions `create-repo`.
- `plugin-kiln/skills/report-issue/SKILL.md` — dispatches `report-issue-and-sync.json`.
- `plugin-kiln/skills/mistake/SKILL.md` — dispatches `report-mistake-and-sync.json`.
- `plugin-kiln/agents/continuance.md` — cross-plugin skill references (create-repo, debug-*, shelf-*, trim-*, wheel-*).
- `plugin-kiln/agents/debugger.md` — references debug-* and fix.
- `plugin-kiln/bin/init.mjs` — mentions `create-repo` in install flow messages.
- `plugin-kiln/scaffold/CLAUDE.md` — mirrors root CLAUDE.md for consumer projects.
- `plugin-kiln/workflows/report-issue-and-sync.json` — internal dispatch of other workflows (command steps).
- `plugin-kiln/workflows/report-mistake-and-sync.json` — internal dispatch of other workflows.

### Clay
- `plugin-clay/.claude-plugin/plugin.json` — `workflows: ["workflows/clay-sync.json"]` → `sync.json`.
- `plugin-clay/skills/clay-list/SKILL.md` (→ `list/`) — self-references, mentions `clay-sync`.
- `plugin-clay/skills/create-prd/SKILL.md` (→ `new-product/`) — self-references, may mention `create-repo`, `clay-list`.
- `plugin-clay/skills/create-repo/SKILL.md` — mentions `clay-list`, `clay-sync`.
- `plugin-clay/skills/idea/SKILL.md` — may mention `create-prd`, `clay-list`, `create-repo`.
- `plugin-clay/skills/idea-research/SKILL.md` — may mention `create-prd`.
- `plugin-clay/skills/project-naming/SKILL.md` — may mention `create-prd`.
- `plugin-clay/workflows/clay-sync.json` (→ `sync.json`) — `name` field change, possibly internal self-refs.

### Shelf
- `plugin-shelf/.claude-plugin/plugin.json` — workflows array.
- `plugin-shelf/skills/*/SKILL.md` for each renamed skill — self-references + cross-refs to other shelf skills.
- `plugin-shelf/skills/propose-manifest-improvement/SKILL.md` — references shelf-full-sync callers.
- `plugin-shelf/workflows/shelf-full-sync.json` → `sync.json` — `name` field; may call sub-workflows.
- `plugin-shelf/workflows/shelf-create.json` → `create.json` — `name` field.
- `plugin-shelf/workflows/shelf-repair.json` → `repair.json` — `name` field.
- `plugin-shelf/workflows/propose-manifest-improvement.json` — may reference shelf-full-sync in context.
- `plugin-shelf/status-labels.md` — may mention workflow filenames.
- `plugin-shelf/scripts/*.sh` — audit each for hardcoded workflow filename strings (`update-sync-manifest.sh`, `compute-work-list.sh`, `generate-sync-summary.sh`, `obsidian-snapshot-*.sh`, `read-sync-manifest.sh`, `derive-proposal-slug.sh`).

### Trim
- `plugin-trim/.claude-plugin/plugin.json` — workflows array.
- `plugin-trim/skills/*/SKILL.md` for each — self-references + cross-refs to other trim skills.
- `plugin-trim/workflows/*.json` — `name` field for each renamed workflow; audit for cross-workflow dispatch.
- `plugin-trim/templates/trim-config.tpl` — if it mentions skill names.

### Wheel
- `plugin-wheel/.claude-plugin/plugin.json` — workflows array.
- `plugin-wheel/skills/*/SKILL.md` for each renamed skill.
- `plugin-wheel/lib/*.sh` — `dispatch.sh`, `engine.sh`, `workflow.sh` may reference skill names.
- `plugin-wheel/hooks/*.sh` — `block-state-write.sh` etc.; audit for hardcoded skill/workflow names.
- `plugin-wheel/skills/test/lib/runtime.sh` — wheel-test runner; may reference workflow filenames.
- `plugin-wheel/bin/activate.sh`, `deactivate.sh`, `validate-workflow.sh` — audit.

### Tests
- `tests/test-team-wait-agent-capture.sh` — mentions `wheel-run`.
- `tests/unit/test-write-proposal-dispatch.sh` — shelf-full-sync / propose-manifest-improvement.
- `tests/unit/test-validate-reflect-output.sh` — shelf-full-sync.
- `tests/integration/out-of-scope.sh`, `hallucinated-current.sh`, `caller-wiring.sh`, `write-proposal.sh` — shelf-full-sync, report-issue-and-sync, report-mistake-and-sync.
- `workflows/tests/shelf-full-sync.json` — test fixture.

### Top-level `workflows/` duplicates
- `workflows/shelf-full-sync.json`, `workflows/shelf-create.json`, `workflows/shelf-repair.json`, `workflows/report-issue-and-sync.json`.

### Agent briefs / other
- `.claude/agents/wheel-runner.md` — may reference wheel-run, wheel-stop.

### Explicitly EXCLUDED from grep gate (historical/runtime artifacts — frozen in time)
- `.git/`
- `.wheel/history/` — all state files, archived runs
- `.kiln/logs/` — all historical logs
- `.kiln/issues/completed/` — historical issue records
- `docs/features/` — historical PRD archives
- `specs/` — all prior pipeline spec artifacts (EXCEPT this feature's `specs/plugin-naming-consistency/contracts/interfaces.md` rename tables, which contain the old names by design)
- `plugin-*/workflows/tests/` state outputs if any (but NOT the test fixture JSONs themselves, which ARE in scope)

---

## Open question resolutions (from PRD)

1. **`plugin-clay/skills/clay-sync/` directory?** Confirmed does NOT exist (never existed). The `clay-sync.json` workflow is an orphan — no skill dispatches it, no other workflow calls it. Only user-facing dispatch is `wheel:run clay-sync`. **Decision:** rename workflow to `plugin-clay/workflows/sync.json` per FR-005 prefix-drop rule; do NOT create a new owning skill (out of scope per FR-009, rename-only). Users invoke via `wheel:run clay:sync` going forward.

2. **`clay:create-repo` → `clay:scaffold`?** Confirmed: keep as `clay:create-repo`. Not a redundant prefix — `create-repo` is a unique action name. Listed under FR-003 as explicitly unchanged.

3. **`trim-library-sync.json` rename?** Confirmed: rename to `library-sync.json` (drop `trim-` prefix only). The workflow's owning skill is `trim:library` invoked in "sync" sub-mode — filename reflects the mode, which is an acceptable FR-006 variant.
