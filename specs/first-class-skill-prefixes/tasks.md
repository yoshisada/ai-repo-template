# Tasks: First-Class Skill Prefix Convention

**Spec**: [spec.md](./spec.md)
**Plan**: [plan.md](./plan.md)
**Rename table (single source of truth)**: [plan.md](./plan.md#rename-table-complete--single-source-of-truth)

---

## Phase K — plugin-kiln renames (owner: impl-kiln)

27 RENAMEs, 7 NO-OPs. All cross-references inside `plugin-kiln/` MUST be updated.

### Rename directories + update frontmatter

- [ ] **K-001** `git mv` plugin-kiln/skills/analyze → plugin-kiln/skills/kiln-analyze; update SKILL.md frontmatter `name: kiln-analyze`
- [ ] **K-002** `git mv` plugin-kiln/skills/analyze-issues → plugin-kiln/skills/kiln-analyze-issues; update frontmatter `name: kiln-analyze-issues`
- [ ] **K-003** `git mv` plugin-kiln/skills/build-prd → plugin-kiln/skills/kiln-build-prd; update frontmatter `name: kiln-build-prd`
- [ ] **K-004** `git mv` plugin-kiln/skills/checklist → plugin-kiln/skills/kiln-checklist; update frontmatter `name: kiln-checklist`
- [ ] **K-005** `git mv` plugin-kiln/skills/clarify → plugin-kiln/skills/kiln-clarify; update frontmatter `name: kiln-clarify`
- [ ] **K-006** `git mv` plugin-kiln/skills/constitution → plugin-kiln/skills/kiln-constitution; update frontmatter `name: kiln-constitution`
- [ ] **K-007** `git mv` plugin-kiln/skills/coverage → plugin-kiln/skills/kiln-coverage; update frontmatter `name: kiln-coverage`
- [ ] **K-008** `git mv` plugin-kiln/skills/create-prd → plugin-kiln/skills/kiln-create-prd; update frontmatter `name: kiln-create-prd`
- [ ] **K-009** `git mv` plugin-kiln/skills/fix → plugin-kiln/skills/kiln-fix; update frontmatter `name: kiln-fix`
- [ ] **K-010** `git mv` plugin-kiln/skills/init → plugin-kiln/skills/kiln-init; update frontmatter `name: kiln-init`
- [ ] **K-011** `git mv` plugin-kiln/skills/issue-to-prd → plugin-kiln/skills/kiln-issue-to-prd; update frontmatter `name: kiln-issue-to-prd`
- [ ] **K-012** `git mv` plugin-kiln/skills/mistake → plugin-kiln/skills/kiln-mistake; update frontmatter `name: kiln-mistake`
- [ ] **K-013** `git mv` plugin-kiln/skills/next → plugin-kiln/skills/kiln-next; update frontmatter `name: kiln-next`
- [ ] **K-014** `git mv` plugin-kiln/skills/qa-audit → plugin-kiln/skills/kiln-qa-audit; update frontmatter `name: kiln-qa-audit`
- [ ] **K-015** `git mv` plugin-kiln/skills/qa-checkpoint → plugin-kiln/skills/kiln-qa-checkpoint; update frontmatter `name: kiln-qa-checkpoint`
- [ ] **K-016** `git mv` plugin-kiln/skills/qa-final → plugin-kiln/skills/kiln-qa-final; update frontmatter `name: kiln-qa-final`
- [ ] **K-017** `git mv` plugin-kiln/skills/qa-pass → plugin-kiln/skills/kiln-qa-pass; update frontmatter `name: kiln-qa-pass`
- [ ] **K-018** `git mv` plugin-kiln/skills/qa-pipeline → plugin-kiln/skills/kiln-qa-pipeline; update frontmatter `name: kiln-qa-pipeline`
- [ ] **K-019** `git mv` plugin-kiln/skills/qa-setup → plugin-kiln/skills/kiln-qa-setup; update frontmatter `name: kiln-qa-setup`
- [ ] **K-020** `git mv` plugin-kiln/skills/report-issue → plugin-kiln/skills/kiln-report-issue; update frontmatter `name: kiln-report-issue`
- [ ] **K-021** `git mv` plugin-kiln/skills/reset-prd → plugin-kiln/skills/kiln-reset-prd; update frontmatter `name: kiln-reset-prd`
- [ ] **K-022** `git mv` plugin-kiln/skills/resume → plugin-kiln/skills/kiln-resume; update frontmatter `name: kiln-resume`
- [ ] **K-023** `git mv` plugin-kiln/skills/roadmap → plugin-kiln/skills/kiln-roadmap; update frontmatter `name: kiln-roadmap`
- [ ] **K-024** `git mv` plugin-kiln/skills/taskstoissues → plugin-kiln/skills/kiln-taskstoissues; update frontmatter `name: kiln-taskstoissues`
- [ ] **K-025** `git mv` plugin-kiln/skills/todo → plugin-kiln/skills/kiln-todo; update frontmatter `name: kiln-todo`
- [ ] **K-026** `git mv` plugin-kiln/skills/ux-evaluate → plugin-kiln/skills/kiln-ux-evaluate; update frontmatter `name: kiln-ux-evaluate`
- [ ] **K-027** `git mv` plugin-kiln/skills/version → plugin-kiln/skills/kiln-version; update frontmatter `name: kiln-version`

### No-ops (verify, do not change)

- [ ] **K-028** Verify plugin-kiln/skills/audit (name: `audit`) unchanged — pipeline-internal
- [ ] **K-029** Verify plugin-kiln/skills/implement (name: `implement`) unchanged — pipeline-internal
- [ ] **K-030** Verify plugin-kiln/skills/plan (name: `plan`) unchanged — pipeline-internal
- [ ] **K-031** Verify plugin-kiln/skills/specify (name: `specify`) unchanged — pipeline-internal
- [ ] **K-032** Verify plugin-kiln/skills/tasks (name: `tasks`) unchanged — pipeline-internal
- [ ] **K-033** Verify plugin-kiln/skills/kiln-cleanup (name: `kiln-cleanup`) unchanged — already prefixed
- [ ] **K-034** Verify plugin-kiln/skills/kiln-doctor (name: `kiln-doctor`) unchanged — already prefixed

### Workflow JSON alignment (FR-004)

- [ ] **K-035** `git mv` plugin-kiln/workflows/mistake.json → plugin-kiln/workflows/kiln-mistake.json; update internal `name`/`activate_name` fields to `kiln-mistake` if present
- [ ] **K-036** `git mv` plugin-kiln/workflows/report-issue.json → plugin-kiln/workflows/kiln-report-issue.json; update internal `name`/`activate_name` fields to `kiln-report-issue` if present

### In-plugin cross-reference sweep

- [ ] **K-037** Grep `plugin-kiln/` for every renamed skill's old bare name (e.g., `analyze`, `analyze-issues`, `build-prd`, `checklist`, `clarify`, `constitution`, `coverage`, `create-prd`, `fix`, `init`, `issue-to-prd`, `mistake`, `next`, `qa-audit`, `qa-checkpoint`, `qa-final`, `qa-pass`, `qa-pipeline`, `qa-setup`, `report-issue`, `reset-prd`, `resume`, `roadmap`, `taskstoissues`, `todo`, `ux-evaluate`, `version`) in command-shape (e.g., `/<name>`, `kiln:<name>`, `.claude-plugin` manifest, workflow JSON) and rewrite to new prefixed form. EXCEPTIONS: the five pipeline-internal names (`specify`, `plan`, `tasks`, `implement`, `audit`) STAY bare in every occurrence — do not rewrite these.
- [ ] **K-038** Update plugin-kiln/skills/kiln-build-prd/SKILL.md (FR-008): ensure every internal command reference (`/specify`, `/plan`, `/tasks`, `/implement`, `/audit`) stays bare AND every first-class command reference (`/create-prd` → `/kiln:kiln-create-prd`, `/fix` → `/kiln:kiln-fix`, etc.) is prefixed.
- [ ] **K-039** Grep `plugin-kiln/agents/` for references to old bare skill names in command-shape; update.
- [ ] **K-040** Grep `plugin-kiln/hooks/` for references to old bare skill names in command-shape; update.
- [ ] **K-041** Grep `plugin-kiln/templates/` for references to old bare skill names in command-shape; update.
- [ ] **K-042** Grep `plugin-kiln/scripts/` for references to old bare skill names in command-shape; update.
- [ ] **K-043** Grep `plugin-kiln/scaffold/` (if present) for references to old bare skill names in command-shape; update. (Scaffold templates are what consumers see — FR-006 surface.)

### Verification

- [ ] **K-044** Run `grep -rn -E '/(analyze|analyze-issues|build-prd|checklist|clarify|constitution|coverage|create-prd|fix|init|issue-to-prd|mistake|next|qa-audit|qa-checkpoint|qa-final|qa-pass|qa-pipeline|qa-setup|report-issue|reset-prd|resume|roadmap|taskstoissues|todo|ux-evaluate|version)\b' plugin-kiln/` — expect zero live hits (pipeline-internal bare forms are fine since they're not in this regex).
- [ ] **K-045** Commit Phase K with message `refactor(kiln): prefix first-class skills with kiln- (FR-001)`.

---

## Phase S — plugin-shelf renames (owner: impl-shelf)

8 RENAMEs, 0 NO-OPs.

### Rename directories + update frontmatter

- [X] **S-001** `git mv` plugin-shelf/skills/create → plugin-shelf/skills/shelf-create; update frontmatter `name: shelf-create`
- [X] **S-002** `git mv` plugin-shelf/skills/feedback → plugin-shelf/skills/shelf-feedback; update frontmatter `name: shelf-feedback`
- [X] **S-003** `git mv` plugin-shelf/skills/propose-manifest-improvement → plugin-shelf/skills/shelf-propose-manifest-improvement; update frontmatter `name: shelf-propose-manifest-improvement`
- [X] **S-004** `git mv` plugin-shelf/skills/release → plugin-shelf/skills/shelf-release; update frontmatter `name: shelf-release`
- [X] **S-005** `git mv` plugin-shelf/skills/repair → plugin-shelf/skills/shelf-repair; update frontmatter `name: shelf-repair`
- [X] **S-006** `git mv` plugin-shelf/skills/status → plugin-shelf/skills/shelf-status; update frontmatter `name: shelf-status`
- [X] **S-007** `git mv` plugin-shelf/skills/sync → plugin-shelf/skills/shelf-sync; update frontmatter `name: shelf-sync`
- [X] **S-008** `git mv` plugin-shelf/skills/update → plugin-shelf/skills/shelf-update; update frontmatter `name: shelf-update`

### Workflow JSON alignment (FR-004)

- [X] **S-009** `git mv` plugin-shelf/workflows/create.json → plugin-shelf/workflows/shelf-create.json; update internal `name`/`activate_name` to `shelf-create` if present
- [X] **S-010** `git mv` plugin-shelf/workflows/propose-manifest-improvement.json → plugin-shelf/workflows/shelf-propose-manifest-improvement.json; update internal fields
- [X] **S-011** `git mv` plugin-shelf/workflows/repair.json → plugin-shelf/workflows/shelf-repair.json; update internal fields
- [X] **S-012** `git mv` plugin-shelf/workflows/sync.json → plugin-shelf/workflows/shelf-sync.json; update internal fields

### In-plugin cross-reference sweep

- [X] **S-013** Grep `plugin-shelf/` for old bare skill names in command-shape (`create`, `feedback`, `propose-manifest-improvement`, `release`, `repair`, `status`, `sync`, `update`); rewrite to prefixed forms.
- [X] **S-014** Grep `plugin-shelf/agents/`, `plugin-shelf/hooks/`, `plugin-shelf/templates/`, `plugin-shelf/scripts/` (whichever exist) for old bare skill names in command-shape; update.

### Verification

- [X] **S-015** Run command-shape grep within `plugin-shelf/` for old bare skill names — expect zero live hits.
- [X] **S-016** Commit Phase S with message `refactor(shelf): prefix first-class skills with shelf- (FR-001)`.

---

## Phase C — plugin-clay renames (owner: impl-clay)

6 RENAMEs, 0 NO-OPs.

### Rename directories + update frontmatter

- [X] **C-001** `git mv` plugin-clay/skills/create-repo → plugin-clay/skills/clay-create-repo; update frontmatter `name: clay-create-repo`
- [X] **C-002** `git mv` plugin-clay/skills/idea → plugin-clay/skills/clay-idea; update frontmatter `name: clay-idea`
- [X] **C-003** `git mv` plugin-clay/skills/idea-research → plugin-clay/skills/clay-idea-research; update frontmatter `name: clay-idea-research`
- [X] **C-004** `git mv` plugin-clay/skills/list → plugin-clay/skills/clay-list; update frontmatter `name: clay-list`
- [X] **C-005** `git mv` plugin-clay/skills/new-product → plugin-clay/skills/clay-new-product; update frontmatter `name: clay-new-product`
- [X] **C-006** `git mv` plugin-clay/skills/project-naming → plugin-clay/skills/clay-project-naming; update frontmatter `name: clay-project-naming`

### Workflow JSON alignment (FR-004)

- [X] **C-007** Inspect `plugin-clay/workflows/sync.json`: read its internal `name` / `activate_name`, grep for references. If it corresponds to a clay skill, rename accordingly. If not (there is no `clay-sync` skill), KEEP filename as-is. Document the outcome in the commit message. [Verified: internal name="sync", no activate_name, no clay-sync skill exists — filename KEPT as sync.json.]

### In-plugin cross-reference sweep

- [X] **C-008** Grep `plugin-clay/` for old bare skill names in command-shape (`create-repo`, `idea`, `idea-research`, `list`, `new-product`, `project-naming`); rewrite to prefixed forms.
- [X] **C-009** Grep `plugin-clay/agents/`, `plugin-clay/hooks/`, `plugin-clay/templates/`, `plugin-clay/scripts/` (whichever exist) for old bare skill names in command-shape; update. [N/A: none of those directories exist in plugin-clay.]

### Verification

- [X] **C-010** Run command-shape grep within `plugin-clay/` for old bare skill names — expect zero live hits. [Verified zero hits.]
- [X] **C-011** Commit Phase C with message `refactor(clay): prefix first-class skills with clay- (FR-001)`.

---

## Phase T — plugin-trim renames (owner: impl-trim)

10 RENAMEs, 0 NO-OPs.

### Rename directories + update frontmatter

- [X] **T-001** `git mv` plugin-trim/skills/design → plugin-trim/skills/trim-design; update frontmatter `name: trim-design`
- [X] **T-002** `git mv` plugin-trim/skills/diff → plugin-trim/skills/trim-diff; update frontmatter `name: trim-diff`
- [X] **T-003** `git mv` plugin-trim/skills/edit → plugin-trim/skills/trim-edit; update frontmatter `name: trim-edit`
- [X] **T-004** `git mv` plugin-trim/skills/flows → plugin-trim/skills/trim-flows; update frontmatter `name: trim-flows`
- [X] **T-005** `git mv` plugin-trim/skills/init → plugin-trim/skills/trim-init; update frontmatter `name: trim-init`
- [X] **T-006** `git mv` plugin-trim/skills/library → plugin-trim/skills/trim-library; update frontmatter `name: trim-library`
- [X] **T-007** `git mv` plugin-trim/skills/pull → plugin-trim/skills/trim-pull; update frontmatter `name: trim-pull`
- [X] **T-008** `git mv` plugin-trim/skills/push → plugin-trim/skills/trim-push; update frontmatter `name: trim-push`
- [X] **T-009** `git mv` plugin-trim/skills/redesign → plugin-trim/skills/trim-redesign; update frontmatter `name: trim-redesign`
- [X] **T-010** `git mv` plugin-trim/skills/verify → plugin-trim/skills/trim-verify; update frontmatter `name: trim-verify`

### Workflow JSON alignment (FR-004)

- [X] **T-011** `git mv` plugin-trim/workflows/design.json → plugin-trim/workflows/trim-design.json; update internal fields
- [X] **T-012** `git mv` plugin-trim/workflows/diff.json → plugin-trim/workflows/trim-diff.json; update internal fields
- [X] **T-013** `git mv` plugin-trim/workflows/edit.json → plugin-trim/workflows/trim-edit.json; update internal fields
- [X] **T-014** `git mv` plugin-trim/workflows/pull.json → plugin-trim/workflows/trim-pull.json; update internal fields
- [X] **T-015** `git mv` plugin-trim/workflows/push.json → plugin-trim/workflows/trim-push.json; update internal fields
- [X] **T-016** `git mv` plugin-trim/workflows/redesign.json → plugin-trim/workflows/trim-redesign.json; update internal fields
- [X] **T-017** `git mv` plugin-trim/workflows/verify.json → plugin-trim/workflows/trim-verify.json; update internal fields
- [X] **T-018** Leave `plugin-trim/workflows/library-sync.json` as-is (not a skill correspondence). Verify belief by reading the file and confirming.

### In-plugin cross-reference sweep

- [X] **T-019** Grep `plugin-trim/` for old bare skill names in command-shape (`design`, `diff`, `edit`, `flows`, `init`, `library`, `pull`, `push`, `redesign`, `verify`); rewrite to prefixed forms.
- [X] **T-020** Grep `plugin-trim/agents/`, `plugin-trim/hooks/`, `plugin-trim/templates/`, `plugin-trim/scripts/` (whichever exist) for old bare skill names in command-shape; update.

### Verification

- [X] **T-021** Run command-shape grep within `plugin-trim/` for old bare skill names — expect zero live hits.
- [X] **T-022** Commit Phase T with message `refactor(trim): prefix first-class skills with trim- (FR-001)`.

---

## Phase W — plugin-wheel renames (owner: impl-wheel)

7 RENAMEs, 0 NO-OPs.

### Rename directories + update frontmatter

- [X] **W-001** `git mv` plugin-wheel/skills/create → plugin-wheel/skills/wheel-create; update frontmatter `name: wheel-create`
- [X] **W-002** `git mv` plugin-wheel/skills/init → plugin-wheel/skills/wheel-init; update frontmatter `name: wheel-init`
- [X] **W-003** `git mv` plugin-wheel/skills/list → plugin-wheel/skills/wheel-list; update frontmatter `name: wheel-list`
- [X] **W-004** `git mv` plugin-wheel/skills/run → plugin-wheel/skills/wheel-run; update frontmatter `name: wheel-run`
- [X] **W-005** `git mv` plugin-wheel/skills/status → plugin-wheel/skills/wheel-status; update frontmatter `name: wheel-status`
- [X] **W-006** `git mv` plugin-wheel/skills/stop → plugin-wheel/skills/wheel-stop; update frontmatter `name: wheel-stop`
- [X] **W-007** `git mv` plugin-wheel/skills/test → plugin-wheel/skills/wheel-test; update frontmatter `name: wheel-test`

### Workflow JSON alignment (FR-004)

- [X] **W-008** Leave `plugin-wheel/workflows/example.json` as-is (not a skill correspondence; it is a template/example).

### In-plugin cross-reference sweep

- [X] **W-009** Grep `plugin-wheel/` for old bare skill names in command-shape (`create`, `init`, `list`, `run`, `status`, `stop`, `test`); rewrite to prefixed forms. **IMPORTANT**: because words like `run`, `status`, `stop`, `init`, `list`, `create`, `test` collide with ordinary English and with unrelated code, use strict command-shape regexes (e.g., `/wheel:run`, `wheel:status`, `activate_name: "run"`, etc.) — do NOT sweep bare-word matches. Expect the collision surface to be larger than for other plugins; budget more time.
- [X] **W-010** Grep `plugin-wheel/agents/`, `plugin-wheel/hooks/`, `plugin-wheel/templates/`, `plugin-wheel/scripts/`, `plugin-wheel/lib/` (whichever exist) for old bare skill names in command-shape; update.

### Verification

- [X] **W-011** Run command-shape grep within `plugin-wheel/` for old bare skill names — expect zero live hits.
- [X] **W-012** Commit Phase W with message `refactor(wheel): prefix first-class skills with wheel- (FR-001)`.

---

## Phase X — Auditor (owner: auditor)

Runs SEQUENTIALLY after Phases K, S, C, T, W complete.

### `/kiln:next` whitelist update (FR-005)

- [ ] **X-001** Open `plugin-kiln/skills/kiln-next/SKILL.md` (renamed in Phase K). Find the allowed-commands whitelist section.
- [ ] **X-002** Rewrite every first-class command in the whitelist to its prefixed form (full list in plan.md § "`/kiln:next` Whitelist Update (FR-005)"). Include `shelf:shelf-*`, `wheel:wheel-*`, `clay:clay-*`, `trim:trim-*`, and `kiln:kiln-*` recommendations.
- [ ] **X-003** Verify the blocklist (`/specify`, `/plan`, `/tasks`, `/implement`, `/audit` → recommend `/kiln:kiln-build-prd` instead) is intact. Update the recommendation target to `/kiln:kiln-build-prd`.

### Cross-plugin sweep (FR-003, FR-006, FR-008)

- [ ] **X-004** Update `CLAUDE.md` — rewrite every first-class command reference to prefixed form. Pipeline-internal commands stay bare. Watch for the Available Commands section, the Mandatory Workflow section, and Recent Changes.
- [ ] **X-005** Update `docs/PRD.md` if it contains live command references.
- [ ] **X-006** Update in-flight `docs/features/**/*.md` files that live-reference commands (EXCEPT the PRD for this feature itself, whose text references old names as the subject of the rename — leave its historical text intact). Read each doc and decide per-file.
- [ ] **X-007** Update `README.md` in repo root (if present) and `plugin-*/README.md` (if present).
- [ ] **X-008** Audit `.specify/memory/constitution.md` for live command references. (Current text references `/speckit.*` legacy commands, which are out of scope — but any `/kiln:*` or `/<skill>` references MUST be updated.)
- [ ] **X-009** Verify FR-008 in `plugin-kiln/skills/kiln-build-prd/SKILL.md`: internal commands stay bare, first-class commands are prefixed. Spot-check by reading the file. If impl-kiln missed anything, fix it.

### Version bump (FR-009)

- [ ] **X-010** Run `./scripts/version-bump.sh pr` from repo root.
- [ ] **X-011** Read `VERSION` and confirm the `pr` segment was incremented (e.g., `000.001.000.179` → `000.001.001.000` or similar — verify the bump script's exact behavior).
- [ ] **X-012** Verify all five `plugin-*/.claude-plugin/plugin.json` files have the new `version` field. If the bump script did not propagate automatically, update them manually.
- [ ] **X-013** Verify `plugin-kiln/package.json` has the new `version` field. (PRD says "root package.json"; there is no root package.json — the npm manifest is `plugin-kiln/package.json`.)

### Grep gate (SC-001)

- [ ] **X-014** For each pre-rename first-class skill name listed in plan.md's rename table, run a command-shape grep across the full repo (excluding `specs/`, `.kiln/`, `.wheel/`, `.shelf-sync.json`, `docs/features/2026-04-21-first-class-skill-prefixes/`). Expect zero live hits.
  - Example invocation (iterate per old name): `grep -rnE '(/|:)(analyze|analyze-issues|build-prd|...) ' --exclude-dir=specs --exclude-dir=.kiln --exclude-dir=.wheel .`
  - Pipeline-internal bare forms (`specify`, `plan`, `tasks`, `implement`, `audit`) WILL return many live hits — these are expected and correct; they are NOT in the rename table.
  - Skills already prefixed (`kiln-cleanup`, `kiln-doctor`) are unchanged; their references are fine.
- [ ] **X-015** For any grep hits that ARE dangling references (not explicitly allowlisted above), fix them in a follow-up commit before PR.

### Final verification + PR

- [ ] **X-016** Run `ls plugin-*/skills/*/` and confirm every directory name matches `<plugin>-<action>` OR is one of the five pipeline-internal kiln skills (`audit`, `implement`, `plan`, `specify`, `tasks`). (SC-002 mechanical check.)
- [ ] **X-017** Run a batch frontmatter read across `plugin-*/skills/*/SKILL.md` and confirm every frontmatter `name:` field matches its directory name exactly.
- [ ] **X-018** Commit Phase X with message `chore: cross-plugin sweep + version bump for first-class-skill-prefixes (FR-005, FR-006, FR-009)`.
- [ ] **X-019** Create PR via `gh pr create` with title `refactor: prefix first-class skills across all plugins`. Body MUST include: (a) summary of rename count per plugin, (b) the rename table reference, (c) pipeline-internal exclusion note, (d) consumer-side breaking-change note ("muscle memory: `/wheel:stop` → `/wheel:wheel-stop`, `/shelf:sync` → `/shelf:shelf-sync`, etc."), (e) SC-003 post-merge smoke requirement note.

---

## Phase Completion Criteria

- **Phase K complete when**: all K-001 through K-045 are `[X]` and the phase commit is on `build/first-class-skill-prefixes-20260421`.
- **Phase S complete when**: S-001 through S-016 are `[X]` and committed.
- **Phase C complete when**: C-001 through C-011 are `[X]` and committed.
- **Phase T complete when**: T-001 through T-022 are `[X]` and committed.
- **Phase W complete when**: W-001 through W-012 are `[X]` and committed.
- **Phase X complete when**: X-001 through X-019 are `[X]`, PR is open, grep gate is green, and version bump is propagated.

## Notes for Implementers

- Use **`git mv`**, not raw `mv`, so git tracks the rename and preserves history.
- Mark each task `[X]` **immediately** after completion per constitution principle VIII. No batching.
- Commit after each phase, not at the very end.
- If a rename surfaces a reference you can't resolve, stop and flag it to the team lead rather than guessing. A dangling reference is a hard blocker for SC-001.
- The memory note `feedback_skill_naming_prefixes.md` documents the maintainer's reasoning (grep searchability). If you're tempted to leave a bare name for "ergonomics" — don't. The whole point of this PR is searchability over brevity.
