# Feature PRD: Kiln Rebrand, Infrastructure & QA Reliability

**Date**: 2026-03-31
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md) (template — standalone feature PRD)

## Background

The speckit-harness plugin has grown into a full-featured development orchestration tool, but its identity and internal infrastructure haven't kept pace. The "speckit-harness" name no longer reflects the scope of what the tool does — it's not just a spec kit or a test harness, it's a complete build pipeline with agents, workflows, QA, and debugging.

Simultaneously, the plugin lacks a dedicated directory structure in consumer projects for storing workflow definitions, agent outputs, QA artifacts, and automation state. These artifacts are scattered across ad-hoc locations (`docs/backlog/`, `qa-results/`, inline in specs). There's no way to validate or migrate this state as the plugin evolves.

Finally, a recurring reliability issue in QA pipeline runs — the qa-engineer agent evaluating stale builds — has caused wasted investigation time and unreliable findings.

This PRD addresses all four backlog items as a cohesive body of work: rebrand to "kiln", establish the `.kiln/` directory as the central artifact store, add a doctor/migration tool, and fix the QA stale-build problem.

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [Rename speckit-harness to kiln](../../backlog/2026-03-31-rename-to-kiln.md) | — | improvement | medium |
| 2 | [Create .kiln/ directory for workflows, QA, and automation artifacts](../../backlog/2026-03-31-dot-directory-for-storage.md) | — | feature-request | medium |
| 3 | [Add kiln doctor — manifest-based state validation and migration](../../backlog/2026-03-31-kiln-doctor-manifest.md) | — | feature-request | medium |
| 4 | [QA engineer must verify latest build before evaluating](../../backlog/2026-03-31-qa-version-verification.md) | — | friction | high |

## Problem Statement

**Identity**: The plugin is branded "speckit-harness" across npm, plugin.json, skill prefixes, documentation, and scaffold templates. This name is confusing for new users and doesn't convey what the tool actually does. Renaming to "kiln" — a tool that fires and hardens raw material into finished product — better represents the pipeline's purpose.

**Artifact sprawl**: Agent runs, QA results, workflow definitions, and issue tracking are scattered across multiple directories with no consistent structure. There's no single place to look for "what happened during the last build" or "what workflows are available." Consumer projects accumulate stale artifacts with no cleanup mechanism.

**Migration gap**: As the directory structure changes (e.g., `docs/backlog/` to `.kiln/issues/`), existing consumer projects have no way to detect they're out of date or migrate automatically. There's no manifest defining "correct state" and no doctor tool to diagnose and fix drift.

**QA reliability**: The qa-engineer agent starts testing without confirming the app reflects the latest code changes. This produces false findings (bugs already fixed) and missed issues (new code not tested), wasting implementer time on phantom bugs.

## Goals

- Rename the entire plugin from "speckit-harness" to "kiln" across all user-facing surfaces
- Establish `.kiln/` as the standard directory for workflows, agent outputs, QA artifacts, issues, and logs in consumer projects
- Provide a `kiln doctor` tool that validates project state against a manifest and migrates legacy paths
- Ensure the QA engineer agent always verifies it's testing the latest build before evaluating

## Non-Goals

- Replacing `.specify/` — the speckit memory/constitution directory is unchanged
- Replacing `specs/` — feature spec artifacts stay where they are
- Changing the core workflow (specify -> plan -> tasks -> implement -> audit)
- Building a GUI or dashboard for `.kiln/` contents
- Changing the versioning scheme

## Requirements

### Functional Requirements

**Rename (from: 2026-03-31-rename-to-kiln.md)**

- **FR-001**: Rename the npm package from `@yoshisada/speckit-harness` to `@yoshisada/kiln` in `plugin/package.json`
- **FR-002**: Update `plugin/.claude-plugin/plugin.json` name field to "kiln"
- **FR-003**: Rename all skill prefixes from `speckit-harness:` to `kiln:` in skill directory names and any namespace references
- **FR-004**: Rename internal skill names: `speckit-specify` -> `specify`, `speckit-plan` -> `plan`, `speckit-tasks` -> `tasks`, `speckit-implement` -> `implement`, `speckit-audit` -> `audit`, `speckit-constitution` -> `constitution`, `speckit-analyze` -> `analyze`, `speckit-coverage` -> `coverage`, `speckit-checklist` -> `checklist`, `speckit-clarify` -> `clarify`, `speckit-taskstoissues` -> `taskstoissues`
- **FR-005**: Update all references in CLAUDE.md, README, scaffold templates, and documentation to use "kiln" branding
- **FR-006**: Update `plugin/bin/init.mjs` to reference the new package name and any internal naming
- **FR-007**: Maintain backwards compatibility — if a consumer project still references `speckit-harness:` prefixed skills, provide a deprecation notice pointing to the new names

**`.kiln/` Directory (from: 2026-03-31-dot-directory-for-storage.md)**

- **FR-008**: Define the `.kiln/` directory structure with subdirectories: `workflows/`, `agents/`, `issues/`, `qa/`, `logs/`
- **FR-009**: Update `init.mjs` to scaffold the `.kiln/` directory structure in consumer projects
- **FR-010**: Route agent run outputs (logs, artifacts) into `.kiln/agents/` with per-run directories
- **FR-011**: Move issue/backlog tracking from `docs/backlog/` to `.kiln/issues/` — update `/report-issue` skill to write to the new location
- **FR-012**: Route QA artifacts from `/qa-pass`, `/qa-final`, `/qa-checkpoint` into `.kiln/qa/`
- **FR-013**: Route build/pipeline logs from `/build-prd` into `.kiln/logs/`
- **FR-014**: Configure `.gitignore` to exclude transient outputs (agent run logs, QA test runs) while tracking workflow definitions and issues
- **FR-015**: Define a workflow format specification that skills and agents can produce and consume from `.kiln/workflows/`

**Kiln Doctor (from: 2026-03-31-kiln-doctor-manifest.md)**

- **FR-016**: Define a manifest format (JSON) describing the expected `.kiln/` directory structure, required subdirectories, and file naming conventions
- **FR-017**: Create a `/kiln-doctor` skill that reads the manifest and compares current project state against it
- **FR-018**: Doctor diagnose mode: report missing directories, misplaced files, stale artifacts, and legacy paths that need migration (e.g., `docs/backlog/` -> `.kiln/issues/`, `qa-results/` -> `.kiln/qa/`)
- **FR-019**: Doctor fix mode: for each issue found, present the suggested fix to the user and apply it on confirmation — must be idempotent (safe to run repeatedly)
- **FR-020**: Map all known legacy paths to their `.kiln/` equivalents for automatic migration detection

**QA Build Verification (from: 2026-03-31-qa-version-verification.md)**

- **FR-021**: Add a pre-flight step to the qa-engineer agent: before any testing, read the version string from the app UI and compare against the VERSION file or latest git commit
- **FR-022**: If version mismatch detected: trigger a rebuild (run the project's build command), wait for completion, then re-check the version
- **FR-023**: If version still doesn't match after rebuild: warn the team lead and proceed with a disclaimer note in the QA report
- **FR-024**: Add the same version verification pre-flight to `/qa-pass` and `/ux-evaluate` skills

### Non-Functional Requirements

- **NFR-001**: The rename must be atomic from the user's perspective — no partial rename states where some references say "speckit" and others say "kiln"
- **NFR-002**: `.kiln/` directory creation must be idempotent — running init twice doesn't duplicate or corrupt
- **NFR-003**: Doctor must complete a full scan in under 10 seconds for typical consumer projects
- **NFR-004**: QA version check must add no more than 30 seconds to the pre-flight phase
- **NFR-005**: All changes must maintain backwards compatibility with existing consumer projects until they run `kiln doctor` to migrate

## User Stories

- As a **new user**, I want the plugin name "kiln" to clearly convey what it does so that I understand its purpose without reading documentation.
- As a **developer using kiln**, I want all agent outputs, QA results, and workflow definitions stored in `.kiln/` so that I have one place to look for automation artifacts.
- As a **developer upgrading** from speckit-harness, I want `kiln doctor` to detect my outdated directory structure and migrate it so that I don't have to manually reorganize files.
- As a **pipeline operator**, I want the QA engineer to verify it's testing the latest build so that I don't waste time investigating phantom bugs from stale builds.
- As a **developer**, I want to define reusable workflows in `.kiln/workflows/` so that recurring automation tasks can be executed on demand.

## Success Criteria

- All user-facing references say "kiln" — no remaining "speckit-harness" strings in plugin code, docs, or scaffold output
- Consumer projects scaffolded with `/init` have a properly structured `.kiln/` directory
- `kiln doctor` correctly identifies and migrates at least: `docs/backlog/` -> `.kiln/issues/`, `qa-results/` -> `.kiln/qa/`
- QA engineer agent never produces findings against a stale build — version verification runs before every evaluation
- Existing consumer projects can upgrade without manual intervention by running `kiln doctor`

## Tech Stack

- **Language**: JavaScript/Shell (consistent with existing plugin)
- **Package**: npm (`@yoshisada/kiln`)
- **Manifest**: JSON schema for `.kiln/` structure definition
- **Testing**: Pipeline validation via `/build-prd` on consumer projects

## Risks & Open Questions

- **npm package rename**: Does `@yoshisada/speckit-harness` need to be deprecated on npm, or can it be unpublished? Need to check npm policy.
- **Skill prefix migration**: Claude Code plugin system may cache old skill names. Need to verify how skill discovery handles renames.
- **Workflow format**: The workflow specification (FR-015) needs design work — what format enables both human authoring and agent generation? This may warrant its own spec phase.
- **Version detection**: FR-021 assumes the app displays a version string in the UI. Not all consumer projects will have this. Need a fallback strategy (e.g., check build output timestamp, git SHA in bundle).
- **Scope of rename**: Do we rename the GitHub repo (`ai-repo-template` -> `kiln`)? This PRD covers the plugin rename only, not the repo.
