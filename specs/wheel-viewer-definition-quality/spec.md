# Feature Specification: Wheel Viewer — Definition-Quality Pass

**Feature Branch**: `build/wheel-viewer-definition-quality-20260509`
**Created**: 2026-05-09
**Status**: Draft
**Input**: PRD at `docs/features/2026-05-09-wheel-viewer-definition-quality/PRD.md`

## Summary

Lift the wheel viewer (`plugin-wheel/viewer/`, Next.js 15 + React 19 in Docker on port 3847) from "static doc browser" to a **definition-quality tool** that an analyst can rely on to inspect, search, validate, and compare workflow definitions across plugins. Adds team-step rendering, layered auto-layout, search + filter, structural lint, side-by-side diff, source-checkout discovery, and empty-state UX. Live execution state, archive browsing, and execution-control surface are explicitly deferred to a separate PRD.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Workflow analyst inspecting a team workflow (Priority: P1)

An analyst opens the viewer in a fresh container, registers this repo as a project, and clicks into `bifrost-minimax-team-static`. They expect to see every step rendered correctly (no `?` placeholders), no overlapping nodes, and the team-create → teammate fan-out → team-wait fan-in pattern visible at a glance. They expand the `worker-1` teammate to see its sub-workflow inline.

**Why this priority**: This is the load-bearing scenario from the PRD. Phase 4 fixtures are precisely the workflow surface the team just stabilized over 105 commits, and they currently render as fallback `?` nodes — the viewer's biggest blind spot.

**Independent Test**: Open `http://localhost:3847`, register this repo, click `bifrost-minimax-team-static` in the sidebar, screenshot the FlowDiagram. Verify all 8 steps visible, no node overlap, type-specific colors/icons on team-create / teammate / team-wait / team-delete.

**Acceptance Scenarios**:

1. **Given** the viewer is running with this repo registered, **When** the analyst clicks `bifrost-minimax-team-static`, **Then** the FlowDiagram renders all 8 steps with no node overlap, edges follow the layered DAG, and each team-step type has its specific badge + color.
2. **Given** the same workflow is open, **When** the analyst expands the `worker-1` teammate's sub-workflow link, **Then** the sub-DAG renders below the parent step as a self-contained cluster with no overlap, connected by the existing dashed-cyan `expanded-` edge.
3. **Given** a `bifrost-minimax-team-mixed-model` workflow is selected, **When** the analyst inspects each step, **Then** all 7 step types (`command`, `team-create`, `teammate`×2, `team-wait`, `command`, `team-delete`) render with type-specific styling and zero `?` placeholders.

---

### User Story 2 — Plugin author working from a source checkout (Priority: P2)

A plugin author has this repo open locally with `plugin-wheel/`, `plugin-kiln/`, `plugin-clay/`, `plugin-shelf/`, `plugin-trim/` directly in the working tree. They register `/Users/.../ai-repo-template` and expect to see ALL plugin workflows in the sidebar — both the installed-marketplace versions AND the source-checkout versions, with the source ones tagged `(source)` so they can verify they're seeing the working-tree edits.

**Why this priority**: The author dev loop is broken without source discovery — the viewer is invisible to plugin authors editing their own workflows, which is the most common case for this repo's contributors.

**Independent Test**: With this repo registered, scroll the sidebar. Confirm `plugin-kiln` and `plugin-shelf` workflow groups show entries from both `~/.claude/plugins/cache/<org>/<plugin>/<version>/workflows/` (installed) and `<repoPath>/plugin-*/workflows/` (source) with the latter tagged.

**Acceptance Scenarios**:

1. **Given** a project is registered whose path contains `plugin-*/` siblings, **When** discovery runs, **Then** sibling plugin workflows are surfaced under the same plugin group with a `(source)` tag distinct from `(installed)` entries.
2. **Given** both an installed and a source version of the same workflow are discovered, **When** the sidebar renders, **Then** both entries are visible (the user can click either) and the source version visually shadows the installed one when both are clickable.

---

### User Story 3 — First-time user with empty registry (Priority: P3)

A user runs `/wheel:wheel-view` for the first time with a fresh container and zero registered projects. They expect onboarding guidance — not blank panels.

**Why this priority**: Empty-state UX prevents an "is it broken?" first impression. Lower priority than P1/P2 because experienced users hit it once.

**Independent Test**: Start the container with a fresh registry (`globalThis.__wheelViewProjects` empty) and load `http://localhost:3847`. Confirm the onboarding panel shows the "Add a project path" form with example placeholder text.

**Acceptance Scenarios**:

1. **Given** the container has zero registered projects, **When** the user opens the viewer, **Then** an onboarding panel renders with a one-line explanation and the `/Users/you/projects/my-app` placeholder text in the input.
2. **Given** a project is registered but its `workflows/` directory is missing, **When** the user clicks that project, **Then** an explanatory panel renders: "No workflows discovered. Run `/wheel:wheel-init` in this project, or check that `<projectPath>/workflows/` exists."

---

### User Story 4 — Analyst diffing two related workflows (Priority: P2)

An analyst wants to know what's different between `team-static` and `team-haiku-fanout` — currently they have to run `git diff` in another window. They shift-click both workflows in the sidebar and expect a side-by-side diff view with added / removed / modified counts and step-level highlighting.

**Why this priority**: Diff comparison is a discrete value-add that's easy to recognize in the sidebar UI; users get measurable productivity from it without a learning curve.

**Independent Test**: Shift-click two workflows in the sidebar, click the "Diff" affordance, verify the side-by-side view appears with summary counts.

**Acceptance Scenarios**:

1. **Given** zero workflows are selected, **When** the user shift-clicks two workflows, **Then** a "Diff" affordance becomes available.
2. **Given** two workflows are diff-selected, **When** the user opens diff view, **Then** the layout shows added (green) / removed (red) / modified (yellow with JSON expand) / unchanged (muted) and a header summary `X added, Y removed, Z modified, W unchanged`.

---

### User Story 5 — Lint surfacing structural issues (Priority: P2)

A workflow author broke a `branch` step's `if_zero` target while editing — the target ID no longer exists. They want the viewer to surface this immediately, not silently render a broken graph.

**Why this priority**: Lint catches the class of bugs that only manifest at runtime. Pre-runtime catch is high value for authors.

**Independent Test**: Commit a deliberately-broken fixture at `plugin-wheel/tests/lint-fixture-broken.json` containing missing-id, unresolved branch target, missing loop substep, and team-create without team_name. Confirm the Lint tab surfaces all four issues.

**Acceptance Scenarios**:

1. **Given** a workflow with structural defects, **When** the user selects it, **Then** the sidebar badge shows red-X (errors) and the right panel exposes a Lint tab with one row per issue (severity, step ID, message, jump-to-step).
2. **Given** a clean workflow (e.g. `bifrost-minimax-smoke`), **When** the user selects it, **Then** the sidebar badge shows green-check and the Lint tab is empty.

---

### Edge Cases

- **Empty workflow** (zero steps): rendered as a placeholder card; no FlowDiagram crash.
- **Source AND installed both present** (same plugin name): both rendered; sidebar shows `(source)` tag on the source entry.
- **Source path missing `.claude-plugin/plugin.json`**: directory skipped silently (it's not a plugin checkout).
- **Loop substep with no `id`** (only top-level steps need IDs to lint): substep flagged separately if it itself contains broken refs.
- **Branch target on a sibling step in a parent workflow** (when expanded sub-workflow references a step outside its own scope): out of v1 scope; lint operates per-workflow only.
- **Two workflows with identical name** (e.g. installed AND source): sidebar disambiguates with the `(source)` tag; both clickable.
- **Diff with no common step IDs**: every step shows as added or removed; summary still computed.
- **Search input + step-type filter compose** (intersect): zero results render the "no matches" hint, filters can be cleared via "clear all" button.

## Requirements *(mandatory)*

### Functional Requirements

#### FR-1 — Auto-layout engine

- **FR-1.1**: System MUST identify a workflow's logical DAG by following `next-step` (default), `if_zero` / `if_nonzero` (branch), `skip` (jump), and `substep` (loop body) edges.
- **FR-1.2**: System MUST compute node positions via a layered topological-rank algorithm — nodes at the same rank spread horizontally, ranks stack vertically.
- **FR-1.3**: Branch targets that join back to the main chain MUST render at the rejoin point, not as orphan columns.
- **FR-1.4**: Loop substeps MUST render as a nested cluster anchored to the loop step, with a labeled back-edge showing the iteration boundary.
- **FR-1.5**: Parallel children MUST render as siblings at the same rank.
- **FR-1.6**: Expanded sub-workflows MUST render below their parent step as a self-contained sub-DAG with its own layered layout. The existing dashed-cyan `expanded-` edge stays; only the layout changes.
- **FR-1.7**: Team-step fan-out MUST render `team-wait` with incoming edges from every preceding `teammate` step that targets the same team — visually a fan-in node.
- **FR-1.8**: No two nodes MUST overlap in any fixture under `plugin-wheel/tests/*` or `workflows/tests/*.json` (visually verified by qa-engineer screenshots).

#### FR-2 — Team-step rendering

- **FR-2.1**: `StepType` MUST be extended to: `'command' | 'agent' | 'workflow' | 'branch' | 'loop' | 'parallel' | 'approval' | 'team-create' | 'team-wait' | 'team-delete' | 'teammate'`.
- **FR-2.2**: `WorkflowNode` MUST render type-specific icons and colors for the new types: `team-create: ⊕`, `team-wait: ⊞`, `team-delete: ⊖`, `teammate: ◐`. The four team types share a color family from the existing palette in `viewer.css`, distinct from `agent` / `command` / `workflow` colors.
- **FR-2.3**: `WorkflowNode` body MUST render type-specific fields:
  - `team-create`: `team_name`
  - `team-wait`: `team` ref + `output` path if present
  - `team-delete`: `team` ref + `terminal: true` badge if present
  - `teammate`: `team` ref + `workflow` (sub-workflow path) + `model` if present + `assign` summary
- **FR-2.4**: `RightPanel` step-detail view MUST show the full `assign` JSON for `teammate` steps and the full `workflow_definition` for sub-workflow expansions.

#### FR-3 — Sidebar search + filter

- **FR-3.1**: Sidebar MUST gain a `<input type="search">` element above the workflow list. Filtering is real-time substring match against workflow `name`, case-insensitive. Empty input = show all.
- **FR-3.2**: Below the search input, a horizontal chip strip MUST list all step types present across the discovered workflows (deduplicated). Clicking a chip toggles a filter: only workflows containing at least one step of that type remain visible.
- **FR-3.3**: Search and step-type filters MUST compose (intersect). Active filters MUST show a "clear all" button.
- **FR-3.4**: Workflow group counts in the sidebar MUST reflect post-filter visible counts (e.g. `kiln (12 of 27)` when filters narrow the list).

#### FR-4 — Lint panel

- **FR-4.1**: Each workflow MUST have a Lint summary computed at discovery time and shown as a badge next to the workflow name in the sidebar: green check (clean), yellow triangle (warnings only), red X (errors).
- **FR-4.2**: Selecting a workflow MUST open a "Lint" tab in the right panel (alongside the existing "Detail" tab) listing every issue with severity, step ID, one-line message, and a "jump to step" affordance.
- **FR-4.3**: Lint rules in v1:
  - **L-001 (error)**: every step must have a non-empty `id`.
  - **L-002 (error)**: every step must have a recognized `type` (member of extended StepType union).
  - **L-003 (error)**: branch step targets (`if_zero`, `if_nonzero`) must resolve to a sibling step's `id` within the same workflow.
  - **L-004 (error)**: `skip` target must resolve to a sibling step's `id` within the same workflow.
  - **L-005 (error)**: `loop` step must define a `substep`.
  - **L-006 (error)**: duplicate step IDs within a single workflow.
  - **L-007 (warning)**: `requires_plugins` references a plugin not in `installed_plugins.json` AND not source-discoverable from the registered project path.
  - **L-008 (warning)**: `team-create` step missing `team_name` field.
  - **L-009 (warning)**: `teammate` step missing `team`, `workflow`, OR `assign` field.
  - **L-010 (warning)**: `team-wait` step's `team` ref doesn't match any prior `team-create` step in the same workflow.
- **FR-4.4**: `lintWorkflow` MUST be pure-functional and synchronous — no I/O beyond the `installed_plugins.json` snapshot loaded by discovery and passed in as a parameter.

#### FR-5 — Diff view

- **FR-5.1**: Sidebar workflow rows MUST support shift-click to multi-select. With exactly two workflows selected, a "Diff" affordance MUST become available.
- **FR-5.2**: Diff view MUST replace the FlowDiagram + RightPanel with a side-by-side layout: left workflow on the left, right workflow on the right. Each side renders a compact step list (reuses `StepRow`) with diff highlighting:
  - Added steps (present only in right): green
  - Removed steps (present only in left): red
  - Modified steps (same `id`, different content): yellow + expand to show JSON diff
  - Unchanged steps: muted
- **FR-5.3**: Step alignment MUST use `id` as the join key. Steps with no matching `id` on the other side render as added / removed.
- **FR-5.4**: A small header MUST summarize the diff: `X added, Y removed, Z modified, W unchanged`.

#### FR-6 — Direct-source-checkout discovery

- **FR-6.1**: `discoverPluginWorkflows` MUST accept an optional `projectPath` parameter (the registered project's path). Existing call sites without the parameter MUST keep working (backwards-compatible).
- **FR-6.2**: When `projectPath` is provided, the function MUST scan `<projectPath>/plugin-*/` for siblings of `plugin-wheel/`. For each matching directory, it treats it as a plugin install (looks for `.claude-plugin/plugin.json` + `workflows/`).
- **FR-6.3**: Source-discovered workflows MUST tag with `discoveryMode: 'source'` (new optional field on `Workflow`). Installed-discovered workflows tag with `discoveryMode: 'installed'`. The sidebar shows source-discovered workflows under the same plugin group with a `(source)` suffix in the type badge.
- **FR-6.4**: When BOTH installed AND source versions of the same workflow are discovered, both MUST render in the sidebar. The `localOverride` field semantics extend to: source shadows installed for direct-checkout authors actively editing.

#### FR-7 — Empty-state UX

- **FR-7.1**: First page load with zero projects MUST render the "Add project" form prominently with a one-line explanation: "Add a project path to view its workflows." The example placeholder text shows `/Users/you/projects/my-app`.
- **FR-7.2**: Project registered but `workflows/` directory missing MUST render an explanatory panel: "No workflows discovered. Run `/wheel:wheel-init` in this project, or check that `<projectPath>/workflows/` exists."
- **FR-7.3**: Project + workflows present but Lint reports errors on the active workflow: the Detail panel still renders the FlowDiagram, but a banner above it MUST offer to switch to the Lint tab.

#### FR-8 — Hygiene

- **FR-8.1**: System MUST delete `plugin-wheel/skills/wheel-view/viewer.html` (the pre-Next.js prototype that the new app supersedes).
- **FR-8.2**: System MUST verify no other file references it: `git grep -F viewer.html plugin-wheel/` returns zero matches.

### Key Entities *(include if feature involves data)*

- **Workflow**: A workflow JSON file. Adds `discoveryMode: 'installed' | 'source' | 'local'` to distinguish discovery origin. Existing `localOverride: boolean` semantic preserved.
- **Step**: Existing entity. `type` widens to include team primitives. No structural changes beyond the union widening.
- **LintIssue**: A structural issue surfaced by `lintWorkflow`. Attributes: `severity ('error'|'warning')`, `stepId: string` (or empty for workflow-level issues), `ruleId ('L-001'…'L-010')`, `message: string`.
- **WorkflowDiff**: The result of comparing two workflows. Attributes: `added: Step[]`, `removed: Step[]`, `modified: { id, leftStep, rightStep, fieldDiff: FieldDiff[] }[]`, `unchanged: Step[]`.
- **GraphNode / GraphEdge**: React Flow render-ready node and edge. Computed by `buildLayout(workflow, expandedWorkflows?)`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

The PRD ships when **every screenshot below has been captured from a real `/wheel:wheel-view` session against this repo** and committed under `specs/wheel-viewer-definition-quality/screenshots/` (mirrored in the PRD directory):

- **SC-001 (AC-1, auto-layout, normal)**: `bifrost-minimax-team-static` renders in the FlowDiagram with no node overlap, all 8 steps visible, edges following the layered DAG. → `screenshots/01-auto-layout-team-static.png`.
- **SC-002 (AC-2, auto-layout, expanded)**: `bifrost-minimax-team-static` with the `worker-1` teammate sub-workflow expanded renders the sub-DAG below the parent step with no overlap. → `screenshots/02-auto-layout-team-static-expanded.png`.
- **SC-003 (AC-3, auto-layout, branch fan-out)**: a workflow with `branch` + `if_zero` / `if_nonzero` targets renders both branches with the rejoin point cleanly visible. → `screenshots/03-auto-layout-branch.png`.
- **SC-004 (AC-4, team-step rendering)**: `bifrost-minimax-team-mixed-model` renders all 7 step types with their type-specific colors / icons / fields and zero `?` placeholders. → `screenshots/04-team-step-rendering.png`.
- **SC-005 (AC-5, search)**: typing `team-` in the sidebar search shows only team-* workflows. → `screenshots/05-search.png`.
- **SC-006 (AC-6, filter)**: clicking the `branch` chip filters to only workflows containing at least one branch step. → `screenshots/06-filter.png`.
- **SC-007 (AC-7, lint, clean)**: `bifrost-minimax-smoke` shows the green check badge in the sidebar. → `screenshots/07-lint-clean.png`.
- **SC-008 (AC-8, lint, errors)**: a deliberately-broken fixture (committed as `plugin-wheel/tests/lint-fixture-broken.json`) surfaces L-001 / L-003 / L-005 / L-008 errors with step IDs. → `screenshots/08-lint-errors.png`.
- **SC-009 (AC-9, diff)**: shift-clicking `team-static` and `team-haiku-fanout` opens the diff view with X-added / Y-removed counts. → `screenshots/09-diff.png`.
- **SC-010 (AC-10, source discovery)**: registering this repo's path shows kiln/clay/shelf/trim workflows tagged `(source)`. → `screenshots/10-source-discovery.png`.
- **SC-011 (AC-11, empty-state, no projects)**: container fresh, no projects, shows the "Add project" onboarding. → `screenshots/11-empty-no-projects.png`.
- **SC-012 (AC-12, empty-state, no workflows)**: registering a project with no `workflows/` dir shows the "No workflows discovered" panel. → `screenshots/12-empty-no-workflows.png`.
- **SC-013 (hygiene)**: `git grep -F viewer.html plugin-wheel/` returns zero matches after FR-8 ships.
- **SC-014 (lint coverage)**: `lintWorkflow` unit-tests cover all 10 lint rules (L-001…L-010), both positive (rule fires) and negative (rule does not fire on a clean fixture) for each.

### Authoring grep-style success criteria against historical state

SC-013 above is a grep-style assertion that scans `plugin-wheel/`. There is no historical-state directory pre-PRD that would noisily match `viewer.html`, so a date-bound qualifier is unnecessary; the bare `git grep -F viewer.html plugin-wheel/` is the live assertion. If pre-PRD scaffolding artifacts mention the deleted file, surface them and confirm they're either irrelevant docs (commits, PR descriptions) or follow-up cleanup tasks.

## Non-Goals

Mirrors PRD's "Non-Goals" + "Out of Scope" sections — keep these explicit so audit doesn't try to retrofit them into the current spec:

- **Not live state.** Reading `.wheel/state_*.json` for in-flight workflows is deferred to a separate PRD (`wheel-viewer-runtime-ops`).
- **Not archive browsing.** Reading `.wheel/history/<bucket>/*.json` for completed runs is deferred to the runtime-ops PRD.
- **Not execution.** No `/wheel:wheel-run`, `/wheel:wheel-stop`, `/wheel:wheel-skip` triggers from the UI. The viewer stays read-only in this scope.
- **Not workflow authoring.** No in-browser create/edit/save back to disk.
- **Not Mermaid / DOT export.** Out of scope; an analyst can copy-paste from JSON.
- **Not Docker removal.** Direct `npm start` would reduce friction but stays Dockerized in this PRD.
- **Not persistent registry.** Project list still lives in `globalThis.__wheelViewProjects`. Container restart still wipes it.
- **Not test infrastructure (Playwright/CI).** `vitest` for `viewer/src/lib/*` is in scope; Playwright wiring into CI is deferred to runtime-ops PRD.

## Assumptions

- Viewer remains Dockerized on port 3847; no shipping-model changes in this scope.
- The existing `Workflow` type adds optional fields (`discoveryMode`) — backwards-compatible with current consumers.
- The team-step palette pulls from existing CSS custom properties (`--accent-blue`, `--accent-cyan`, etc.); no new color tokens introduced.
- React Flow continues to be the rendering layer; the layout change is internal to `buildGraphLayout` (replaced by `buildLayout`).
- No new npm dependencies are required (hand-rolled layout instead of `dagre`); the `viewer/package.json` `dependencies` block is unchanged.
- The deliberately-broken lint fixture under `plugin-wheel/tests/lint-fixture-broken.json` is committed alongside implementation and consumed only by lint test cases — it is NOT activated by `/wheel:wheel-test`.
- Screenshots can be captured manually via Playwright invoked by `qa-engineer` against a running container; no Playwright CI wiring is required.
- `viewer/src/lib/*.ts` modules are unit-tested with `vitest` (already configured for plugin-wheel).
