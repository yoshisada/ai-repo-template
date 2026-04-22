# Feature Spec: First-Class Skill Prefix Convention

**Feature**: first-class-skill-prefixes
**Branch**: build/first-class-skill-prefixes-20260421
**PRD**: [docs/features/2026-04-21-first-class-skill-prefixes/PRD.md](../../docs/features/2026-04-21-first-class-skill-prefixes/PRD.md)
**Parent PRD**: [docs/PRD.md](../../docs/PRD.md)

## Overview

Rename every first-class (user-invokable) skill across all five plugins (`kiln`, `shelf`, `clay`, `trim`, `wheel`) so that both the skill directory name and the frontmatter `name:` field follow the `<plugin>-<action>` convention. This reverses the in-plugin prefix stripping from PR #121 (`cc19311`) for the plugins where it was applied (`wheel`, `shelf`, `trim`), and extends the convention to first-class skills that never carried a prefix (all of `clay`, plus several `kiln` skills like `report-issue`, `build-prd`, etc.).

Pipeline-internal kiln skills (`specify`, `plan`, `tasks`, `implement`, `audit`) are explicitly excluded. They are orchestrated internally by `/kiln:kiln-build-prd` and `/kiln:kiln-fix` and must retain their bare names so existing pipeline prompts keep working.

## User Stories

### US-001 — Grep-friendly skill names for the maintainer

**As** the plugin maintainer (Ryan / yoshisada),
**I want** every first-class skill directory and frontmatter name to be prefixed with its owning plugin,
**so that** a grep for `wheel-stop` or `shelf-sync` returns exactly the handful of files that reference that skill, instead of thousands of hits on ambiguous words like `stop`, `sync`, or `create`.

**Acceptance scenarios**:
1. **Given** the rename has landed, **when** I run `grep -r "wheel-stop" .` from the repo root, **then** every returned line is a live reference to the Wheel stop skill (no incidental matches on unrelated words).
2. **Given** I am editing any SKILL.md, agent file, workflow JSON, template, or doc that references a first-class skill, **when** I grep for the old bare name, **then** I get zero live hits outside of historical `specs/`, `.kiln/` caches, and runtime state files.

### US-002 — Predictable prefix across all plugins

**As** the plugin maintainer,
**when** I invoke a first-class command from muscle memory,
**I can predict** that the plugin-name prefix appears twice (once as the plugin namespace, once in the skill name): `/wheel:wheel-stop`, `/shelf:shelf-sync`, `/clay:clay-new-product`, `/kiln:kiln-build-prd`,
**so that** I don't have to remember per-plugin exceptions or which skills happened to already be prefixed.

**Acceptance scenarios**:
1. **Given** the rename has landed, **when** I list `plugin-*/skills/*/SKILL.md` and read the frontmatter `name:` field, **then** every first-class skill name matches `<plugin>-<action>`.
2. **Given** the rename has landed, **when** I check the five pipeline-internal kiln skills, **then** their frontmatter `name:` fields are still the bare forms (`specify`, `plan`, `tasks`, `implement`, `audit`).

### US-003 — Pipeline orchestration keeps working

**As** the `/kiln:kiln-build-prd` or `/kiln:kiln-fix` orchestrator,
**when** I dispatch to pipeline-internal skills via `/specify`, `/plan`, `/tasks`, `/implement`, `/audit`,
**then** the invocations resolve successfully without any rename,
**so that** existing pipeline prompts, agent briefs, and retrospective logs continue to work unchanged.

**Acceptance scenarios**:
1. **Given** the rename has landed, **when** I run `/kiln:kiln-build-prd` on a throwaway feature, **then** the specifier → implementer → auditor → retrospective chain completes without any "skill not found" errors for the internal `/specify`/`/plan`/`/tasks`/`/implement`/`/audit` calls.
2. **Given** the rename has landed, **when** I inspect `plugin-kiln/skills/build-prd/SKILL.md` for internal command references, **then** all five pipeline-internal commands appear in their bare form while all first-class command references use the new prefixed form.

## Functional Requirements

- **FR-001** Every first-class skill in `plugin-kiln/skills/`, `plugin-shelf/skills/`, `plugin-clay/skills/`, `plugin-trim/skills/`, and `plugin-wheel/skills/` MUST have a directory name matching `<plugin>-<action>` AND a frontmatter `name:` field matching `<plugin>-<action>`. The five pipeline-internal kiln skills (`specify`, `plan`, `tasks`, `implement`, `audit` under `plugin-kiln/skills/`) are explicitly excluded and MUST remain bare.
- **FR-002** The implementation plan MUST include an explicit rename table mapping every first-class skill directory to its new name. Already-prefixed skills (`kiln-cleanup`, `kiln-doctor`) MUST appear in the table as no-ops. The five pipeline-internal kiln skills MUST appear as explicit no-ops so the final state is unambiguous.
- **FR-003** Every internal cross-reference to a renamed skill MUST be updated wherever it appears: other SKILL.md files, `plugin-*/agents/*.md`, `plugin-*/workflows/*.json`, top-level `workflows/*.json`, `plugin-*/templates/`, `plugin-*/scripts/`, `plugin-*/hooks/`, `CLAUDE.md`, `docs/**/*.md`, and any in-flight `specs/**/*.md` / `.kiln/issues/*.md` that live-reference a renamed command. Dangling references are hard blockers.
- **FR-004** Where a workflow JSON filename corresponds to a renamed skill (e.g., `plugin-kiln/workflows/report-issue.json` corresponds to the `report-issue` skill), the workflow file MUST be renamed to match the new skill name and every `activate_name` / workflow lookup MUST be updated accordingly. Workflow JSONs that do NOT correspond to a skill (e.g., `library-sync.json`) keep their current name.
- **FR-005** The `/kiln:kiln-next` skill's allowed-commands whitelist MUST be updated so every first-class command appears in its new prefixed form. The blocklist MUST stay unchanged (`/specify`, `/plan`, `/tasks`, `/implement`, `/audit` remain blocked in favor of `/kiln:kiln-build-prd`).
- **FR-006** `docs/PRD.md`, `CLAUDE.md`, any `README.md` files in the plugin source repo, and `docs/features/**/*.md` that live-reference command names MUST be updated to the new prefixed forms.
- **FR-007** No legacy aliases, compatibility shims, or redirects MUST be shipped. The rename is a single-commit, single-PR cutover (same approach PR #121 used).
- **FR-008** Inside `plugin-kiln/skills/build-prd/SKILL.md`, every example/reference of an internal command MUST stay bare (`/specify`, `/plan`, `/tasks`, `/implement`, `/audit`). First-class commands referenced in the build-prd skill body MUST switch to the prefixed form.
- **FR-009** The rename PR MUST bump the `pr` segment of `VERSION` and propagate the new version to all five `plugin-*/.claude-plugin/plugin.json` files AND to `plugin-kiln/package.json`. (Note: there is no root `package.json`; the npm package manifest lives in `plugin-kiln/package.json`.)

## Success Criteria

- **SC-001 Zero dangling references.** `grep` for every pre-rename first-class skill name across the full repo (excluding `specs/`, `.kiln/`, `.wheel/`, `.shelf-sync.json`, and this feature's own artifacts) returns zero live hits after the rename commits land. Auditor verifies via a grep gate.
- **SC-002 All first-class skills prefixed.** A grep / listing of `plugin-*/skills/*/SKILL.md` shows every first-class skill's frontmatter `name:` field matches its directory name AND matches `<plugin>-<action>`. The five excluded pipeline-internal skills are explicitly confirmed unprefixed.
- **SC-003 Pipeline smoke.** A manual `/kiln:kiln-build-prd` run on a throwaway feature completes through specifier → implementer → auditor → retrospective without "skill not found" errors. (Same post-merge smoke requirement PR #121 had.)
- **SC-004 `/kiln:kiln-next` whitelist round-trip.** Invoking `/kiln:kiln-next` on a clean project emits suggestions using the new prefixed command forms with zero old-form recommendations.
- **SC-005 Version bump propagated.** `VERSION` has a bumped `pr` segment and every `plugin-*/.claude-plugin/plugin.json` plus `plugin-kiln/package.json` matches `VERSION` exactly.

## Out of Scope

- Renaming plugin directories (`plugin-kiln`, `plugin-shelf`, etc.).
- Renaming agents under `plugin-*/agents/`.
- Renaming hook scripts.
- Renaming workflow JSONs that do not correspond to a skill.
- Unprefixing any of the five pipeline-internal skills.
- User-facing docs outside the repo (marketplace listing, npm README beyond `plugin-kiln/package.json` metadata).
- Rewriting historical artifacts in `specs/` (completed specs) or `.kiln/issues/*.md` (historical suggestions).

## Constraints

- Tech stack: Markdown + JSON + Bash only. No new runtime dependencies, libraries, or tools.
- Hard cutover: no aliases, no shims, no redirects.
- Pipeline-internal skills (`specify`, `plan`, `tasks`, `implement`, `audit`) MUST remain bare. This is NON-NEGOTIABLE per PRD FR-001.
- Every task in the implementation plan MUST be marked `[X]` immediately after completion per constitution principle VIII.

## Dependencies

- PR #121 (`cc19311` — refactor(plugins): naming consistency (rename skills + workflows)) is the inverse of this change on the plugins it touched. Any in-flight branch that conflicts with PR #121's surface will likely conflict with this PR too.
- The memory note `feedback_skill_naming_prefixes.md` records the maintainer's preference for prefixed names and the grep-searchability reasoning.

## References

- PRD: `docs/features/2026-04-21-first-class-skill-prefixes/PRD.md`
- Prior PR (inverse): `cc19311` — `refactor(plugins): naming consistency (rename skills + workflows)`
- Constitution: `.specify/memory/constitution.md`
- Rename table: see `plan.md` (this spec's sister artifact)
