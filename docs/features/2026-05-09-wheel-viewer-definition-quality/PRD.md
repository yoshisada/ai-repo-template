# Feature PRD: Wheel Viewer — Definition-Quality Pass

## Parent Product

Wheel — hook-based workflow engine plugin (`plugin-wheel/`). The viewer (`plugin-wheel/viewer/`) is the in-browser inspector for workflow definitions, launched via `/wheel:wheel-view`. It runs as a Next.js 15 + React 19 app inside a Docker container on port 3847.

This PRD is the first follow-up after the viewer's initial scaffold (commit `df81b25c` on main, 2026-05-09). The initial scaffold delivered the registration → discovery → render skeleton; this PRD lifts the viewer from "static doc browser" to a **definition-quality tool** an analyst can rely on to inspect, search, validate, and compare workflow definitions across plugins.

## Feature Overview

Treat workflow JSON files as **first-class artifacts that need quality-of-information tooling**: completeness (every step type rendered correctly), discoverability (search + filter across many plugins), correctness (lint + validation of definitions), comparability (diff two workflows), and visual coherence (auto-layout that scales beyond linear chains). The viewer becomes the "read what the wheel knows about" companion to `/wheel:wheel-list` and `/wheel:wheel-create`.

**Live execution state, archive browsing, and execution-control surface are explicitly deferred to a separate PRD** — this one is about the definition layer only.

## Problem / Motivation

The initial scaffold renders enough of a workflow to be useful for the simple `command → agent → command` chain, but breaks down on the workflow surface that actually matters today:

1. **Step-type coverage is incomplete.** `StepType` is `'command' | 'agent' | 'workflow' | 'branch' | 'loop' | 'parallel' | 'approval'`. The team primitives — `team-create`, `team-wait`, `team-delete`, `teammate` — are absent. Every Phase 4 fixture we just shipped (`bifrost-minimax-team-*`) renders these as fallback "?" nodes. The viewer's biggest blind spot is exactly the step types we just spent 105 commits stabilizing.

2. **Auto-layout is naïve.** `FlowDiagram.buildGraphLayout` lays steps out at `y = i * 160` with zero horizontal offset. Branch targets, loop substeps, and expanded sub-workflows all collide on the same vertical axis. A workflow with a single `if_zero` jump produces a crossed-edges hairball; a `loop` step's `substep` doesn't render at all; an expanded sub-workflow's children are drawn at `parent.y + offset` with hand-tuned x positions that don't account for sibling fan-out.

3. **No search / filter.** With kiln + clay + shelf + trim each registering their workflows, a typical sidebar has 60+ entries grouped only by plugin name. Finding a specific workflow requires manual scanning. There's no name search, no step-type filter, no plugin filter.

4. **No validation surface.** A workflow JSON with a missing `id`, a `branch` step pointing to a non-existent target, a `loop` step with no `substep`, or a `requires_plugins` referencing an uninstalled plugin renders silently as if it were valid. The viewer has the entire workflow JSON in scope; it should call out structural issues.

5. **No comparison.** "What's different between `team-static` and `team-haiku-fanout`?" has no in-tool answer — has to be done via `git diff` in another window.

6. **Plugin discovery has a coverage gap.** `discoverPluginWorkflows` reads `~/.claude/plugins/installed_plugins.json`. If you're working from a source checkout (the repo root contains `plugin-wheel/`, `plugin-kiln/`, etc. directly), those workflows don't appear in the sidebar — only their installed-marketplace versions do. This is the most common case for plugin authors and the viewer is invisible to them in their own dev loop.

7. **Hygiene debt.** `plugin-wheel/skills/wheel-view/viewer.html` (16KB) is a pre-Next.js prototype that the new app supersedes. It's never read. Should be deleted.

8. **No empty-state UX.** First run with zero registered projects, or registered project with zero workflows, falls through to blank panels with no guidance.

The pattern: the scaffold proves the architecture works; this PRD makes it an analyst-grade tool.

## Goals

- **G1 (auto-layout, primary user request).** Workflows render with a layout algorithm that handles: linear chains, branch fan-out (`if_zero` / `if_nonzero` targets), loop substeps, parallel children, expanded sub-workflows, and team-step parent → teammate fan-out → fan-in patterns. No node overlap. No edge crossings on the happy path. Acceptance: every fixture under `plugin-wheel/tests/*` and every `workflows/tests/*.json` renders with no overlapping nodes (visually verified per fixture, screenshot-attached).
- **G2 (step-type completeness).** `StepType` includes the team primitives: `team-create`, `team-wait`, `team-delete`, `teammate`. Each gets a custom node renderer with type-specific badge + color + relevant fields (e.g. `team_name` on team-create, `team` ref on team-wait, sub-workflow link on teammate). Acceptance: a `bifrost-minimax-team-mixed-model` workflow renders all 7 step types with their type-specific styling, no `'?'` nodes.
- **G3 (search + filter).** Sidebar gains a search input that filters workflows by name (substring match, case-insensitive) and a step-type filter chip strip that hides workflows not containing the selected type. Acceptance: typing `team-` in search shows only the 6 bifrost-minimax-team-* workflows + any other team-* fixtures; clicking the `branch` chip hides workflows with no branch step.
- **G4 (workflow validation).** A new "Lint" panel surfaces structural issues per workflow:
  - Missing required fields (`id` on every step, `team_name` on team-create, etc.)
  - Branch / skip targets that don't resolve (`if_zero: "step-x"` where no step has `id: "step-x"`)
  - Loop steps with no `substep`
  - `requires_plugins` references that don't appear in `installed_plugins.json` AND aren't direct-checkout-discoverable
  - Duplicate step IDs
  - Acceptance: synthesizing a deliberately-broken workflow surfaces every issue as a Lint-panel row with the failing step ID + a one-line explanation.
- **G5 (diff view).** Selecting two workflows from the sidebar (multi-select via shift-click) opens a side-by-side diff view: structural diff (added / removed / modified steps) + a JSON diff for the modified ones. Acceptance: diffing `team-static` vs `team-haiku-fanout` shows the added teammates + the loop_from change in a readable, navigable view.
- **G6 (direct-source-checkout discovery).** `discoverPluginWorkflows` augments `installed_plugins.json` discovery with a scan of the registered project path itself for sibling `plugin-*/` directories. Found plugins' workflows are tagged "(source)" in the sidebar to distinguish from installed copies. Acceptance: registering `/Users/.../ai-repo-template` shows kiln/clay/shelf/trim/wheel workflows under both their installed AND source listings, with the source ones tagged.
- **G7 (empty-state UX).** First-run experience guides the user: "Add a project path to start" with the input field highlighted; per-project empty workflow state explains "this project has no `workflows/` directory yet — see `/wheel:wheel-init`." Acceptance: container started with a fresh registry, opening `http://localhost:3847` shows the onboarding state without errors.
- **G8 (hygiene).** Delete `plugin-wheel/skills/wheel-view/viewer.html`. The skill's launcher only references `plugin-wheel/viewer/`. Acceptance: `git grep -F viewer.html plugin-wheel/` returns zero matches.

## Non-Goals

- **Not live state.** Reading `.wheel/state_*.json` for in-flight workflows is deferred to a separate PRD ("wheel-viewer-runtime-ops"). The data flow + UI patterns are different enough to deserve their own scope.
- **Not archive browsing.** Reading `.wheel/history/<bucket>/*.json` for completed runs is deferred to the same runtime-ops PRD.
- **Not execution.** No `/wheel:wheel-run`, `/wheel:wheel-stop`, `/wheel:wheel-skip` triggers from the UI. The viewer stays read-only in this scope.
- **Not workflow authoring.** No in-browser create/edit/save back to disk.
- **Not Mermaid / DOT export.** Tempting given React Flow already renders the graph, but out of scope; an analyst can copy-paste from JSON.
- **Not Docker removal.** Direct `npm start` would reduce friction but changes the shipping model. Stays Dockerized in this PRD.
- **Not persistent registry.** Project list still lives in `globalThis.__wheelViewProjects`. Container restart still wipes it. Adding a JSON file at `~/.claude/wheel-view/projects.json` is a small change but not the primary value here; punt to a follow-up unless trivially aligned with G6's discovery work.
- **Not test infrastructure.** Playwright is in `package.json` deps but unused. Wiring it into CI is out of scope; covered separately in the runtime-ops PRD where live state assertions need it.

## Functional Requirements

### FR-1 — Auto-layout engine

`FlowDiagram` replaces `buildGraphLayout` with a directed-graph layout that:

- **FR-1.1** Identifies the workflow's logical DAG by following `next-step` (default), `if_zero` / `if_nonzero` (branch), `skip` (jump), and `substep` (loop body) edges.
- **FR-1.2** Computes node positions via a layered approach (e.g. dagre-style or a hand-rolled topological-rank algorithm — implementer's choice based on bundle-size). Nodes at the same rank are spread horizontally; ranks stack vertically.
- **FR-1.3** Branch targets that join back to the main chain render at the rejoin point, not as orphan columns.
- **FR-1.4** Loop substeps render as a nested cluster anchored to the loop step, with a labeled back-edge showing the iteration boundary.
- **FR-1.5** Parallel children render as siblings at the same rank.
- **FR-1.6** Expanded sub-workflows render below their parent step as a self-contained sub-DAG with its own layered layout — siblings at the same rank within the sub, then the sub itself sits below the parent. The connection from parent to sub is visually distinct (the existing dashed-cyan `expanded-` edge stays; only the layout changes).
- **FR-1.7** Team-step fan-out: `team-wait` rendering shows incoming edges from every `teammate` step pointing at this team. Visually a fan-in node.
- **FR-1.8** No two nodes overlap in any fixture under `plugin-wheel/tests/*` or `workflows/tests/*.json`.

### FR-2 — Team-step rendering

- **FR-2.1** `StepType` extended: `'command' | 'agent' | 'workflow' | 'branch' | 'loop' | 'parallel' | 'approval' | 'team-create' | 'team-wait' | 'team-delete' | 'teammate'`.
- **FR-2.2** `WorkflowNode` adds icons + colors for each new type. Icons: `team-create: ⊕`, `team-wait: ⊞`, `team-delete: ⊖`, `teammate: ◐`. Colors: pick from existing palette in `viewer.css` (`--accent-blue` / `--accent-cyan` / etc.) — the four team types share a color family distinct from agent/command/workflow.
- **FR-2.3** `WorkflowNode` body renders type-specific fields:
  - `team-create`: `team_name`
  - `team-wait`: `team` ref + `output` path if present
  - `team-delete`: `team` ref + `terminal: true` badge if present
  - `teammate`: `team` ref + `workflow` (sub-workflow path) + `model` if present + `assign` summary
- **FR-2.4** `RightPanel` step-detail view shows the full `assign` JSON for `teammate` steps and the full `workflow_definition` for sub-workflow expansion.

### FR-3 — Sidebar search + filter

- **FR-3.1** Sidebar gains a `<input type="search">` element above the workflow list. Filters in real-time on substring match against workflow `name` (case-insensitive). Empty input = show all.
- **FR-3.2** Below the search input, a horizontal chip strip lists all step types present across the discovered workflows (deduplicated). Clicking a chip toggles a filter: only workflows containing at least one step of that type remain visible.
- **FR-3.3** Search and step-type filters compose (intersect). Active filters show a "clear all" button.
- **FR-3.4** Workflow group counts in the sidebar reflect post-filter visible counts (e.g. `kiln (12 of 27)` when filters narrow the list).

### FR-4 — Lint panel

- **FR-4.1** Each workflow has a Lint summary computed at discovery time and shown as a badge next to the workflow name in the sidebar: green check (clean), yellow triangle (warnings only), red X (errors).
- **FR-4.2** Selecting a workflow opens a "Lint" tab in the right panel (alongside the existing "Detail" tab) listing every issue with: severity, step ID, one-line message, and a "jump to step" affordance.
- **FR-4.3** Lint rules in v1:
  - **L-001 (error)**: every step must have a non-empty `id`.
  - **L-002 (error)**: every step must have a recognized `type`.
  - **L-003 (error)**: branch step targets (`if_zero`, `if_nonzero`) must resolve to a sibling step's `id`.
  - **L-004 (error)**: `skip` target must resolve to a sibling step's `id`.
  - **L-005 (error)**: `loop` step must define a `substep`.
  - **L-006 (error)**: duplicate step IDs within a workflow.
  - **L-007 (warning)**: `requires_plugins` references a plugin not in `installed_plugins.json` AND not source-discoverable.
  - **L-008 (warning)**: `team-create` step missing `team_name` field.
  - **L-009 (warning)**: `teammate` step missing `team`, `workflow`, OR `assign` field.
  - **L-010 (warning)**: `team-wait` step's `team` ref doesn't match any prior `team-create` step in the same workflow.
- **FR-4.4** Lint runs are pure-functional and synchronous (no I/O beyond `installed_plugins.json` already loaded by discovery).

### FR-5 — Diff view

- **FR-5.1** Sidebar workflow rows support shift-click to multi-select. With exactly two workflows selected, a "Diff" affordance becomes available.
- **FR-5.2** Diff view replaces the FlowDiagram + RightPanel with a side-by-side layout: left workflow on the left, right workflow on the right. Each side renders a compact step list (the existing `StepRow` component is fine) with diff highlighting:
  - Added steps (present only in right): green
  - Removed steps (present only in left): red
  - Modified steps (same `id`, different content): yellow + expand to show JSON diff
  - Unchanged steps: muted
- **FR-5.3** Step alignment uses `id` as the join key. Steps with no matching `id` on the other side render as added / removed.
- **FR-5.4** A small header summarizes the diff: "X added, Y removed, Z modified, W unchanged".

### FR-6 — Direct-source-checkout discovery

- **FR-6.1** `discoverPluginWorkflows` accepts the registered project's `path` as input.
- **FR-6.2** When called with a project path, scans `<projectPath>/plugin-*/` for siblings of `plugin-wheel/`. For each matching directory, treats it as a plugin install (looks for `.claude-plugin/plugin.json` + `workflows/`).
- **FR-6.3** Source-discovered workflows tag with `source: 'plugin'` AND `discoveryMode: 'source'` (new field on `Workflow`). The sidebar shows source-discovered workflows under the same plugin group as installed-discovered ones, but with a `(source)` suffix in the type badge.
- **FR-6.4** When BOTH installed AND source versions of the same workflow are discovered, both render. The `localOverride` field's existing semantic (local workflow shadows plugin) extends to: source shadows installed for direct-checkout authors actively editing.

### FR-7 — Empty-state UX

- **FR-7.1** First page load with zero projects: render the "Add project" form prominently with a one-line explanation: "Add a project path to view its workflows." The example placeholder text shows `/Users/you/projects/my-app`.
- **FR-7.2** Project registered but `workflows/` directory missing: render an explanatory panel: "No workflows discovered. Run `/wheel:wheel-init` in this project, or check that `<projectPath>/workflows/` exists."
- **FR-7.3** Project + workflows present but Lint reports errors on the active workflow: the Detail panel still renders the FlowDiagram, but a banner above it offers to switch to the Lint tab.

### FR-8 — Hygiene

- **FR-8.1** Delete `plugin-wheel/skills/wheel-view/viewer.html`.
- **FR-8.2** Verify no other file references it.

## Acceptance Criteria

This PRD ships when **every screenshot below has been captured from a real `/wheel:wheel-view` session against this repo** and added to this PRD's directory under `screenshots/`:

- **AC-1 (auto-layout, normal)**: `bifrost-minimax-team-static` renders in the FlowDiagram with no node overlap, all 8 steps visible, edges following the layered DAG. Screenshot: `screenshots/01-auto-layout-team-static.png`.
- **AC-2 (auto-layout, expanded)**: `bifrost-minimax-team-static` with the `worker-1` teammate sub-workflow expanded (`team-sub-worker.json`) renders the sub-DAG below the parent step with no overlap. Screenshot: `screenshots/02-auto-layout-team-static-expanded.png`.
- **AC-3 (auto-layout, branch fan-out)**: a workflow with `branch` + `if_zero` / `if_nonzero` targets renders both branches with the rejoin point cleanly visible. Screenshot: `screenshots/03-auto-layout-branch.png`.
- **AC-4 (team-step rendering)**: `bifrost-minimax-team-mixed-model` renders all 7 step types (`command`, `team-create`, `teammate`, `teammate`, `team-wait`, `command`, `team-delete`) with their type-specific colors / icons / fields. No `?` placeholders. Screenshot: `screenshots/04-team-step-rendering.png`.
- **AC-5 (search)**: typing `team-` in the sidebar search shows only team-* workflows. Screenshot: `screenshots/05-search.png`.
- **AC-6 (filter)**: clicking the `branch` chip filters to only workflows containing at least one branch step. Screenshot: `screenshots/06-filter.png`.
- **AC-7 (lint, clean)**: `bifrost-minimax-smoke` (a clean workflow) shows the green check badge in the sidebar. Screenshot: `screenshots/07-lint-clean.png`.
- **AC-8 (lint, errors)**: a deliberately-broken fixture (committed as `plugin-wheel/tests/lint-fixture-broken.json`) surfaces L-001 / L-003 / L-005 / L-008 errors with step IDs. Screenshot: `screenshots/08-lint-errors.png`.
- **AC-9 (diff)**: shift-clicking `team-static` and `team-haiku-fanout` opens the diff view with X-added / Y-removed counts. Screenshot: `screenshots/09-diff.png`.
- **AC-10 (source discovery)**: registering this repo's path (`/Users/.../ai-repo-template`) shows kiln/clay/shelf/trim workflows tagged `(source)`. Screenshot: `screenshots/10-source-discovery.png`.
- **AC-11 (empty-state, no projects)**: container fresh, no projects, shows the "Add project" onboarding. Screenshot: `screenshots/11-empty-no-projects.png`.
- **AC-12 (empty-state, no workflows)**: registering a project with no `workflows/` dir shows the "No workflows discovered" panel. Screenshot: `screenshots/12-empty-no-workflows.png`.

**All 12 screenshots committed alongside the implementation. Final PR description embeds each screenshot inline.**

## Out of Scope (Future PRDs)

These are real product needs surfaced during the audit but explicitly **not** part of this scope:

- **wheel-viewer-runtime-ops**: live state from `.wheel/state_*.json`, archive browser from `.wheel/history/<bucket>/`, per-step status overlay (pending / working / done / failed), polling / SSE for live updates, execution-control surface (`/wheel:wheel-run` / `-stop` / `-skip` from UI), Playwright + CI test wiring.
- **wheel-viewer-authoring**: in-browser workflow editor with save-back-to-disk.
- **wheel-viewer-portability**: drop Docker dependency, ship as `npm start` directly, persistent registry at `~/.claude/wheel-view/projects.json`.

These should be filed as `/kiln:kiln-roadmap` items at PRD-approval time so they don't get lost.

## Implementation Notes

- **Layout library choice**: a hand-rolled layered layout is probably ~150 LOC and avoids adding `dagre` (~250KB). Consider before reaching for the dependency.
- **Lint as a pure module**: `lib/lint.ts` with `function lintWorkflow(wf: Workflow): LintIssue[]`. No I/O; deterministic output. Easy to unit-test.
- **Search/filter state**: lift to URL query params (`?q=team&types=branch`) so links are shareable.
- **Diff rendering**: existing `StepRow` component already accepts a step + index; extend with an optional `diffStatus` prop. JSON diff library: avoid `jsondiffpatch` (~80KB); a hand-rolled key-by-key diff over `Step` is enough for v1.
- **Screenshot capture**: use Playwright (already in `package.json`) headlessly against a running container, OR manual capture from a real session. The acceptance gate is "screenshots committed under `screenshots/`," not "automated screenshot tests" (that's deferred to runtime-ops PRD).
