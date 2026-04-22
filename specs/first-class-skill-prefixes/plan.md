# Implementation Plan: First-Class Skill Prefix Convention

**Feature**: first-class-skill-prefixes
**Spec**: [spec.md](./spec.md)
**PRD**: [../../docs/features/2026-04-21-first-class-skill-prefixes/PRD.md](../../docs/features/2026-04-21-first-class-skill-prefixes/PRD.md)

## Technical Approach

This is a pure rename refactor. There is no new runtime code, no new data structures, and no new dependencies. The scope is:

1. Rename skill directories to `<plugin>-<action>`.
2. Update each renamed skill's frontmatter `name:` field to match its new directory name.
3. Rewrite every cross-reference that mentions an old skill name by its bare form.
4. Rename workflow JSONs whose filenames correspond to a renamed skill (FR-004).
5. Update `/kiln:next`'s allowed-commands whitelist (FR-005).
6. Update top-level docs — `CLAUDE.md`, `docs/PRD.md`, plugin `README.md`s (FR-006).
7. Bump the `pr` segment of `VERSION` and propagate to five plugin manifests plus `plugin-kiln/package.json` (FR-009).
8. Verify via a grep gate: zero live references to any old skill name outside the excluded paths (SC-001).

Per the PRD's `Absolute Musts`, this mirrors PR #121's structure wholesale: parallel-by-plugin agent teams, each implementer owning one plugin, auditor runs the cross-plugin sweep and grep gate at the end.

## Architecture — Work Partition

Five plugin-owner agents run in parallel; each owns exactly one `plugin-<p>/` subtree and the renames plus in-plugin cross-refs within it. A sixth auditor agent runs after all five finish: it performs the cross-plugin sweep, updates root-level docs, bumps the version, and creates the PR.

```
Phase K (impl-kiln)     Phase S (impl-shelf)    Phase C (impl-clay)
      │                       │                       │
Phase T (impl-trim)     Phase W (impl-wheel)
      │                       │
      └───────────────────────┴───────┐
                                      │
                              Phase X (auditor)
                              ├─ /kiln:next whitelist update
                              ├─ Cross-plugin sweep (CLAUDE.md, docs/, build-prd body refs)
                              ├─ Version bump + propagate
                              ├─ Grep gate (SC-001)
                              └─ PR creation
```

Rationale: PR #121 used the same partition and it worked. The per-plugin phases are touch-isolated — no two implementers edit the same directory — so they can run in parallel with no coordination overhead. The auditor phase is sequential because it touches shared files (`CLAUDE.md`, `docs/PRD.md`, `VERSION`, plugin manifests).

## Rename Table (COMPLETE — SINGLE SOURCE OF TRUTH)

This table maps every first-class skill directory to its new name. Already-prefixed skills and pipeline-internal kiln skills appear as explicit no-ops so the final state is unambiguous. **Any implementation that diverges from this table is a bug — update this table first if a rename must change.**

Legend:
- **NO-OP** = directory and frontmatter `name:` stay exactly as-is; no rename is performed.
- **RENAME** = directory is `mv`'d and frontmatter `name:` is rewritten.

### plugin-kiln (Phase K)

| Old directory | Old `name:` | New directory | New `name:` | Action |
|---|---|---|---|---|
| `plugin-kiln/skills/analyze` | `analyze` | `plugin-kiln/skills/kiln-analyze` | `kiln-analyze` | RENAME |
| `plugin-kiln/skills/analyze-issues` | `analyze-issues` | `plugin-kiln/skills/kiln-analyze-issues` | `kiln-analyze-issues` | RENAME |
| `plugin-kiln/skills/audit` | `audit` | `plugin-kiln/skills/audit` | `audit` | **NO-OP** (pipeline-internal) |
| `plugin-kiln/skills/build-prd` | `build-prd` | `plugin-kiln/skills/kiln-build-prd` | `kiln-build-prd` | RENAME |
| `plugin-kiln/skills/checklist` | `checklist` | `plugin-kiln/skills/kiln-checklist` | `kiln-checklist` | RENAME |
| `plugin-kiln/skills/clarify` | `clarify` | `plugin-kiln/skills/kiln-clarify` | `kiln-clarify` | RENAME |
| `plugin-kiln/skills/constitution` | `constitution` | `plugin-kiln/skills/kiln-constitution` | `kiln-constitution` | RENAME |
| `plugin-kiln/skills/coverage` | `coverage` | `plugin-kiln/skills/kiln-coverage` | `kiln-coverage` | RENAME |
| `plugin-kiln/skills/create-prd` | `create-prd` | `plugin-kiln/skills/kiln-create-prd` | `kiln-create-prd` | RENAME |
| `plugin-kiln/skills/fix` | `fix` | `plugin-kiln/skills/kiln-fix` | `kiln-fix` | RENAME |
| `plugin-kiln/skills/implement` | `implement` | `plugin-kiln/skills/implement` | `implement` | **NO-OP** (pipeline-internal) |
| `plugin-kiln/skills/init` | `init` | `plugin-kiln/skills/kiln-init` | `kiln-init` | RENAME |
| `plugin-kiln/skills/issue-to-prd` | `issue-to-prd` | `plugin-kiln/skills/kiln-issue-to-prd` | `kiln-issue-to-prd` | RENAME |
| `plugin-kiln/skills/kiln-cleanup` | `kiln-cleanup` | `plugin-kiln/skills/kiln-cleanup` | `kiln-cleanup` | **NO-OP** (already prefixed) |
| `plugin-kiln/skills/kiln-doctor` | `kiln-doctor` | `plugin-kiln/skills/kiln-doctor` | `kiln-doctor` | **NO-OP** (already prefixed) |
| `plugin-kiln/skills/mistake` | `mistake` | `plugin-kiln/skills/kiln-mistake` | `kiln-mistake` | RENAME |
| `plugin-kiln/skills/next` | `next` | `plugin-kiln/skills/kiln-next` | `kiln-next` | RENAME |
| `plugin-kiln/skills/plan` | `plan` | `plugin-kiln/skills/plan` | `plan` | **NO-OP** (pipeline-internal) |
| `plugin-kiln/skills/qa-audit` | `qa-audit` | `plugin-kiln/skills/kiln-qa-audit` | `kiln-qa-audit` | RENAME |
| `plugin-kiln/skills/qa-checkpoint` | `qa-checkpoint` | `plugin-kiln/skills/kiln-qa-checkpoint` | `kiln-qa-checkpoint` | RENAME |
| `plugin-kiln/skills/qa-final` | `qa-final` | `plugin-kiln/skills/kiln-qa-final` | `kiln-qa-final` | RENAME |
| `plugin-kiln/skills/qa-pass` | `qa-pass` | `plugin-kiln/skills/kiln-qa-pass` | `kiln-qa-pass` | RENAME |
| `plugin-kiln/skills/qa-pipeline` | `qa-pipeline` | `plugin-kiln/skills/kiln-qa-pipeline` | `kiln-qa-pipeline` | RENAME |
| `plugin-kiln/skills/qa-setup` | `qa-setup` | `plugin-kiln/skills/kiln-qa-setup` | `kiln-qa-setup` | RENAME |
| `plugin-kiln/skills/report-issue` | `report-issue` | `plugin-kiln/skills/kiln-report-issue` | `kiln-report-issue` | RENAME |
| `plugin-kiln/skills/reset-prd` | `reset-prd` | `plugin-kiln/skills/kiln-reset-prd` | `kiln-reset-prd` | RENAME |
| `plugin-kiln/skills/resume` | `resume` | `plugin-kiln/skills/kiln-resume` | `kiln-resume` | RENAME |
| `plugin-kiln/skills/roadmap` | `roadmap` | `plugin-kiln/skills/kiln-roadmap` | `kiln-roadmap` | RENAME |
| `plugin-kiln/skills/specify` | `specify` | `plugin-kiln/skills/specify` | `specify` | **NO-OP** (pipeline-internal) |
| `plugin-kiln/skills/tasks` | `tasks` | `plugin-kiln/skills/tasks` | `tasks` | **NO-OP** (pipeline-internal) |
| `plugin-kiln/skills/taskstoissues` | `taskstoissues` | `plugin-kiln/skills/kiln-taskstoissues` | `kiln-taskstoissues` | RENAME |
| `plugin-kiln/skills/todo` | `todo` | `plugin-kiln/skills/kiln-todo` | `kiln-todo` | RENAME |
| `plugin-kiln/skills/ux-evaluate` | `ux-evaluate` | `plugin-kiln/skills/kiln-ux-evaluate` | `kiln-ux-evaluate` | RENAME |
| `plugin-kiln/skills/version` | `version` | `plugin-kiln/skills/kiln-version` | `kiln-version` | RENAME |

**Note on `plugin-kiln/skills/ux-audit-scripts/`**: this is NOT a skill (no `SKILL.md`; it contains only helper `.js` files: `axe-inject.js`, `contrast-check.js`, `layout-check.js`). Out of scope — leave it alone.

### plugin-shelf (Phase S)

| Old directory | Old `name:` | New directory | New `name:` | Action |
|---|---|---|---|---|
| `plugin-shelf/skills/create` | `create` | `plugin-shelf/skills/shelf-create` | `shelf-create` | RENAME |
| `plugin-shelf/skills/feedback` | `feedback` | `plugin-shelf/skills/shelf-feedback` | `shelf-feedback` | RENAME |
| `plugin-shelf/skills/propose-manifest-improvement` | `propose-manifest-improvement` | `plugin-shelf/skills/shelf-propose-manifest-improvement` | `shelf-propose-manifest-improvement` | RENAME |
| `plugin-shelf/skills/release` | `release` | `plugin-shelf/skills/shelf-release` | `shelf-release` | RENAME |
| `plugin-shelf/skills/repair` | `repair` | `plugin-shelf/skills/shelf-repair` | `shelf-repair` | RENAME |
| `plugin-shelf/skills/status` | `status` | `plugin-shelf/skills/shelf-status` | `shelf-status` | RENAME |
| `plugin-shelf/skills/sync` | `sync` | `plugin-shelf/skills/shelf-sync` | `shelf-sync` | RENAME |
| `plugin-shelf/skills/update` | `update` | `plugin-shelf/skills/shelf-update` | `shelf-update` | RENAME |

### plugin-clay (Phase C)

| Old directory | Old `name:` | New directory | New `name:` | Action |
|---|---|---|---|---|
| `plugin-clay/skills/create-repo` | `create-repo` | `plugin-clay/skills/clay-create-repo` | `clay-create-repo` | RENAME |
| `plugin-clay/skills/idea` | `idea` | `plugin-clay/skills/clay-idea` | `clay-idea` | RENAME |
| `plugin-clay/skills/idea-research` | `idea-research` | `plugin-clay/skills/clay-idea-research` | `clay-idea-research` | RENAME |
| `plugin-clay/skills/list` | `list` | `plugin-clay/skills/clay-list` | `clay-list` | RENAME |
| `plugin-clay/skills/new-product` | `new-product` | `plugin-clay/skills/clay-new-product` | `clay-new-product` | RENAME |
| `plugin-clay/skills/project-naming` | `project-naming` | `plugin-clay/skills/clay-project-naming` | `clay-project-naming` | RENAME |

### plugin-trim (Phase T)

| Old directory | Old `name:` | New directory | New `name:` | Action |
|---|---|---|---|---|
| `plugin-trim/skills/design` | `design` | `plugin-trim/skills/trim-design` | `trim-design` | RENAME |
| `plugin-trim/skills/diff` | `diff` | `plugin-trim/skills/trim-diff` | `trim-diff` | RENAME |
| `plugin-trim/skills/edit` | `edit` | `plugin-trim/skills/trim-edit` | `trim-edit` | RENAME |
| `plugin-trim/skills/flows` | `flows` | `plugin-trim/skills/trim-flows` | `trim-flows` | RENAME |
| `plugin-trim/skills/init` | `init` | `plugin-trim/skills/trim-init` | `trim-init` | RENAME |
| `plugin-trim/skills/library` | `library` | `plugin-trim/skills/trim-library` | `trim-library` | RENAME |
| `plugin-trim/skills/pull` | `pull` | `plugin-trim/skills/trim-pull` | `trim-pull` | RENAME |
| `plugin-trim/skills/push` | `push` | `plugin-trim/skills/trim-push` | `trim-push` | RENAME |
| `plugin-trim/skills/redesign` | `redesign` | `plugin-trim/skills/trim-redesign` | `trim-redesign` | RENAME |
| `plugin-trim/skills/verify` | `verify` | `plugin-trim/skills/trim-verify` | `trim-verify` | RENAME |

### plugin-wheel (Phase W)

| Old directory | Old `name:` | New directory | New `name:` | Action |
|---|---|---|---|---|
| `plugin-wheel/skills/create` | `create` | `plugin-wheel/skills/wheel-create` | `wheel-create` | RENAME |
| `plugin-wheel/skills/init` | `init` | `plugin-wheel/skills/wheel-init` | `wheel-init` | RENAME |
| `plugin-wheel/skills/list` | `list` | `plugin-wheel/skills/wheel-list` | `wheel-list` | RENAME |
| `plugin-wheel/skills/run` | `run` | `plugin-wheel/skills/wheel-run` | `wheel-run` | RENAME |
| `plugin-wheel/skills/status` | `status` | `plugin-wheel/skills/wheel-status` | `wheel-status` | RENAME |
| `plugin-wheel/skills/stop` | `stop` | `plugin-wheel/skills/wheel-stop` | `wheel-stop` | RENAME |
| `plugin-wheel/skills/test` | `test` | `plugin-wheel/skills/wheel-test` | `wheel-test` | RENAME |

### Rename Count Summary

- plugin-kiln: 34 total; 29 RENAME, 5 NO-OP (`audit`, `implement`, `plan`, `specify`, `tasks` pipeline-internal + `kiln-cleanup`, `kiln-doctor` already-prefixed → actually 7 no-ops across 2 categories; RENAME = 27). **Correction**: 34 rows; 7 NO-OP (5 pipeline-internal + 2 already-prefixed); **27 RENAMEs**.
- plugin-shelf: 8 RENAMEs.
- plugin-clay: 6 RENAMEs.
- plugin-trim: 10 RENAMEs.
- plugin-wheel: 7 RENAMEs.
- **Grand total: 58 RENAMEs, 7 NO-OPs.**

## Workflow JSON Alignment (FR-004)

Workflow JSONs whose filenames correspond to a renamed skill MUST be renamed and every `activate_name` / workflow lookup updated. Workflow JSONs that do not correspond to a skill keep their current name.

### plugin-kiln/workflows/

| Old JSON | Corresponds to skill | New JSON |
|---|---|---|
| `plugin-kiln/workflows/mistake.json` | `kiln-mistake` (renamed from `mistake`) | `plugin-kiln/workflows/kiln-mistake.json` |
| `plugin-kiln/workflows/report-issue.json` | `kiln-report-issue` (renamed from `report-issue`) | `plugin-kiln/workflows/kiln-report-issue.json` |

### plugin-shelf/workflows/

| Old JSON | Corresponds to skill | New JSON |
|---|---|---|
| `plugin-shelf/workflows/create.json` | `shelf-create` | `plugin-shelf/workflows/shelf-create.json` |
| `plugin-shelf/workflows/propose-manifest-improvement.json` | `shelf-propose-manifest-improvement` | `plugin-shelf/workflows/shelf-propose-manifest-improvement.json` |
| `plugin-shelf/workflows/repair.json` | `shelf-repair` | `plugin-shelf/workflows/shelf-repair.json` |
| `plugin-shelf/workflows/sync.json` | `shelf-sync` | `plugin-shelf/workflows/shelf-sync.json` |

### plugin-clay/workflows/

| Old JSON | Corresponds to skill | New JSON |
|---|---|---|
| `plugin-clay/workflows/sync.json` | Does NOT correspond to a clay skill (there is no `clay-sync` skill; this is a plugin workflow used elsewhere) — implementer MUST verify this belief by inspecting the file and any references. If the file's workflow `name` field or activation matches a skill name, rename accordingly; otherwise KEEP. | (likely KEEP — verify) |

**Action for impl-clay**: open `plugin-clay/workflows/sync.json`, read its internal `name` field, grep for its activation, confirm it is not a skill-backed workflow, and either leave it alone (if confirmed) or rename to match the corresponding renamed skill name. Document the outcome in the per-phase commit message.

### plugin-trim/workflows/

| Old JSON | Corresponds to skill | New JSON |
|---|---|---|
| `plugin-trim/workflows/design.json` | `trim-design` | `plugin-trim/workflows/trim-design.json` |
| `plugin-trim/workflows/diff.json` | `trim-diff` | `plugin-trim/workflows/trim-diff.json` |
| `plugin-trim/workflows/edit.json` | `trim-edit` | `plugin-trim/workflows/trim-edit.json` |
| `plugin-trim/workflows/library-sync.json` | Does NOT correspond to a skill (there is no `trim-library-sync` skill — closest skill is `trim-library` which has a `sync` subcommand) | **KEEP as-is** |
| `plugin-trim/workflows/pull.json` | `trim-pull` | `plugin-trim/workflows/trim-pull.json` |
| `plugin-trim/workflows/push.json` | `trim-push` | `plugin-trim/workflows/trim-push.json` |
| `plugin-trim/workflows/redesign.json` | `trim-redesign` | `plugin-trim/workflows/trim-redesign.json` |
| `plugin-trim/workflows/verify.json` | `trim-verify` | `plugin-trim/workflows/trim-verify.json` |

### plugin-wheel/workflows/

| Old JSON | Corresponds to skill | New JSON |
|---|---|---|
| `plugin-wheel/workflows/example.json` | Does NOT correspond to a skill (it is an example / template) | **KEEP as-is** |

### Top-level workflows/ (in repo root)

| Old JSON | Notes |
|---|---|
| `workflows/create.json` | Top-level wheel workflow; NOT inside a plugin. Keep filename; inspect content for any references to renamed skills and update. |
| `workflows/repair.json` | Top-level wheel workflow; NOT inside a plugin. Keep filename; inspect content for any references to renamed skills and update. |
| `workflows/tests/**` | Test workflows; inspect contents for references to renamed skills and update. |

For all workflow JSONs that stay named the same but reference renamed skills in their `step` bodies (e.g., a command step that calls `/specify` or `/wheel:stop`), the references inside the JSON MUST be updated per FR-003.

## `/kiln:next` Whitelist Update (FR-005)

The `/kiln:next` skill (after rename, `/kiln:kiln-next`) owns the mapping between project state and suggested commands. Its allowed-commands whitelist MUST be updated so every first-class command appears in its new prefixed form.

Expected changes (implementer to verify against the current SKILL.md body):
- `/specify` → **stays bare** (pipeline-internal, not in first-class whitelist; it's in the blocklist)
- `/plan` → **stays bare** (same)
- `/tasks` → **stays bare** (same)
- `/implement` → **stays bare** (same)
- `/audit` → **stays bare** (same)
- `/build-prd` → `/kiln:kiln-build-prd`
- `/create-prd` → `/kiln:kiln-create-prd`
- `/fix` → `/kiln:kiln-fix`
- `/qa-pass`, `/qa-pipeline`, `/qa-final`, `/qa-setup`, `/qa-checkpoint` → prefixed with `kiln:kiln-`
- `/next`, `/resume`, `/todo`, `/roadmap`, `/report-issue`, `/mistake`, `/init`, `/reset-prd` → prefixed with `kiln:kiln-`
- `/analyze`, `/analyze-issues`, `/checklist`, `/clarify`, `/constitution`, `/coverage`, `/issue-to-prd`, `/taskstoissues`, `/version`, `/ux-evaluate` → prefixed with `kiln:kiln-`
- `/qa-audit` → `/kiln:kiln-qa-audit`

The blocklist (`/specify`, `/plan`, `/tasks`, `/implement`, `/audit`) mapped to the recommendation "use `/kiln:kiln-build-prd` instead" MUST remain intact.

## Cross-Plugin Sweep (Phase X)

The auditor is responsible for every file that lives OUTSIDE a single plugin's directory and references a first-class skill name.

### Files the auditor MUST update

1. **`CLAUDE.md`** — numerous command references. Every first-class command switches to its prefixed form; pipeline-internal commands stay bare.
2. **`docs/PRD.md`** — parent PRD. Audit for any command references.
3. **`docs/features/**/*.md`** — feature PRDs that live-reference commands. The PRD for THIS feature (`docs/features/2026-04-21-first-class-skill-prefixes/PRD.md`) references command names extensively as the subject of the rename — DO NOT rewrite its historical text; these are references to the pre-state.
4. **`README.md`** in the repo root (if present) — update any command references.
5. **`plugin-*/README.md`** (if present) — update any command references.
6. **`plugin-kiln/skills/build-prd/SKILL.md`** (which after rename becomes `plugin-kiln/skills/kiln-build-prd/SKILL.md`) — FR-008: internal command examples stay bare; first-class command references get prefixed. **This file is owned by Phase K's impl-kiln**, not Phase X — but auditor MUST verify FR-008 is satisfied as part of the grep gate.
7. **Scaffold files under `plugin-kiln/scaffold/`** (if present) — any template that references commands MUST be updated.
8. **`.specify/memory/constitution.md`** — audit for command references. The current constitution references `/speckit.specify` etc. (legacy), which is out of scope for this rename — but any live references to this-repo command names (`/kiln:specify`, `/specify`, etc.) are in scope for audit.
9. **Memory notes** under `/Users/ryansuematsu/.claude/projects/.../memory/` — **OUT OF SCOPE** (user-scoped state, not part of the repo).

### Version Bump (FR-009)

- Run `./scripts/version-bump.sh pr`. This bumps the `pr` segment of `VERSION` (currently `000.001.000.179`) and should auto-propagate (per CLAUDE.md's versioning section).
- Verify `VERSION` has the new value.
- Verify all five `plugin-*/.claude-plugin/plugin.json` files have the new `version` field.
- Verify `plugin-kiln/package.json` has the new `version` field.
- If the bump script does not propagate automatically to all targets, the auditor MUST update them manually.

**Important note on FR-009 scope**: The PRD says "root package.json" but there is no root `package.json` in this repo. The npm package manifest is `plugin-kiln/package.json`. The auditor MUST propagate the version there; no other "root package.json" exists to update.

## Grep Gate (SC-001)

After all phases complete, the auditor runs the hard verification gate. For each pre-rename first-class skill name in the rename table above, grep the repo for live references and confirm zero hits outside the excluded paths.

**Excluded paths** (historical / runtime / this-feature's own artifacts):
- `specs/` (historical spec artifacts from completed features)
- `.kiln/` (runtime caches, issue files, logs)
- `.wheel/` (runtime workflow state)
- `.shelf-sync.json` (runtime sync state)
- `docs/features/2026-04-21-first-class-skill-prefixes/` (this feature's own PRD references old names as the subject)
- `specs/first-class-skill-prefixes/` (this feature's own artifacts reference both old and new names)

**Expected allowlisted live hits** (per PRD "Absolute Musts" #1 — same pattern PR #121 used):
- Pipeline-internal skills (`specify`, `plan`, `tasks`, `implement`, `audit`) — these stay bare, so `grep` for them will (correctly) return many live hits. These are NOT dangling references.
- Words that also happen to be old skill names (e.g., `create`, `init`, `list`, `update`, `sync`, `status`, `stop`, `run`) will grep-collide with unrelated content. The auditor uses WORD-BOUNDARY or COMMAND-FORM searches (e.g., `grep -E '/(create|init|list) '` or `grep -E '/(shelf|wheel|trim|clay):(create|init|list|...)'`) to focus on live command references.

**Gate definition**: zero live hits matching a command-shaped reference to an old skill name outside the excluded paths.

## Implementation Constraints

- **Git-aware rename**: use `git mv` (not raw `mv`) so git tracks the rename and preserves history. Implementers SHOULD run `git mv plugin-<p>/skills/<old> plugin-<p>/skills/<new>`.
- **Frontmatter rewrite**: each renamed SKILL.md's `name:` frontmatter field MUST be updated to match its new directory name exactly.
- **Commit granularity**: each implementer phase is a single commit or a small sequence of commits scoped to one plugin. The auditor phase is a separate commit for the version bump and any cross-plugin updates. PR-at-end convention follows `/build-prd`.
- **No code written to `src/`**: this feature does not touch any `src/` directory. The 4-gate hooks that block `src/` edits are not relevant here.
- **No new test code required**: the PRD explicitly states this is a rename refactor with no new runtime behavior. The verification is the grep gate (SC-001) plus the post-merge pipeline smoke (SC-003). Per the constitution's 80% coverage gate: this applies to new/changed *code*, not to rename refactors of declarative configuration files. No new tests are required.

## Interface Contracts

Per the constitution's Principle VII, every exported function signature must be defined in `contracts/interfaces.md` before implementation. This feature has NO exported functions — it is a rename refactor of markdown, JSON, and directory names. The "interface" of this change is the rename table above.

See `contracts/interfaces.md` — it references this plan's rename table as the single source of truth.

## Phases Summary

| Phase | Owner | Scope | Parallel? |
|---|---|---|---|
| K | impl-kiln | All plugin-kiln renames + in-plugin cross-refs + workflow JSON alignment | Yes |
| S | impl-shelf | All plugin-shelf renames + in-plugin cross-refs + workflow JSON alignment | Yes |
| C | impl-clay | All plugin-clay renames + in-plugin cross-refs + verify `sync.json` | Yes |
| T | impl-trim | All plugin-trim renames + in-plugin cross-refs + workflow JSON alignment | Yes |
| W | impl-wheel | All plugin-wheel renames + in-plugin cross-refs | Yes |
| X | auditor | `/kiln:next` whitelist (inside plugin-kiln but touching a first-class skill surface), top-level docs, version bump, grep gate, PR | Sequential (runs after K–W) |

Phases K, S, C, T, W MUST run in parallel; Phase X runs sequentially after all five complete.

## Risks & Mitigations

- **Merge conflicts with open branches.** Any open branch that touches a SKILL.md or references a renamed command will conflict. Mitigation: merge/rebase outstanding branches before dispatching implementers. The auditor MUST check `git branch -a` for open build-* branches before PR creation.
- **Plugin cache staleness at consumer sites.** Known limitation, same as PR #121. Not a blocker.
- **Workflow JSON filename drift.** Some workflow JSONs might have internal `name` fields that differ from filenames. Implementers MUST read each JSON and align both filename AND internal `name` field when the skill correspondence is clear. Document ambiguous cases in the per-phase commit message.
- **`/kiln:next` ownership ambiguity.** The `/kiln:next` skill body lives inside `plugin-kiln/` so impl-kiln technically owns the file mechanically. But its whitelist content is cross-plugin — it references every first-class skill across all five plugins. Resolution: impl-kiln writes the mechanical rename; Phase X auditor updates the whitelist body content in a SEPARATE commit. Both agents touching the same file is an explicit coordination pattern; impl-kiln commits the file-rename-and-frontmatter change first, auditor commits the whitelist content update afterward.
