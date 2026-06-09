# QA Test Matrix — wheel-viewer-definition-quality

Generated from: `specs/wheel-viewer-definition-quality/spec.md` + PRD AC-1..AC-12.
Date: 2026-05-09
Owner: qa-engineer (task #5 / T030..T041)

## Acceptance gate

The PRD ships when **every screenshot below has been captured from a real running session and committed under `specs/wheel-viewer-definition-quality/screenshots/`**. Each row maps 1:1 to a Phase-3 task in `tasks.md` (T030..T041) and a Success Criterion in `spec.md` (SC-001..SC-012).

Capture path: **Path A** (Next.js dev server on `http://localhost:3000`) for speed; promote to **Path B** (Docker on `:3847`) only if a discrepancy is suspected. Both paths produce identical UI per PRD Implementation Notes.

| #  | Acceptance Criterion (AC)                       | Source         | Steps to drive UI                                                                                                                                                                                                       | Expected Result (what the screenshot must prove)                                                                              | Depends on                | Priority | Status      |
|----|-------------------------------------------------|----------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------|---------------------------|----------|-------------|
| 1  | AC-1 — auto-layout normal (team-static)         | US1 / SC-001   | Register repo → click `bifrost-minimax-team-static` → screenshot FlowDiagram                                                                                                                                            | All 8 steps visible, NO node overlap, edges follow layered DAG, type-specific badges on team-create / teammate / team-wait / team-delete | T013 + T014               | P0       | untested    |
| 2  | AC-2 — auto-layout expanded sub-DAG             | US1 / SC-002   | From AC-1 state → expand `worker-1` teammate sub-workflow → screenshot                                                                                                                                                  | Sub-DAG renders below parent step as self-contained cluster, no overlap, dashed-cyan `expanded-` edge present                  | T013 + T024               | P0       | untested    |
| 3  | AC-3 — auto-layout branch fan-out + rejoin      | US1 / SC-003   | Click a workflow with `branch` + `if_zero` / `if_nonzero` (e.g. `bifrost-minimax-smoke` or any workflow under `workflows/tests/*.json` with branches) → screenshot FlowDiagram                                          | Both branches visible; rejoin point cleanly rendered (not orphan columns)                                                      | T013                      | P0       | untested    |
| 4  | AC-4 — team-step rendering (mixed-model)        | US1 / SC-004   | Click `bifrost-minimax-team-mixed-model` → screenshot FlowDiagram                                                                                                                                                       | All 7 step types render (`command`, `team-create`, 2× `teammate`, `team-wait`, `command`, `team-delete`); type-specific colors/icons/fields; **zero `?` placeholders** | T013 + T014               | P0       | untested    |
| 5  | AC-5 — sidebar search                           | US3 / SC-005   | In sidebar → type `team-` into the `<input type=search>` → screenshot                                                                                                                                                   | Only workflows with `team-` in name remain visible; group counts reflect post-filter visible counts                            | T018                      | P0       | untested    |
| 6  | AC-6 — sidebar step-type filter                 | US3 / SC-006   | Click the `branch` chip in the chip strip → screenshot sidebar + main panel                                                                                                                                              | Only workflows containing ≥1 branch step remain visible; "clear all" button visible                                            | T019 + T020               | P0       | untested    |
| 7  | AC-7 — lint clean                               | US5 / SC-007   | Click `bifrost-minimax-smoke` → screenshot sidebar row + RightPanel Lint tab                                                                                                                                            | Sidebar row shows green-check badge; Lint tab is empty                                                                         | T021 + T025               | P0       | untested    |
| 8  | AC-8 — lint errors                              | US5 / SC-008   | Register `plugin-wheel/tests/` as a project so the broken fixture surfaces (or rely on its inclusion in fixture discovery) → click `lint-fixture-broken` → screenshot Lint tab                                          | Lint tab lists L-001 (missing id) + L-003 (unresolved branch) + L-005 (loop without substep) + L-008 (team-create without team_name); sidebar badge red-X | T021 + T025 + T005        | P0       | untested    |
| 9  | AC-9 — diff view                                | US4 / SC-009   | Shift-click `team-static` then shift-click `team-haiku-fanout` → click "Diff" affordance → screenshot                                                                                                                   | Side-by-side layout; header summary `X added, Y removed, Z modified, W unchanged` with non-zero added or modified counts; per-step coloring (green/red/yellow/muted) | T022 + T026               | P0       | untested    |
| 10 | AC-10 — source-checkout discovery               | US2 / SC-010   | Register `/Users/ryansuematsu/Documents/github/personal/ai-repo-template` as a project → screenshot sidebar                                                                                                            | kiln/clay/shelf/trim plugin groups show entries with `(source)` tag (and `(installed)` peers if installed)                     | T009 + T023               | P0       | untested    |
| 11 | AC-11 — empty state, no projects                | US3 / SC-011   | Fresh container/dev-server with zero registered projects → screenshot main panel                                                                                                                                        | Onboarding panel: "Add a project path to view its workflows" + `/Users/you/projects/my-app` placeholder                        | T028                      | P0       | untested    |
| 12 | AC-12 — empty state, no workflows               | US3 / SC-012   | Register a temp project path with no `workflows/` dir → click that project → screenshot                                                                                                                                | Explanatory panel: "No workflows discovered. Run `/wheel:wheel-init` in this project, or check that `<projectPath>/workflows/` exists." | T028                      | P0       | untested    |

## Tooling

- **Browser**: Playwright Chromium (already installed at v1.59.1 via `playwright` runtime dep in `viewer/package.json`).
- **Capture command**: `await page.screenshot({ path: 'specs/wheel-viewer-definition-quality/screenshots/<NN>-<slug>.png', fullPage: true })`.
- **Viewport**: 1440×900 (matches `playwright.config.ts` default in `.kiln/qa/config/`).
- **Headless**: yes by default (set `headless: false` only when interactive verification is needed).

## Credentials

NONE required. Viewer is read-only:
- Reads `~/.claude/plugins/installed_plugins.json` (mounted RO in Path B Docker).
- Reads `<registeredProjectPath>/workflows/` and `<registeredProjectPath>/plugin-*/workflows/` from the host filesystem.
- No API keys, no auth, no test accounts.

## Execution flow

1. **Wait** for impl-data-layer / impl-graph / impl-shell to signal readiness per row's "Depends on" column.
2. **Drive** the running viewer (Path A by default) via a Playwright capture script.
3. **Verify** each PNG visually opens and shows what the row's "Expected Result" requires.
4. **Re-shoot** if a defect is found; SendMessage the responsible implementer with severity + suggested fix direction; continue with un-blocked rows.
5. **Commit** all 12 PNGs under `specs/wheel-viewer-definition-quality/screenshots/`.
6. **Run** `/kiln:kiln-qa-pipeline` and `/kiln:kiln-qa-final` for the final pass.
7. **SendMessage** audit-pr that QA is complete.
