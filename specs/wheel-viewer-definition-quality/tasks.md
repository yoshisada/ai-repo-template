---
description: "Task list for wheel-viewer-definition-quality"
---

# Tasks: Wheel Viewer — Definition-Quality Pass

**Input**: Design documents from `/specs/wheel-viewer-definition-quality/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), contracts/interfaces.md (required)
**Tests**: Required for `viewer/src/lib/*.ts` (≥80% coverage gate). UI components tested via qa-engineer screenshots.

**Organization**: Tasks are grouped by phase. Phase 1 unblocks Phase 2's three parallel implementer tracks. Phase 3 (qa screenshots) runs alongside Phase 2.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task supports (US1=team-rendering, US2=source-discovery, US3=empty-state, US4=diff, US5=lint)
- File paths are absolute under repo root.

---

## Phase 1: Foundational — Type extension (BLOCKS everything else)

**Purpose**: Extend `StepType` and `Workflow.discoveryMode` so impl-graph and impl-shell can reference the new types in TypeScript.

**Owner**: impl-data-layer (single agent — small, fast, blocks others)

**⚠️ CRITICAL**: impl-graph and impl-shell are blocked on T001+T002 completion. Confirm via SendMessage to team-lead when this checkpoint passes.

- [X] T001 [US1] Extend `StepType` in `plugin-wheel/viewer/src/lib/types.ts` to include `'team-create' | 'team-wait' | 'team-delete' | 'teammate'` (FR-2.1). Add `discoveryMode?: 'installed' | 'source' | 'local'` to `Workflow` (FR-6.3). Add `team_name?`, `team?`, `workflow?`, `assign?`, `workflow_definition?` to `Step` (FR-2.3). Match contracts/interfaces.md exactly.
- [X] T002 [US2] Extend `DiscoveredWorkflow` in `plugin-wheel/viewer/src/lib/discover.ts` with the same `discoveryMode?` field (FR-6.3). No behavior changes yet — type-only.

**Checkpoint**: Type extensions land. impl-graph + impl-shell can now reference team-step types. impl-data-layer continues into Phase 2A (lint, diff, discover.ts behavior changes).

---

## Phase 2A: Data layer (impl-data-layer)

**Goal**: Pure-functional `lintWorkflow`, `diffWorkflows`, and source-checkout `discoverPluginWorkflows`. All exhaustively unit-tested.

### Tests for User Story 5 (Lint) — write FIRST, expect FAIL

- [X] T003 [P] [US5] Write `plugin-wheel/viewer/src/lib/lint.test.ts` covering all 10 rules (L-001…L-010), one positive + one negative case per rule. Reference SC-014. Reference `plugin-wheel/tests/lint-fixture-broken.json` (created in T005) for the multi-rule positive fixture. Tests MUST fail until T004 lands.
- [X] T004 [US5] Implement `plugin-wheel/viewer/src/lib/lint.ts` matching `contracts/interfaces.md` exactly: `lintWorkflow`, `workflowLintBadge`, `LintIssue`, `LintContext`, `LintBadge`, `LintSeverity`. FR-4.4 — pure, deterministic, no I/O. Sort: errors before warnings, then by step index, then by ruleId.
- [X] T005 [US5] Create `plugin-wheel/tests/lint-fixture-broken.json` — a deliberately-broken workflow that triggers L-001 (step missing id), L-003 (branch target unresolved), L-005 (loop without substep), L-008 (team-create without team_name). One workflow, ≥4 issues. NOT registered for `/wheel:wheel-test`.

### Tests for User Story 4 (Diff) — write FIRST, expect FAIL

- [X] T006 [P] [US4] Write `plugin-wheel/viewer/src/lib/diff.test.ts`: cases for all-added, all-removed, mixed modifications, unchanged passthrough, ID-collision pairing, and unidentified-step index pairing. Tests MUST fail until T007 lands.
- [X] T007 [US4] Implement `plugin-wheel/viewer/src/lib/diff.ts` matching `contracts/interfaces.md`: `diffWorkflows`, `WorkflowDiff`, `ModifiedStep`, `FieldDiff`. FR-5.3 — id-keyed alignment with index fallback for unidentified steps.

### Source-checkout discovery (US2)

- [ ] T008 [P] [US2] Write `plugin-wheel/viewer/src/lib/discover.test.ts` (or extend if exists): cases for `discoverPluginWorkflows()` (no projectPath, baseline preserved), `discoverPluginWorkflows(projectPath)` with `plugin-*/` siblings present and absent, `discoverSourcePluginWorkflows(projectPath)`. Tests MUST fail until T009 lands.
- [ ] T009 [US2] Extend `plugin-wheel/viewer/src/lib/discover.ts`: add optional `projectPath` param to `discoverPluginWorkflows`; tag `discoveryMode='installed'` on the existing path; add `discoverSourcePluginWorkflows` exported helper that scans `<projectPath>/plugin-*/` and tags `discoveryMode='source'` (FR-6.1, FR-6.2). Backwards-compat: legacy callers without `projectPath` get the same result as today.

### Coverage gate

- [ ] T010 [US5][US4][US2] Run `vitest run --coverage` from `plugin-wheel/viewer/`. All lib/*.ts files MUST achieve ≥80%. Fix gaps before marking complete.

**Checkpoint**: data layer green. impl-graph + impl-shell can import `lintWorkflow`, `workflowLintBadge`, `diffWorkflows`, and `discoverSourcePluginWorkflows`.

---

## Phase 2B: Graph layer (impl-graph) — runs in parallel with 2A after T001+T002

**Goal**: Layered auto-layout, team-step rendering, hygiene cleanup. Visually verified by qa-engineer.

### Tests for FR-1 (layout) — write FIRST, expect FAIL

- [ ] T011 [P] [US1] Write `plugin-wheel/viewer/src/lib/layout.test.ts`: cases for linear chain, branch fan-out + rejoin, loop substep cluster + back-edge, parallel siblings, expanded sub-DAG offset, team-step fan-in, no-overlap invariant on every fixture under `plugin-wheel/tests/*.json`. Tests MUST fail until T012 lands.
- [ ] T012 [US1] Implement `plugin-wheel/viewer/src/lib/layout.ts` matching `contracts/interfaces.md`: `buildLayout`, `GraphNode`, `GraphEdge`, `LayoutResult`, the three layout constants. Hand-rolled layered topological-rank — NO new npm dep. Algorithm sketch in plan.md D-1.

### FlowDiagram + WorkflowNode rewrite

- [ ] T013 [US1] Rewrite `plugin-wheel/viewer/src/components/FlowDiagram.tsx`: replace `buildGraphLayout` with `buildLayout(workflow, expandedWorkflows)`. Pass through React Flow nodes/edges from the result. Preserve existing `expanded-` dashed-cyan edge handling.
- [ ] T014 [P] [US1] Extend `plugin-wheel/viewer/src/components/WorkflowNode.tsx`: add icons (`team-create: ⊕`, `team-wait: ⊞`, `team-delete: ⊖`, `teammate: ◐`) + colors (team-color-family from existing palette) + body fields per type (FR-2.2, FR-2.3).
- [ ] T015 [P] [US4] Extend `plugin-wheel/viewer/src/components/StepRow.tsx`: add `diffStatus?` and `fieldDiff?` props (FR-5.2). Render diff highlighting (added/removed/modified/unchanged) + expand-on-click for fieldDiff. Default behavior unchanged when props omitted.
- [ ] T016 [P] [US1] Add team-step CSS rules to `plugin-wheel/viewer/src/app/viewer.css`: team-* node colors, fan-in edge styling, expanded sub-DAG cluster boundaries. Coordinate with impl-shell to avoid clobbering shell rules.

### Hygiene (FR-8)

- [ ] T017 [US1] Delete `plugin-wheel/skills/wheel-view/viewer.html` (FR-8.1). Verify no other file references it: `git grep -F viewer.html plugin-wheel/` returns zero matches (FR-8.2 / SC-013).

**Checkpoint**: graph layer renders all step types with no overlap. qa-engineer can capture AC-1, AC-2, AC-3, AC-4 screenshots.

---

## Phase 2C: Shell layer (impl-shell) — runs in parallel with 2A + 2B after T001+T002

**Goal**: Sidebar search/filter/multi-select/lint badge, RightPanel Lint tab, DiffView, empty-state UX.

### Sidebar (FR-3 + FR-4.1 + FR-5.1)

- [ ] T018 [US3] Extend `plugin-wheel/viewer/src/components/Sidebar.tsx`: add `<input type="search">` above the workflow list (FR-3.1, real-time substring filter, case-insensitive).
- [ ] T019 [US3] Add step-type filter chip strip below search input (FR-3.2). Chips dedupe across all discovered workflows. Click toggles filter. Multi-chip filters are AND.
- [ ] T020 [US3] Compose search + chip filters as intersect; render "clear all" button when ≥1 filter is active (FR-3.3). Group counts reflect post-filter visible counts: `kiln (12 of 27)` (FR-3.4).
- [ ] T021 [US5] Render lint badge next to workflow name: green check (clean), yellow triangle (warnings), red X (errors). Consume `workflowLintBadge` from `lib/lint` (FR-4.1).
- [ ] T022 [US4] Add shift-click multi-select for workflow rows. Track selected set. With exactly two selected, expose a "Diff" affordance (FR-5.1).
- [ ] T023 [US2] Render `(source)` suffix tag on workflow rows when `discoveryMode === 'source'` (FR-6.3). Source AND installed both visible — group by plugin name, distinguish by tag.

### RightPanel (FR-2.4 + FR-4.2 + FR-7.3)

- [ ] T024 [US1] Extend `plugin-wheel/viewer/src/components/RightPanel.tsx`: render type-specific sections for `team-create` / `team-wait` / `team-delete` / `teammate` (FR-2.3, FR-2.4). Show full `assign` JSON for teammate. Show inline `workflow_definition` when present.
- [ ] T025 [US5] Add Lint tab to RightPanel (alongside Detail). Render LintIssue[] rows: severity icon, step ID, message, "jump to step" affordance (FR-4.2). Empty state: "No lint issues."

### DiffView (FR-5.2)

- [ ] T026 [US4] Create `plugin-wheel/viewer/src/components/DiffView.tsx`: side-by-side step lists using `StepRow` with `diffStatus`. Header: `X added, Y removed, Z modified, W unchanged` (FR-5.4). `onClose` returns to single-workflow view.

### WorkflowDetail (FR-7.3)

- [ ] T027 [US5] Extend `plugin-wheel/viewer/src/components/WorkflowDetail.tsx`: when active workflow has lint errors, render a banner above FlowDiagram offering to switch to the Lint tab (FR-7.3). Add diff vs detail mode switch — driven by Sidebar's selected-set count.

### Empty states + page shell (FR-7)

- [ ] T028 [US3] Extend `plugin-wheel/viewer/src/app/page.tsx`: zero-projects renders the "Add a project path to view its workflows" onboarding panel with `/Users/you/projects/my-app` placeholder (FR-7.1). Project + missing `workflows/` renders the "No workflows discovered. Run `/wheel:wheel-init`…" panel (FR-7.2).
- [ ] T029 [P] [US3] Add shell/sidebar/page/diff CSS rules to `plugin-wheel/viewer/src/app/viewer.css` (search input, chip strip, clear-all button, lint-badge variants, diff added/removed/modified/unchanged tints, empty-state panels). Coordinate with impl-graph (T016) to keep node-rule and shell-rule sections separate.

**Checkpoint**: shell layer integrates lint, diff, search/filter, source-tag, and empty-state. qa-engineer can capture AC-5..AC-12 screenshots.

---

## Phase 3: Visual QA (qa-engineer) — runs in parallel with Phase 2B + 2C

**Goal**: Capture all 12 acceptance-criteria screenshots from a real running session.

**Owner**: qa-engineer

- [ ] T030 [P] [US1] Capture `screenshots/01-auto-layout-team-static.png` (AC-1 / SC-001) once T013 lands.
- [ ] T031 [P] [US1] Capture `screenshots/02-auto-layout-team-static-expanded.png` (AC-2 / SC-002) once T013 + T024 land.
- [ ] T032 [P] [US1] Capture `screenshots/03-auto-layout-branch.png` (AC-3 / SC-003) once T013 lands.
- [ ] T033 [P] [US1] Capture `screenshots/04-team-step-rendering.png` (AC-4 / SC-004) once T013 + T014 land.
- [ ] T034 [P] [US3] Capture `screenshots/05-search.png` (AC-5 / SC-005) once T018 lands.
- [ ] T035 [P] [US3] Capture `screenshots/06-filter.png` (AC-6 / SC-006) once T019 + T020 land.
- [ ] T036 [P] [US5] Capture `screenshots/07-lint-clean.png` (AC-7 / SC-007) once T021 lands.
- [ ] T037 [P] [US5] Capture `screenshots/08-lint-errors.png` (AC-8 / SC-008) once T021 + T025 + T005 land.
- [ ] T038 [P] [US4] Capture `screenshots/09-diff.png` (AC-9 / SC-009) once T026 + T022 land.
- [ ] T039 [P] [US2] Capture `screenshots/10-source-discovery.png` (AC-10 / SC-010) once T009 + T023 land.
- [ ] T040 [P] [US3] Capture `screenshots/11-empty-no-projects.png` (AC-11 / SC-011) once T028 lands.
- [ ] T041 [P] [US3] Capture `screenshots/12-empty-no-workflows.png` (AC-12 / SC-012) once T028 lands.

**Checkpoint**: all 12 screenshots committed. PR description embeds them inline.

---

## Phase 4: Audit + Smoke + PR

**Owner**: prd-auditor → smoke-tester → team-lead (PR)

- [ ] T042 PRD audit: every PRD requirement mapped to an FR; every FR mapped to ≥1 implementation file + ≥1 test (or screenshot). Document blockers in `specs/wheel-viewer-definition-quality/blockers.md` if any.
- [ ] T043 Smoke test: build the viewer Docker image, start the container on port 3847, hit `http://localhost:3847`, confirm onboarding panel renders. Tear down. Pass/fail report.
- [ ] T044 Coverage gate: re-run `vitest run --coverage` from `viewer/`; confirm ≥80% on `lib/*.ts`.
- [ ] T045 Hygiene gate: `git grep -F viewer.html plugin-wheel/` returns zero matches (SC-013).
- [ ] T046 Create PR with `build-prd` label. Body embeds all 12 screenshots inline. Title: `wheel-viewer: definition-quality pass (FR-1..FR-8)`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1**: No dependencies — starts immediately.
- **Phase 2A / 2B / 2C**: All depend on Phase 1 completion (T001 + T002). After that, they run **in parallel**.
- **Phase 3 (qa)**: Per-screenshot dependencies are listed inline; qa-engineer captures incrementally as the relevant Phase 2 tasks land.
- **Phase 4 (audit + smoke + PR)**: Depends on all Phase 2 + Phase 3 tasks.

### Critical Path

T001 → T012 (layout) → T013 (FlowDiagram rewrite) → T030..T033 (graph screenshots) → T042..T046.

### Parallel Opportunities

- T003 / T006 / T008 / T011 / T014 / T015 / T016 / T029 / T030..T041 all `[P]`.
- The three implementer tracks (2A, 2B, 2C) run in parallel after Phase 1.

---

## Notes

- `[P]` tasks = different files, no dependencies.
- `[Story]` label maps task to spec user story (US1..US5) for traceability.
- Tests written BEFORE implementation per Article VIII; tests MUST fail until implementation lands.
- Commit after each task or logical group. Implementers commit after each phase per build-prd convention.
- Implementers MUST mark `[X]` immediately after completing a task — hooks check this before allowing further `src/` edits.
- Every function MUST reference its FR in a top-of-function comment.
- File ownership map (plan.md D-4 + contracts/interfaces.md) is non-negotiable. Coordinate via SendMessage on team-lead if overlap is discovered.
