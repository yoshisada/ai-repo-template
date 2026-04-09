# Feature PRD: Shelf Skills Polish

**Date**: 2026-04-08
**Status**: Draft

## Background

The shelf plugin's `shelf-create` skill has accumulated several quality issues since its initial implementation. It doesn't follow its own Obsidian templates consistently, guesses directory paths inefficiently, ignores existing project state when scaffolding, and uses inconsistent status labels across skills. Additionally, the `shelf-full-sync` workflow lacks a summary step, leaving users without a consolidated view of what changed.

These are all friction points discovered through daily use of the shelf plugin across multiple projects.

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [shelf-create not following Obsidian template; add repair function](.kiln/issues/2026-04-08-shelf-create-template-compliance.md) | — | bug | high |
| 2 | [shelf-create should start at vault root when finding project directory](.kiln/issues/2026-04-08-shelf-create-root-path-lookup.md) | — | friction | medium |
| 3 | [shelf-create should assess project progress holistically](.kiln/issues/2026-04-08-shelf-create-holistic-progress.md) | — | improvement | medium |
| 4 | [Unify project status labels across shelf skills](.kiln/issues/2026-04-08-unify-project-status-labels.md) | — | friction | medium |
| 5 | [Add summary step to shelf-full-sync workflow](.kiln/issues/2026-04-08-shelf-full-sync-summary-step.md) | — | improvement | low |

## Problem Statement

The shelf plugin's project scaffolding and sync workflows have inconsistencies that erode trust in the Obsidian dashboard as a reliable project tracking surface. `shelf-create` produces dashboards that don't match the template, wastes MCP calls on path guessing, and creates blank progress for already-developed projects. Different shelf skills use different status labels for the same project state. The sync workflow runs silently with no consolidated output.

These issues affect every project onboarded to shelf and compound across sessions.

## Goals

- Rewrite `shelf-create` as a wheel workflow — deterministic, step-by-step, with command steps for data gathering and agent steps for MCP operations
- Implement `shelf-repair` as a wheel workflow that re-templates existing projects
- All shelf multi-step operations should be wheel workflows, not monolithic skills
- All shelf skills use a single canonical set of project status labels
- `shelf-full-sync` produces a human-readable summary of all sync actions

## Non-Goals

- Redesigning the Obsidian template structure itself (that's a separate concern)
- Changing the MCP protocol or Obsidian plugin API
- Converting simple single-step skills (shelf-status, shelf-feedback) to workflows

## Architecture: Wheel Workflows First

The key architectural decision for this PRD is: **shelf operations that involve multiple steps MUST be implemented as wheel workflows**, not as monolithic skill instructions. This matches the pattern established by `shelf-full-sync` and `report-issue-and-sync`.

Benefits:
- **Deterministic step ordering** — command steps gather data, agent steps act on it
- **Hook-driven progression** — the Stop hook advances between agent steps, preventing context loss on long operations
- **Composability** — workflows can reference each other (e.g., `shelf-create` can compose `shelf-full-sync` as a final step)
- **Observability** — each step writes to `.wheel/outputs/`, creating an audit trail
- **Resumability** — if a workflow fails mid-way, the state file shows exactly where it stopped

### Workflow Design Pattern

Each workflow should follow this structure:
1. **Command steps first** — gather all repo state, read configs, detect tech stack (cheap, deterministic, no MCP)
2. **Agent steps next** — use gathered context to make MCP calls to Obsidian (expensive, requires judgment)
3. **Summary step last** — read all prior outputs and produce a consolidated report

### New Workflows

| Workflow | Plugin | Steps | Purpose |
|----------|--------|-------|---------|
| `shelf-create` | shelf | ~8 | Scaffold a new project in Obsidian |
| `shelf-repair` | shelf | ~6 | Re-apply templates to existing project |

### Existing Workflows (to be updated)

| Workflow | Plugin | Change |
|----------|--------|--------|
| `shelf-full-sync` | shelf | Add summary step (FR-011/FR-012) |

## Requirements

### Functional Requirements

#### shelf-create workflow

**FR-001** (from: shelf-create-template-compliance.md): Rewrite `shelf-create` as a wheel workflow in `plugin-shelf/workflows/shelf-create.json`. The workflow MUST have command steps that gather repo state and agent steps that create Obsidian notes via MCP.

**FR-002** (from: shelf-create-template-compliance.md): The workflow MUST read the shelf plugin's template files (from `plugin-shelf/templates/`) and produce dashboard, about, and directory structure that exactly matches the template. Templates are the single source of truth.

**FR-003** (from: shelf-create-root-path-lookup.md): The workflow's directory resolution step MUST begin from the vault root using `mcp__obsidian-projects__list_files({ directory: "/" })` and navigate to the configured base_path. No path guessing.

**FR-004** (from: shelf-create-root-path-lookup.md): If the configured base_path doesn't exist, the workflow MUST create it rather than failing silently or guessing alternatives.

**FR-005** (from: shelf-create-holistic-progress.md): Include a command step that inspects the repo for progress signals: specs/ directory (count of spec.md files), code directories (src/, lib/, plugin-*), test files, VERSION file, git commit count, open issues count, and .kiln/ artifacts.

**FR-006** (from: shelf-create-holistic-progress.md): The agent step that creates the dashboard MUST use detected signals to populate initial status (e.g., `active` if code exists, `idea` if only PRDs exist), next_step, and an initial progress entry summarizing what was found.

**FR-007** (from: shelf-create-template-compliance.md): The `shelf-create` skill MUST delegate to `/wheel-run shelf:shelf-create` — the skill becomes a thin wrapper that validates input and launches the workflow.

#### shelf-repair workflow

**FR-008** (from: shelf-create-template-compliance.md): Create a `shelf-repair` wheel workflow in `plugin-shelf/workflows/shelf-repair.json` that re-applies the current template to an existing project's Obsidian notes.

**FR-009** (from: shelf-create-template-compliance.md): `shelf-repair` MUST preserve user-written content (Feedback section, Human Needed items, progress entries, Feedback Log) while updating structure and formatting to match the current template.

**FR-010** (from: shelf-create-template-compliance.md): `shelf-repair` MUST include a diff/preview step that reports what it will change before applying. The agent step reads current dashboard, compares to template, and writes a change report to `.wheel/outputs/`.

**FR-011** (from: unify-project-status-labels.md): `shelf-repair` MUST normalize any non-canonical status labels found in existing dashboards to their closest canonical equivalent.

#### Canonical status labels

**FR-012** (from: unify-project-status-labels.md): Define a canonical set of project status values in `plugin-shelf/status-labels.md`: `idea`, `active`, `paused`, `blocked`, `completed`, `archived`. This file is the single source of truth.

**FR-013** (from: unify-project-status-labels.md): `shelf-create`, `shelf-update`, `shelf-status`, `shelf-sync`, and `shelf-repair` MUST all reference the canonical status list and reject or warn on non-canonical values.

#### shelf-full-sync summary

**FR-014** (from: shelf-full-sync-summary-step.md): Add a final `command` step to the `shelf-full-sync` workflow that reads `.wheel/outputs/sync-issues-results.md`, `.wheel/outputs/sync-docs-results.md`, `.wheel/outputs/update-tags-results.md`, and `.wheel/outputs/push-progress-result.md` and produces a consolidated summary.

**FR-015** (from: shelf-full-sync-summary-step.md): The summary MUST include counts for: issues created/updated/closed/skipped, docs created/updated/skipped, tags added/removed/unchanged, and whether the progress entry was appended. Output to `.wheel/outputs/shelf-full-sync-summary.md`.

### Non-Functional Requirements

**NFR-001**: `shelf-create` workflow should complete in ≤10 MCP calls for a standard project scaffold (down from current ~12-15 with path guessing).

**NFR-002**: `shelf-repair` must be idempotent — running it twice produces the same result as running it once.

**NFR-003**: The canonical status list must be easy to extend without code changes across multiple skills (single source of truth file).

**NFR-004**: All new workflows MUST follow the command-first/agent-second/summary-last pattern established by `shelf-full-sync`.

## User Stories

**US-001**: As a developer onboarding an existing project to shelf, I want the dashboard to reflect my project's actual progress so I don't have to manually fill in status and milestones.

**US-002**: As a developer using shelf across multiple projects, I want consistent status labels so I can filter and compare projects reliably in Obsidian.

**US-003**: As a developer who updates the shelf plugin, I want to re-apply templates to existing projects so they stay current with the latest structure.

**US-004**: As a developer running shelf-full-sync, I want a quick summary of what changed so I don't have to dig through individual output files.

**US-005**: As a developer, I want shelf operations to be wheel workflows so I can see exactly which step failed, resume from where it stopped, and compose operations together.

## Success Criteria

- `shelf-create` is a wheel workflow, not a monolithic skill
- `shelf-create` output matches the template for all note types
- `shelf-repair` exists as a wheel workflow and can fix a pre-existing dashboard without losing user content
- `shelf-create` populates initial status and progress based on repo state
- All shelf skills use the same status vocabulary — no `in progress` vs `active` inconsistency
- `shelf-full-sync` prints a summary at completion with action counts
- MCP call count for `shelf-create` reduced to ≤10

## Tech Stack

- Markdown (skill definitions) + Bash (inline shell commands in skills)
- Obsidian MCP tools (`mcp__obsidian-projects__*`)
- Wheel workflow engine (`plugin-wheel/`) — workflows in `plugin-shelf/workflows/`
- Existing shelf plugin infrastructure (`plugin-shelf/`)

## Risks & Open Questions

- **Template format**: Should the canonical template be a literal `.md` file in the plugin, or a structured JSON/YAML definition? A literal file is easier to maintain but harder to parameterize. **Recommendation**: Use literal `.md` template files with `{{placeholder}}` markers that the agent step fills in.
- **Repair scope**: Should `shelf-repair` also fix issue/doc notes, or just the dashboard? **Recommendation**: Start with dashboard-only. Issue/doc repair can be a separate workflow later.
- **Status migration**: Existing projects with non-canonical status labels need migration. **Recommendation**: `shelf-repair` handles this automatically — it reads the current status, maps to the closest canonical value, and reports the change.
- **Workflow composition**: `shelf-create` may want to compose `shelf-full-sync` as its final step (to immediately sync after creating). This depends on wheel supporting cross-plugin workflow composition, which was just fixed.
