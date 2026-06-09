# qa-engineer friction notes — wheel-viewer-definition-quality

## Path choice: Path A (Next.js dev server on :3000)

Used `npm run dev` from `plugin-wheel/viewer/` (Next.js 15.1.0). Faster iteration than Docker (Path B) because:
- Hot-reload picks up impl-data-layer / impl-graph / impl-shell commits without rebuild.
- Capture script can probe API directly (`POST /api/projects` + `GET /api/workflows?projectId=...`) before Playwright runs to confirm backend state.
- `?q=...` and `?types=...` URL-state in the Sidebar (FR-3 implementation note) makes filter screenshots driveable via plain navigation, skipping fragile selector-typing where possible.

Path A trade-off: the Docker container also mounts `~/.claude:/host_home/.claude:ro` for installed-plugin discovery. Path A reads `~/.claude` directly (no mount), so AC-10 (source discovery) screenshots will exercise the same discover.ts code but show installed plugins from the host's real `~/.claude/plugins/installed_plugins.json`. Acceptable per PRD Implementation Notes ("either path is fine — goal is to prove UI renders correctly").

Promotion to Path B (Docker on :3847) reserved for the smoke-test step (T043) and any case where Path A produces a visual divergence the audit-pr would care about.

## Capture-script architecture

Single Node ESM script at `.kiln/qa/tests/capture.mjs` — uses the `playwright` runtime dep already in `viewer/package.json` (no `@playwright/test` needed). Resolves `playwright` via `createRequire(viewer/package.json)` because Node ESM doesn't walk NODE_PATH. Each AC is one async function in a `captures` map; per-AC invocation via `node capture.mjs 5 6` so I can re-shoot a single AC without rerunning the whole suite.

## Per-AC log

### AC-5 (search) and AC-6 (filter) — first pass

Both captured cleanly on second attempt. **First attempt produced byte-identical PNGs both showing a Next.js runtime-error overlay** (`TypeError: Cannot read properties of undefined (reading 'length')` at `RightPanel.tsx:147` — the `lintIssues.length > 0` line in the tab badge). The error self-resolved between the first run and the second run — likely a hot-reload race where impl-shell's RightPanel had landed before impl-data-layer's `lintWorkflow` import was fully wired through `useMemo`.

Probed via a separate playwright script (`pageerror` + `console error` listeners) and could NOT reproduce. impl-data-layer marked task #2 complete between attempts, which lines up with the "lint module just shipped → useMemo now resolves to an array" theory.

**Action**: did NOT block on this; re-shot and committed. If it recurs, will message impl-shell to add a defensive `lintIssues = lintIssues ?? []` default and surface the earlier failure mode.

### AC-1 (auto-layout) — captured cleanly first try

`tests/team-static` selected, 8 steps, layered DAG: setup → create-team → 3 teammates fanned out at same rank → wait-all (fan-in) → report → cleanup. Type-specific colors / icons present (⊕, ◐, ⊞, ⊖). No node overlap.

### AC-2 (expanded sub-DAG) — RESOLVED

Two-round fix loop:
1. First "fix ready" signal from impl-shell was premature (committed `ade5184e` locally but not pushed). Tested → still failed. Sent re-test report.
2. team-lead caught the missing push; impl-shell pushed. Verified the type-gate widening landed:
   - `RightPanel.tsx:240–242` now reads `(stepType === 'workflow' || stepType === 'teammate') && (s.workflow_name || s.workflow)`.
   - `app/page.tsx:301` mirrors the same widening on the auto-expand-on-double-click path.
   - StepDetail also gained an "Expand teammate sub-workflow" button.
   - Bonus belt-and-suspenders: `lintIssues ?? []` defensive guard at `RightPanel.tsx:147` — same line as the transient TypeError I caught earlier.
3. Re-captured `02-auto-layout-team-static-expanded.png`: worker-1 expanded with `−`, sub-workflow `▼ tests/team-sub-worker` inlined below it (3 sub-steps), FlowDiagram renders the dashed-cyan `expanded-` edge to the inlined sub-DAG nodes. Hash now meaningfully different from AC-1.

### AC-3 (branch fan-out + rejoin) — captured cleanly first try

`tests/branch-multi`, 5 steps. detect-language → check-js (orange B badge) → analyze-js / fallback-analysis at same rank → write-report at rejoin. Layered DAG, no overlap.

### AC-4 (team-step rendering) — captured cleanly first try

`tests/team-mixed-model`, 7 steps, all 7 step types render with type-specific colors / icons / fields. Zero `?` placeholders. Right panel shows step-type badges (C, ⊕, ◐, ⊞, C, ⊖). FR-2.2 / FR-2.3 satisfied.

### AC-7 (lint clean) — captured cleanly

`tests/agent-chain` selected, sidebar shows green ✓ badge, LINT tab active with "Lint clean — no issues found." text. SC-007 satisfied.

### AC-8 (lint errors) — captured cleanly with one capture-script fluke

The lint fixture is at `plugin-wheel/tests/lint-fixture-broken.json` — outside any `workflows/` tree, so neither `discoverLocalWorkflows` (scans `<projectPath>/workflows/`) nor `discoverPluginWorkflows` (scans `<plugin>/workflows/`) surfaces it. To exercise: capture-script creates a temp project under `os.tmpdir()` with `workflows/lint-fixture-broken.json` symlinked to the real fixture, registers it via API, switches to it, then clicks the Lint tab. Result is excellent — sidebar red ✕ "5", Lint tab "4" badge, all 4 expected rules surfaced (L-001/L-003/L-005/L-008) with errors-first-then-warning sort. SC-008 satisfied.

### AC-9 (diff) — captured cleanly

Shift-click on `tests/team-haiku-fanout` then `tests/team-static`, click "Diff" affordance, side-by-side DiffView appears with header summary and per-step coloring. SC-009 satisfied.

### AC-10 (source discovery) — RESOLVED (commit `bd1372f5`)

impl-shell wired `project.path` into `discoverPluginWorkflows(...)` at `route.ts:24` and migrated cache to `Map<projectPath, result>` at line 19. Re-shoot verified via direct Playwright probe: **19 `(source)` tags render live** in the Sidebar (kiln, clay, shelf, trim — all surfaced as source siblings under `plugin-*/`). API also reports `discoveryMode: source` for 19 entries (alongside 18 `installed`), proving FR-6.4's "both versions visible" requirement.

### AC-11 (empty no projects) — captured cleanly

Beautiful empty state: "Add a project to get started" headline, `/Users/you/projects/my-app` placeholder, hint about `workflows/` and `plugin-*/` directories, PROJECTS counter at 0. SC-011 satisfied.

### AC-12 (empty no workflows) — RESOLVED (commit `bd1372f5`)

impl-shell threaded `localCount` separately out of Sidebar's `onWorkflowsLoaded` callback, gated `page.tsx:354` on `activeProjectLocalCount === 0`, and restricted auto-select to `local[0]` so plugin workflows can't sneak in. Re-shoot verified: registered a temp project with no `workflows/` dir → "No workflows discovered" panel renders at the FlowDiagram center with the project path quoted and 3 actionable hints (`/wheel:wheel-init` to scaffold, `<projectPath>/workflows/` check, source-checkout repo-root hint). Sidebar still shows the globally-installed plugin workflows, which is correct behavior — they're per-user, not per-project.

### Bonus defect — DELETE /api/projects path/query mismatch — RESOLVED

While building AC-11 setup, found `lib/api.ts:apiUnregisterProject` calls `DELETE /api/projects/${id}` (path style) while `route.ts:DELETE` reads `id` from `?id=`. The UI's "remove project" × button silently 404s. impl-shell aligned `lib/api.ts:32` to query style in commit `bd1372f5`.

## Final defect summary

Four issues found during capture, all resolved in 4 commits across 2 days:

| AC  | Defect                                                  | File / line                                     | Severity   | Resolved in |
|-----|---------------------------------------------------------|-------------------------------------------------|------------|-------------|
| 2   | Teammate steps have no expand affordance                | `RightPanel.tsx:231`, `app/page.tsx:201`        | Major      | `c8dca439` (rebuilt to `ade5184e` after push gap) |
| 10  | Source-checkout discovery not wired into API route      | `app/api/workflows/route.ts:9`                  | Major      | `bd1372f5` |
| 12  | Empty-state panel gate consumes plugin workflow count   | `app/page.tsx:331` + Sidebar `onWorkflowsLoaded` | Major     | `bd1372f5` |
| —   | DELETE /api/projects path-vs-query handler mismatch     | `lib/api.ts:apiUnregisterProject` vs route.ts   | Minor (UX) | `bd1372f5` |

**All 12 ACs now SC-valid.** Each PNG verified by Read + targeted Playwright probe (e.g. `(source)` tag count, lint-tab issue count).

## Process observations

- **Cross-file integration misses are the dominant defect class on this PR.** AC-2 / AC-10 / AC-12 each had implementations that were "right" at one layer (Sidebar tag rendering, RightPanel handleToggleExpand, FR-7.2 panel) but missed the wire-up at the calling layer (renderer gate / route arg / state-ownership split). impl-shell's friction note F-9 captures this — worth a retro item: integration tests at the route + page boundary would have caught all three.
- **Local commit ≠ origin.** AC-2's "fix ready" signal arrived on a local commit that was never pushed. Caught by team-lead. Minor process glitch but worth noting that QA's verification path (workspace files via dev server) and the "shipped to origin" claim are not the same artifact.
- **Path A speed paid off.** Hot-reload picked up each impl-shell fix within seconds; no Docker rebuild waits. Total wall-clock for the three re-shoots after fixes landed: ≤ 3 minutes per AC.
- **Capture script as a debugging tool.** Each AC function in `capture.mjs` is small enough to invoke standalone (`node capture.mjs 10`). Rapid re-test loop. Worth promoting as a pattern for future visual-QA passes — the mistake is treating screenshots as test output rather than as a triggerable function.

## Outstanding

- Run `/kiln:kiln-qa-pipeline` and `/kiln:kiln-qa-final` per pipeline protocol (per team-lead briefing).
- SendMessage audit-pr that QA is complete and 12 screenshots are committed-staged.
- Mark task #5 completed once qa-final is green.
