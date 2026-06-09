# Implementation Plan: Wheel Viewer — Definition-Quality Pass

**Branch**: `build/wheel-viewer-definition-quality-20260509` | **Date**: 2026-05-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/wheel-viewer-definition-quality/spec.md`

## Summary

Extend `plugin-wheel/viewer/` (Next.js 15 + React 19 in Docker on port 3847) with definition-quality features: layered auto-layout, team-step rendering, sidebar search/filter, structural lint, side-by-side diff, source-checkout discovery, and empty-state UX. Three implementer agents (data-layer, graph, shell) work in parallel after Phase 1's type extension lands. No new npm dependencies — hand-rolled layered layout (≈150 LOC) replaces the naïve `i * 160` row stacking.

## Technical Context

**Language/Version**: TypeScript (strict), Next.js 15 + React 19, Node 20+
**Primary Dependencies**: existing `viewer/package.json` deps only — `react`, `react-dom`, `next`, `reactflow`, `vitest` (dev). **No new deps.**
**Storage**: in-memory (`globalThis.__wheelViewProjects`); reads `~/.claude/plugins/installed_plugins.json` and per-project `workflows/` directories.
**Testing**: `vitest` for `viewer/src/lib/*.ts` unit tests (re-uses plugin-wheel's existing vitest config); Playwright already in `viewer/package.json` deps but only invoked by qa-engineer for screenshot capture (not CI-wired in this scope).
**Target Platform**: Docker container (Node 20 base image), browser (latest Chrome/Firefox, served via `next start` on port 3847).
**Project Type**: web app (Next.js, frontend-only — the API routes are file-system reads, no backing service).
**Performance Goals**: layout O(V + E) per workflow; lint O(steps²) acceptable (worst-case 50 steps in any fixture). Sidebar filter re-renders <50ms with 60+ workflows.
**Constraints**: no new bundle weight beyond ~3-5 KB (hand-rolled layout + lint module). Backwards-compatible: existing call sites of `discoverPluginWorkflows` keep working.
**Scale/Scope**: ~10 modified files, ~3 new files; ~600 LOC delta total.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Article VII (Interface Contracts)**: ✅ — `contracts/interfaces.md` (this PR) is the single source of truth for `lintWorkflow`, `buildLayout`, `discoverPluginWorkflows` (revised), `diffWorkflows`, and the extended `StepType` union.
- **Article VIII (Incremental Task Completion)**: ✅ — tasks split into Phase 1 (types — blocks others), Phase 2 (parallel data/graph/shell), Phase 3 (qa screenshots), with `[X]` checkpoints required after each task.
- **80% test coverage gate**: ✅ — `lintWorkflow`, `buildLayout`, `diffWorkflows`, `discoverPluginWorkflows` are pure-functional and unit-testable. Coverage target applies to `viewer/src/lib/*.ts`. UI components (FlowDiagram, Sidebar, RightPanel) are covered by qa-engineer screenshot QA, not unit tests (per existing viewer convention).
- **No new dependencies without rationale**: ✅ — hand-rolled layout chosen over `dagre`; rationale in "Key Decisions" below.
- **Plugin workflow portability**: N/A — this PR doesn't add a new wheel workflow.

## Key Decisions (call out for downstream implementers)

### D-1 — Layout library choice (FR-1): hand-rolled topological-rank, NOT dagre

| Option | Pro | Con |
|---|---|---|
| **Hand-rolled topological-rank** (chosen) | ~150 LOC, no new dep, exact control over team-step + expanded-sub-DAG semantics, deterministic for screenshot tests | implementer must write + test the algorithm |
| dagre | mature, drop-in for layered DAGs | ~250 KB transitive (dagre + lodash), TypeScript types thin (community-maintained `@types/dagre`), opaque output for our team-step and expanded-sub-DAG edge cases |

**Decision**: hand-rolled. The viewer already imports React Flow which positions nodes from explicit `x, y` coords — we control the algorithm fully. Bundle weight matters: this is a Docker-served Next.js app and the marginal cost of dagre exceeds the LOC savings.

**Algorithm sketch** (for impl-graph):

1. Build adjacency list from `next-step` (default cursor → next index), `if_zero`/`if_nonzero` (branch), `skip` (jump), `substep` (loop body anchor → child).
2. Detect cycles (treat `loop` substep back-edge as the only legal cycle; mark and remove for layering).
3. Layer by topological rank (longest-path layering): `rank(v) = max(rank(parent) + 1) for each parent`.
4. Within each rank, assign x positions by parent-centroid heuristic to minimize edge crossings (simple median sort, two passes).
5. For expanded sub-workflows: recurse into the same algorithm on the sub-DAG, offset the result by parent's `(x, y) + (0, 200)`, render the dashed-cyan `expanded-` edge.
6. For team-step fan-in: gather all `teammate` steps with the same `team` ref, route their out-edges to the corresponding `team-wait` node.

### D-2 — Lint module API surface (FR-4)

```ts
// viewer/src/lib/lint.ts (NEW)

export type LintSeverity = 'error' | 'warning'

export interface LintIssue {
  severity: LintSeverity
  stepId: string          // empty string if workflow-level (e.g. duplicate IDs surfaced once)
  ruleId: string          // 'L-001'..'L-010'
  message: string         // one-line, human-readable
}

export interface LintContext {
  // Snapshot of installed_plugins.json keys (e.g. ['kiln@1.0', 'wheel@2.0']).
  // Empty array = unknown / not loaded.
  installedPlugins: string[]
  // Source-discovered plugin short names (e.g. ['kiln', 'wheel']) from the registered project.
  sourceDiscoveredPlugins: string[]
}

// Pure, deterministic, no I/O.
export function lintWorkflow(wf: Workflow, ctx?: LintContext): LintIssue[]
```

- `LintContext` is optional — when omitted, L-007 (`requires_plugins` reference check) is skipped, not failed. This keeps `lintWorkflow` callable from contexts that don't have the plugin registry loaded.
- Output is sorted: errors before warnings, then by step index, then by ruleId, so screenshots are deterministic.
- Tests live at `viewer/src/lib/lint.test.ts`. One positive + one negative case per rule = 20 cases minimum (see SC-014).

### D-3 — Diff data shape (FR-5)

```ts
// viewer/src/lib/diff.ts (NEW)

export interface FieldDiff {
  path: string         // dot-path within the step, e.g. "agent.model"
  left: unknown
  right: unknown
}

export interface ModifiedStep {
  id: string
  leftStep: Step
  rightStep: Step
  fieldDiff: FieldDiff[]   // sorted by path
}

export interface WorkflowDiff {
  added: Step[]            // present in right, absent in left (by id)
  removed: Step[]          // present in left, absent in right (by id)
  modified: ModifiedStep[] // same id on both sides, different content
  unchanged: Step[]        // identical (deep-equal) on both sides
}

export function diffWorkflows(left: Workflow, right: Workflow): WorkflowDiff
```

- Steps without an `id` (rare but possible per current type) are paired by index when both sides have them at the same index; otherwise they fall through to added/removed.
- Field diff uses key-by-key shallow recursion over the Step JSON; arrays compared element-wise after JSON-stringify (sufficient for v1).
- Unchanged steps included so the diff view can still render the muted "context" rows.

### D-4 — File ownership map (avoids implementer conflicts)

| Implementer | Owns these files |
|---|---|
| **impl-data-layer** | `viewer/src/lib/types.ts` (extend StepType + add discoveryMode field on Workflow), `viewer/src/lib/lint.ts` (NEW), `viewer/src/lib/lint.test.ts` (NEW), `viewer/src/lib/diff.ts` (NEW), `viewer/src/lib/diff.test.ts` (NEW), `viewer/src/lib/discover.ts` (extend with `projectPath` parameter + source scan) |
| **impl-graph** | `viewer/src/lib/layout.ts` (NEW — extracts logic out of FlowDiagram), `viewer/src/lib/layout.test.ts` (NEW), `viewer/src/components/FlowDiagram.tsx` (rewrite `buildGraphLayout` to call `buildLayout`), `viewer/src/components/WorkflowNode.tsx` (extend with team-step icons + colors + body fields), `viewer/src/components/StepRow.tsx` (extend with `diffStatus` prop), `viewer/src/app/viewer.css` (node-related rules: team-step colors, fan-in, expanded sub-DAG cluster), **delete** `plugin-wheel/skills/wheel-view/viewer.html` |
| **impl-shell** | `viewer/src/components/Sidebar.tsx` (search input, step-type chip filter, multi-select shift-click, lint badge consumer, group counts, empty-state), `viewer/src/components/RightPanel.tsx` (Lint tab + team-step section), `viewer/src/components/WorkflowDetail.tsx` (lint banner above FlowDiagram, diff vs detail mode switch), `viewer/src/components/DiffView.tsx` (NEW — side-by-side step list using StepRow + diffStatus), `viewer/src/app/page.tsx` (empty states, project registration form prominence), `viewer/src/app/viewer.css` (shell/sidebar/page/diff rules — non-node) |

**No file owned by two implementers.** `viewer.css` is split: node-related rules (impl-graph) vs shell/sidebar/page/diff rules (impl-shell). If the implementers find overlap during work, they coordinate via SendMessage on the team-lead.

### D-5 — Test substrate

- `vitest` already configured at the plugin-wheel level — reuse for `viewer/src/lib/*.test.ts`. Add a `viewer/vitest.config.ts` if the existing plugin-wheel config doesn't pick up the viewer subtree (impl-data-layer to verify).
- `npm test` from `viewer/` runs all `*.test.ts` under `viewer/src/`.
- Coverage gate: `npm run test:coverage` must report ≥80% on `viewer/src/lib/*.ts`. UI components are out-of-scope for unit-test coverage and covered by qa-engineer screenshot QA instead.
- The deliberately-broken lint fixture: `plugin-wheel/tests/lint-fixture-broken.json` (committed by impl-data-layer alongside `lint.test.ts`). Used as a positive-case fixture for L-001 / L-003 / L-005 / L-008.

## Project Structure

### Documentation (this feature)

```text
specs/wheel-viewer-definition-quality/
├── plan.md                          # This file
├── spec.md                          # Feature spec
├── tasks.md                         # /tasks output
├── contracts/
│   └── interfaces.md                # Single source of truth for function signatures
├── agent-notes/                     # Friction logs from each agent
│   ├── specifier.md                 # Created at end of /specify+/plan+/tasks pass
│   ├── impl-data-layer.md           # Created by data-layer implementer
│   ├── impl-graph.md                # Created by graph implementer
│   └── impl-shell.md                # Created by shell implementer
└── screenshots/                     # 12 PNGs from qa-engineer
    ├── 01-auto-layout-team-static.png
    ├── 02-auto-layout-team-static-expanded.png
    ├── 03-auto-layout-branch.png
    ├── 04-team-step-rendering.png
    ├── 05-search.png
    ├── 06-filter.png
    ├── 07-lint-clean.png
    ├── 08-lint-errors.png
    ├── 09-diff.png
    ├── 10-source-discovery.png
    ├── 11-empty-no-projects.png
    └── 12-empty-no-workflows.png
```

### Source Code (repository root)

```text
plugin-wheel/
├── skills/wheel-view/
│   └── viewer.html                  # DELETED (FR-8.1)
├── tests/
│   └── lint-fixture-broken.json     # NEW — deliberately broken; consumed by lint.test.ts only
└── viewer/
    └── src/
        ├── app/
        │   ├── page.tsx             # Empty-state hooks, project-form prominence (impl-shell)
        │   └── viewer.css           # Split: node rules (impl-graph), shell rules (impl-shell)
        ├── components/
        │   ├── DiffView.tsx         # NEW — side-by-side step list (impl-shell)
        │   ├── FlowDiagram.tsx      # Rewritten buildGraphLayout → calls buildLayout (impl-graph)
        │   ├── RightPanel.tsx       # Lint tab + team-step section (impl-shell)
        │   ├── Sidebar.tsx          # Search + filter + multi-select + lint badge + group counts (impl-shell)
        │   ├── StepRow.tsx          # Extended with diffStatus prop (impl-graph)
        │   ├── WorkflowDetail.tsx   # Lint banner + diff/detail mode switch (impl-shell)
        │   └── WorkflowNode.tsx     # Team-step icons + colors + body fields (impl-graph)
        └── lib/
            ├── api.ts               # (untouched)
            ├── diff.ts              # NEW — diffWorkflows pure function (impl-data-layer)
            ├── diff.test.ts         # NEW (impl-data-layer)
            ├── discover.ts          # Extended with optional projectPath param (impl-data-layer)
            ├── layout.ts            # NEW — buildLayout pure function (impl-graph)
            ├── layout.test.ts       # NEW (impl-graph)
            ├── lint.ts              # NEW — lintWorkflow + LintIssue + LintContext (impl-data-layer)
            ├── lint.test.ts         # NEW (impl-data-layer)
            ├── projects.ts          # (untouched)
            └── types.ts             # Extended StepType + Workflow.discoveryMode (impl-data-layer)
```

**Structure Decision**: single project (frontend-only Next.js app). All source under `plugin-wheel/viewer/src/`. Tests collocated with implementation (`lib/*.test.ts`).

## Phase 0 — Research

No research artifact required for this PR. Decisions D-1 through D-5 are derived from existing fixture inventory + the PRD's Implementation Notes section. The "library vs hand-rolled" decision is documented above (D-1) with explicit rejection rationale for dagre.

## Phase 1 — Design & Contracts (this output)

- ✅ `spec.md` written — covers FR-1 through FR-8, SC-001 through SC-014, all 5 user stories.
- ✅ `plan.md` written (this file) — covers 5 key decisions, file ownership map, project structure, test substrate.
- ✅ `contracts/interfaces.md` (next file) — exact signatures for the 4 new pure functions + the type extensions.
- ⏭ `tasks.md` written by `/tasks` — Phase 1 (types), Phase 2 (parallel data/graph/shell), Phase 3 (qa screenshots).

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| **3 concurrent implementers** (impl-data-layer, impl-graph, impl-shell) | The 8 FRs split cleanly along data / graph / shell axes. Single-implementer would serialize ~600 LOC of independent work. | Single implementer = wall-clock ~3× longer; tasks.md retains explicit phase ordering so coordination cost stays low. |
| **`viewer.css` split across two implementers** | The only file edited by both impl-graph and impl-shell. Both need separate sections of it. | Migrating to CSS modules per component is out of scope for this PR; explicit section split + commit-after-each-task is sufficient. |
| **No Playwright CI wiring** | qa-engineer captures screenshots manually against a running container; CI wiring is a separate scope. | The PRD's non-goals call this out explicitly; punting to runtime-ops PRD. |
