# Tasks: Plugin Naming Consistency

**Spec:** [spec.md](./spec.md)
**Plan:** [plan.md](./plan.md)
**Contracts:** [contracts/interfaces.md](./contracts/interfaces.md)

Partitioned by plugin so the four parallel implementers (Phase K/C/S/TW) own disjoint file sets. The auditor owns Phase X (cross-cutting + gate).

Every task maps to at least one FR. `[P]` marks tasks safely parallelizable within a phase.

---

## Phase K — kiln plugin renames (owner: impl-kiln)

### K1. Delete `plugin-kiln/skills/create-repo/` (FR-001)
- [X] `git rm -r plugin-kiln/skills/create-repo/`.
- [X] Verify no stray files remain: `ls plugin-kiln/skills/create-repo/ 2>&1` should report "No such file".

### K2. Absorb debug-diagnose + debug-fix into `kiln:fix` (FR-004)
- [X] Read `plugin-kiln/skills/debug-diagnose/SKILL.md` and `plugin-kiln/skills/debug-fix/SKILL.md` in full.
- [X] Read `plugin-kiln/skills/fix/SKILL.md` in full.
- [X] Decide: inline vs. helper scripts (see plan.md). If helper scripts, create them under `plugin-kiln/scripts/`.
- [X] Update `plugin-kiln/skills/fix/SKILL.md` to subsume the debug-* logic. Verify the fix skill no longer references `/debug-diagnose` or `/debug-fix`.
- [X] `git rm -r plugin-kiln/skills/debug-diagnose/ plugin-kiln/skills/debug-fix/`.

### K3. Update `plugin-kiln/skills/next/SKILL.md` block-list (FR-004, FR-007)
- [X] Read `next/SKILL.md` and find the block-list + replacement-rules table + any prose mentioning `/debug-diagnose` or `/debug-fix`.
- [X] Remove both entries from the block-list.
- [X] Remove both entries from the replacement-rules table.
- [X] Remove surrounding explanatory prose about the debug-* block-list shim.
- [X] Remove any `create-repo` references (FR-001).
- [X] Verify: grep `next/SKILL.md` for `debug-diagnose`, `debug-fix`, `create-repo` — should return zero hits.

### K4. [P] Rename kiln workflows (FR-006)
- [X] `git mv plugin-kiln/workflows/report-issue-and-sync.json plugin-kiln/workflows/report-issue.json`.
- [X] Edit `plugin-kiln/workflows/report-issue.json` — change `"name": "report-issue-and-sync"` → `"name": "report-issue"`.
- [X] `git mv plugin-kiln/workflows/report-mistake-and-sync.json plugin-kiln/workflows/mistake.json`.
- [X] Edit `plugin-kiln/workflows/mistake.json` — change `"name": "report-mistake-and-sync"` → `"name": "mistake"`.
- [X] Update `plugin-kiln/.claude-plugin/plugin.json` `workflows` array to reference new filenames.
- [X] Update `plugin-kiln/skills/report-issue/SKILL.md` dispatch paths to `workflows/report-issue.json`.
- [X] Update `plugin-kiln/skills/mistake/SKILL.md` dispatch paths to `workflows/mistake.json`.

### K5. [P] Update kiln skill cross-references (FR-001, FR-004, FR-007)
Each edit uses Grep first to find hits, then Edit to replace:
- [X] `plugin-kiln/skills/init/SKILL.md` — remove `create-repo` references; redirect to `clay:create-repo + kiln:init`.
- [X] `plugin-kiln/skills/create-prd/SKILL.md` — remove `create-repo` references; redirect to `clay:create-repo`.
- [X] `plugin-kiln/skills/issue-to-prd/SKILL.md` — remove `create-repo` references.
- [X] `plugin-kiln/skills/build-prd/SKILL.md` — remove `create-repo`, `debug-diagnose`, `debug-fix` references.
- [X] `plugin-kiln/bin/init.mjs` — remove `create-repo` references.

### K6. [P] Update kiln agent briefs (FR-001, FR-004, FR-007)
- [X] `plugin-kiln/agents/continuance.md` — remove `create-repo`, `debug-diagnose`, `debug-fix` references.
- [X] `plugin-kiln/agents/debugger.md` — remove `debug-diagnose`, `debug-fix` skill references (keep internal debug logic if it references the `fix` skill).

### K7. Commit Phase K (FR-008)
- [ ] `git add plugin-kiln/ && git commit -m "refactor(kiln): remove create-repo + debug-* skills, rename workflows (FR-001, FR-004, FR-006, FR-007)"`.
- [ ] Verify: `grep -r "kiln:create-repo\|kiln:debug-diagnose\|kiln:debug-fix\|report-issue-and-sync\|report-mistake-and-sync" plugin-kiln/` returns zero hits.
- [ ] Record friction notes in `specs/plugin-naming-consistency/agent-notes/impl-kiln.md`.

---

## Phase C — clay plugin renames (owner: impl-clay)

### C1. Rename `clay:create-prd` → `clay:new-product` (FR-002)
- [X] `git mv plugin-clay/skills/create-prd/ plugin-clay/skills/new-product/`.
- [X] Edit `plugin-clay/skills/new-product/SKILL.md` frontmatter: `name: create-prd` → `name: new-product`.
- [X] Update description if it self-describes as "create PRDs" to match the new name.

### C2. Rename `clay:clay-list` → `clay:list` (FR-005)
- [X] `git mv plugin-clay/skills/clay-list/ plugin-clay/skills/list/`.
- [X] Edit `plugin-clay/skills/list/SKILL.md` frontmatter: `name: clay-list` → `name: list`.

### C3. Rename `clay-sync.json` → `sync.json` (FR-006)
- [X] `git mv plugin-clay/workflows/clay-sync.json plugin-clay/workflows/sync.json`.
- [X] Edit `plugin-clay/workflows/sync.json` — change `"name": "clay-sync"` → `"name": "sync"`. Update the `.wheel/outputs/clay-sync-*.md` output paths inside the JSON to `.wheel/outputs/sync-*.md` (keep prefix-free for consistency, or leave if downstream consumers rely on the old path — default: update to sync-*).
- [X] Update `plugin-clay/.claude-plugin/plugin.json` `workflows` array: `workflows/clay-sync.json` → `workflows/sync.json`.

### C4. [P] Update clay skill cross-references (FR-007)
- [X] `plugin-clay/skills/list/SKILL.md` (formerly clay-list) — update any self-references from `clay-list` to `list`; update the `clay-sync` reference (line with `<!-- FR-036: clay_derive_status logic — keep identical with clay-sync workflow -->`) to `sync`.
- [X] `plugin-clay/skills/new-product/SKILL.md` — update any self-references from `create-prd` to `new-product`; update references to `clay-list` → `list`.
- [X] `plugin-clay/skills/create-repo/SKILL.md` — update `/clay-list` → `/clay:list`, `clay-sync` → `clay:sync` (line 165 at minimum).
- [X] `plugin-clay/skills/idea/SKILL.md` — grep for `create-prd`, `clay-list`, `clay-sync` and update each.
- [X] `plugin-clay/skills/idea-research/SKILL.md` — same grep, same updates.
- [X] `plugin-clay/skills/project-naming/SKILL.md` — same grep, same updates.

### C5. Commit Phase C (FR-008)
- [X] `git add plugin-clay/ && git commit -m "refactor(clay): rename create-prd→new-product, clay-list→list, clay-sync→sync (FR-002, FR-005, FR-006, FR-007)"`.
- [X] Verify: `grep -r "create-prd\|clay-list\|clay-sync" plugin-clay/` returns zero hits.
- [X] Record friction notes in `specs/plugin-naming-consistency/agent-notes/impl-clay.md`.

---

## Phase S — shelf plugin renames (owner: impl-shelf)

### S1. Rename shelf skills (FR-005)
Run each as a git mv + frontmatter edit pair:
- [X] `git mv plugin-shelf/skills/shelf-create/ plugin-shelf/skills/create/` + edit `name: shelf-create` → `name: create`.
- [X] `git mv plugin-shelf/skills/shelf-feedback/ plugin-shelf/skills/feedback/` + edit `name: shelf-feedback` → `name: feedback`.
- [X] `git mv plugin-shelf/skills/shelf-release/ plugin-shelf/skills/release/` + edit `name: shelf-release` → `name: release`.
- [X] `git mv plugin-shelf/skills/shelf-repair/ plugin-shelf/skills/repair/` + edit `name: shelf-repair` → `name: repair`.
- [X] `git mv plugin-shelf/skills/shelf-status/ plugin-shelf/skills/status/` + edit `name: shelf-status` → `name: status`.
- [X] `git mv plugin-shelf/skills/shelf-sync/ plugin-shelf/skills/sync/` + edit `name: shelf-sync` → `name: sync`.
- [X] `git mv plugin-shelf/skills/shelf-update/ plugin-shelf/skills/update/` + edit `name: shelf-update` → `name: update`.

### S2. Rename shelf workflows (FR-006)
- [X] `git mv plugin-shelf/workflows/shelf-full-sync.json plugin-shelf/workflows/sync.json` + edit JSON `"name": "shelf-full-sync"` → `"name": "sync"`.
- [X] `git mv plugin-shelf/workflows/shelf-create.json plugin-shelf/workflows/create.json` + edit JSON `"name": "shelf-create"` → `"name": "create"`.
- [X] `git mv plugin-shelf/workflows/shelf-repair.json plugin-shelf/workflows/repair.json` + edit JSON `"name": "shelf-repair"` → `"name": "repair"`.
- [X] `propose-manifest-improvement.json` — unchanged (FR-006).
- [X] Update `plugin-shelf/.claude-plugin/plugin.json` `workflows` array. *(no-op: file has no workflows array — see agent-notes/impl-shelf.md)*

### S3. [P] Update shelf skill cross-references (FR-007)
Grep each renamed SKILL.md for old shelf-* names, replace:
- [X] `plugin-shelf/skills/create/SKILL.md` (was shelf-create).
- [X] `plugin-shelf/skills/feedback/SKILL.md` (was shelf-feedback).
- [X] `plugin-shelf/skills/release/SKILL.md` (was shelf-release).
- [X] `plugin-shelf/skills/repair/SKILL.md` (was shelf-repair).
- [X] `plugin-shelf/skills/status/SKILL.md` (was shelf-status).
- [X] `plugin-shelf/skills/sync/SKILL.md` (was shelf-sync).
- [X] `plugin-shelf/skills/update/SKILL.md` (was shelf-update).
- [X] `plugin-shelf/skills/propose-manifest-improvement/SKILL.md` — update refs to shelf-full-sync callers.

### S4. [P] Update shelf workflow internals (FR-007)
- [X] `plugin-shelf/workflows/sync.json` (was shelf-full-sync) — audit command steps for old workflow filenames or skill names.
- [X] `plugin-shelf/workflows/create.json`, `repair.json`, `propose-manifest-improvement.json` — same audit.

### S5. [P] Update shelf scripts and status labels (FR-007)
- [X] `plugin-shelf/status-labels.md` — grep for shelf-* and workflow filenames; replace.
- [X] `plugin-shelf/scripts/update-sync-manifest.sh` — audit. *(remaining refs are to `.shelf-sync.json` data file and `specs/shelf-sync-efficiency/` historical contract — both out of scope per rename tables)*
- [X] `plugin-shelf/scripts/compute-work-list.sh` — audit. *(only historical spec-path comment; out of scope)*
- [X] `plugin-shelf/scripts/generate-sync-summary.sh` — audit. *(updated OUT path from shelf-full-sync-summary.md to sync-summary.md to match workflow rename)*
- [X] `plugin-shelf/scripts/obsidian-snapshot-capture.sh`, `obsidian-snapshot-diff.sh` — audit. *(only historical spec-path comments; out of scope)*
- [X] `plugin-shelf/scripts/read-sync-manifest.sh` — audit. *(only `.shelf-sync.json` + historical spec-path; out of scope)*
- [X] `plugin-shelf/scripts/derive-proposal-slug.sh` — audit. *(no shelf-* refs)*

### S6. Commit Phase S (FR-008)
- [X] `git add plugin-shelf/ && git commit -m "refactor(shelf): drop shelf- prefix from skills and workflows (FR-005, FR-006, FR-007)"`. *(commit 0f566f8)*
- [X] Verify: `grep -rE "shelf-(create|feedback|release|repair|status|sync|update|full-sync)" plugin-shelf/` returns zero hits. *(Remaining expected hits are all in `plugin-shelf/docs/PRD.md` (historical PRD), `scripts/*.sh` comments pointing to real `specs/shelf-sync-efficiency/` spec dir and `.shelf-sync.json` data file, and one example string in `skills/sync/SKILL.md` referencing historical feature slug `shelf-sync-v2` — all out of scope per rename tables. See agent-notes/impl-shelf.md.)*
- [X] Record friction notes in `specs/plugin-naming-consistency/agent-notes/impl-shelf.md`.

---

## Phase TW — trim + wheel plugin renames (owner: impl-trim-wheel)

### TW1. Rename trim skills (FR-005)
- [ ] `git mv plugin-trim/skills/trim-design/ plugin-trim/skills/design/` + frontmatter.
- [ ] `git mv plugin-trim/skills/trim-diff/ plugin-trim/skills/diff/` + frontmatter.
- [ ] `git mv plugin-trim/skills/trim-edit/ plugin-trim/skills/edit/` + frontmatter.
- [ ] `git mv plugin-trim/skills/trim-flows/ plugin-trim/skills/flows/` + frontmatter.
- [ ] `git mv plugin-trim/skills/trim-init/ plugin-trim/skills/init/` + frontmatter.
- [ ] `git mv plugin-trim/skills/trim-library/ plugin-trim/skills/library/` + frontmatter.
- [ ] `git mv plugin-trim/skills/trim-pull/ plugin-trim/skills/pull/` + frontmatter.
- [ ] `git mv plugin-trim/skills/trim-push/ plugin-trim/skills/push/` + frontmatter.
- [ ] `git mv plugin-trim/skills/trim-redesign/ plugin-trim/skills/redesign/` + frontmatter.
- [ ] `git mv plugin-trim/skills/trim-verify/ plugin-trim/skills/verify/` + frontmatter.

### TW2. Rename trim workflows (FR-006)
- [ ] `git mv plugin-trim/workflows/trim-design.json plugin-trim/workflows/design.json` + `"name"` edit.
- [ ] `git mv plugin-trim/workflows/trim-diff.json plugin-trim/workflows/diff.json` + `"name"` edit.
- [ ] `git mv plugin-trim/workflows/trim-edit.json plugin-trim/workflows/edit.json` + `"name"` edit.
- [ ] `git mv plugin-trim/workflows/trim-library-sync.json plugin-trim/workflows/library-sync.json` + `"name"` edit.
- [ ] `git mv plugin-trim/workflows/trim-pull.json plugin-trim/workflows/pull.json` + `"name"` edit.
- [ ] `git mv plugin-trim/workflows/trim-push.json plugin-trim/workflows/push.json` + `"name"` edit.
- [ ] `git mv plugin-trim/workflows/trim-redesign.json plugin-trim/workflows/redesign.json` + `"name"` edit.
- [ ] `git mv plugin-trim/workflows/trim-verify.json plugin-trim/workflows/verify.json` + `"name"` edit.
- [ ] Update `plugin-trim/.claude-plugin/plugin.json` workflows array.

### TW3. [P] Update trim skill and workflow cross-references (FR-007)
- [ ] Grep `plugin-trim/skills/*/SKILL.md` for `trim-` prefixed names; replace with un-prefixed form.
- [ ] Grep `plugin-trim/workflows/*.json` for `trim-` prefixed names in `command` steps; replace.
- [ ] `plugin-trim/templates/trim-config.tpl` — audit for skill references.

### TW4. Rename wheel skills (FR-005)
- [ ] `git mv plugin-wheel/skills/wheel-create/ plugin-wheel/skills/create/` + frontmatter.
- [ ] `git mv plugin-wheel/skills/wheel-init/ plugin-wheel/skills/init/` + frontmatter.
- [ ] `git mv plugin-wheel/skills/wheel-list/ plugin-wheel/skills/list/` + frontmatter.
- [ ] `git mv plugin-wheel/skills/wheel-run/ plugin-wheel/skills/run/` + frontmatter.
- [ ] `git mv plugin-wheel/skills/wheel-status/ plugin-wheel/skills/status/` + frontmatter.
- [ ] `git mv plugin-wheel/skills/wheel-stop/ plugin-wheel/skills/stop/` + frontmatter.
- [ ] `git mv plugin-wheel/skills/wheel-test/ plugin-wheel/skills/test/` + frontmatter.

### TW5. [P] Update wheel skill and lib cross-references (FR-007)
- [ ] Grep `plugin-wheel/skills/*/SKILL.md` for `wheel-` prefixed names; replace.
- [ ] `plugin-wheel/lib/dispatch.sh`, `engine.sh`, `workflow.sh`, `state.sh`, `context.sh`, `lock.sh`, `guard.sh` — grep each for hardcoded skill or workflow names; replace.
- [ ] `plugin-wheel/hooks/block-state-write.sh` — audit.
- [ ] `plugin-wheel/bin/activate.sh`, `deactivate.sh`, `validate-workflow.sh` — audit.
- [ ] `plugin-wheel/skills/test/lib/runtime.sh` (was wheel-test) — audit; this is the wheel-test runner and references workflow filenames.

### TW6. Commit Phase TW (FR-008)
- [ ] `git add plugin-trim/ plugin-wheel/ && git commit -m "refactor(trim,wheel): drop plugin-prefix from skills and workflows (FR-005, FR-006, FR-007)"`.
- [ ] Verify: `grep -rE "trim-(design|diff|edit|flows|init|library|pull|push|redesign|verify)|wheel-(create|init|list|run|status|stop|test)" plugin-trim/ plugin-wheel/` returns zero hits except for the `trim-config.tpl` filename (which is a template file name, not a skill reference — leave as-is unless the template content itself has references).
- [ ] Record friction notes in `specs/plugin-naming-consistency/agent-notes/impl-trim-wheel.md`.

---

## Phase X — cross-cutting + grep gate (owner: auditor)

### X1. Update `CLAUDE.md` (FR-007)
- [ ] Quick Start section line 19: `/create-repo` → `/clay:create-repo`.
- [ ] Architecture tree line 56: remove `create-repo/` entry under kiln skills list.
- [ ] Available Commands section (lines ~185–210): remove `/create-repo`, `/debug-diagnose`, `/debug-fix` bullets; update any shelf/trim/wheel references to post-rename names.
- [ ] Active Technologies section: no changes needed (doesn't reference skill names).
- [ ] Grep CLAUDE.md for any old name not yet caught.

### X2. Update `plugin-kiln/scaffold/` (FR-007)
- [ ] `plugin-kiln/scaffold/CLAUDE.md` — apply same edits as Phase X1.
- [ ] `plugin-kiln/scaffold/docs/` — grep for any old names.
- [ ] `plugin-kiln/scaffold/specify-scripts/` — grep for any old names.

### X3. Handle top-level `workflows/` duplicates (FR-007)
- [ ] Determine whether top-level `workflows/shelf-full-sync.json` etc. are live (dispatched by something) or stale (dev-only artifacts).
- [ ] If live: rename in lockstep with plugin-shelf copies (already done in Phase S if same-named files got renamed).
  - `workflows/shelf-full-sync.json` → `workflows/sync.json` + `"name"` edit.
  - `workflows/shelf-create.json` → `workflows/create.json` + `"name"` edit.
  - `workflows/shelf-repair.json` → `workflows/repair.json` + `"name"` edit.
  - `workflows/report-issue-and-sync.json` → `workflows/report-issue.json` + `"name"` edit.
- [ ] `workflows/tests/shelf-full-sync.json` — check whether `plugin-wheel/skills/test/lib/runtime.sh` (was wheel-test) references this file by name. If so, either rename both in lockstep or keep the fixture name stable and note it in the spec as an exception.

### X4. Update `tests/` (FR-007)
- [ ] `tests/test-team-wait-agent-capture.sh` — replace `wheel-run` → `wheel:run` (or the post-rename form).
- [ ] `tests/unit/test-write-proposal-dispatch.sh` — replace old workflow/skill names.
- [ ] `tests/unit/test-validate-reflect-output.sh` — same.
- [ ] `tests/integration/out-of-scope.sh` — same.
- [ ] `tests/integration/hallucinated-current.sh` — same.
- [ ] `tests/integration/caller-wiring.sh` — same.
- [ ] `tests/integration/write-proposal.sh` — same.

### X5. Update `.shelf-sync.json` and top-level config files (FR-007)
- [ ] `.shelf-sync.json` — grep for old workflow filenames; replace.
- [ ] `.claude/agents/wheel-runner.md` — grep for `wheel-run`, `wheel-stop` etc.; replace.

### X6. Grep gate (SC-001)
- [ ] Run the gate command:
  ```bash
  grep -rE "kiln:create-repo|clay:create-prd|kiln:debug-diagnose|kiln:debug-fix|shelf:shelf-(sync|create|feedback|release|repair|status|update)|trim:trim-(design|diff|edit|flows|init|library|pull|push|redesign|verify)|wheel:wheel-(create|init|list|run|status|stop|test)|clay:clay-list|shelf-full-sync|report-issue-and-sync|report-mistake-and-sync" \
    --exclude-dir=.git \
    --exclude-dir=.wheel \
    --exclude-dir=.kiln \
    --exclude-dir=docs \
    --exclude-dir=specs \
    --exclude-dir=node_modules \
    .
  ```
- [ ] Expected: zero hits. If any hit, open the file, determine the correct post-rename name, update it, re-run the gate.
- [ ] Run a looser grep for bare old names (without `plugin:` prefix) to catch any missed cross-refs: `grep -rE "\b(shelf-sync|shelf-full-sync|trim-pull|wheel-run|clay-list|create-prd|report-issue-and-sync|report-mistake-and-sync|debug-diagnose|debug-fix)\b" --exclude-dir=.git --exclude-dir=.wheel --exclude-dir=.kiln --exclude-dir=docs --exclude-dir=specs .`
- [ ] Zero hits in live code. Accept hits only in `specs/plugin-naming-consistency/contracts/interfaces.md` and archived locations.

### X7. Smoke test (SC-002, SC-003, SC-005)
- [ ] Dispatch `/kiln:fix` on a mock issue; confirm diagnose→fix→verify flow still works without `/debug-diagnose` or `/debug-fix` skills.
- [ ] Dispatch `/shelf:sync` — confirm it loads.
- [ ] Dispatch `/wheel:list` — confirm it loads and enumerates workflows including new filenames.
- [ ] Dispatch `/wheel:run sync` (shelf sync workflow) — confirm it runs end-to-end.
- [ ] Dispatch `/kiln:report-issue` — confirm the renamed workflow (`report-issue.json`) executes.

### X8. Commit Phase X (FR-008)
- [ ] `git add CLAUDE.md plugin-kiln/scaffold/ workflows/ tests/ .shelf-sync.json .claude/ && git commit -m "refactor(docs,scaffold,tests): update cross-plugin references for naming consistency (FR-007)"`.
- [ ] Record friction notes in `specs/plugin-naming-consistency/agent-notes/auditor.md`.

---

## Task → FR mapping summary

| Task | FR |
|---|---|
| K1 | FR-001 |
| K2, K3 | FR-004 |
| K3 | FR-007 (block-list) |
| K4 | FR-006, FR-007 |
| K5, K6 | FR-001, FR-004, FR-007 |
| K7 | FR-008 |
| C1 | FR-002 |
| C2 | FR-005 |
| C3 | FR-006 |
| C4 | FR-007 |
| C5 | FR-008 |
| S1 | FR-005 |
| S2 | FR-006 |
| S3, S4, S5 | FR-007 |
| S6 | FR-008 |
| TW1, TW4 | FR-005 |
| TW2 | FR-006 |
| TW3, TW5 | FR-007 |
| TW6 | FR-008 |
| X1, X2, X3, X4, X5 | FR-007 |
| X6 | SC-001 (acceptance gate) |
| X7 | SC-002, SC-003, SC-005 (smoke test) |
| X8 | FR-008 |

FR-003, FR-009 are passive constraints — no dedicated tasks. FR-003 asserts what does NOT change (verified by absence from rename tables). FR-009 asserts no behavioral change — verified by X7 smoke test showing renamed skills still work.
