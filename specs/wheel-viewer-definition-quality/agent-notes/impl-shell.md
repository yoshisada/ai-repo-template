# impl-shell — agent friction notes

Pipeline: wheel-viewer-definition-quality (build/wheel-viewer-definition-quality-20260509)
Owner role: impl-shell (T018–T029)
Filed: 2026-05-09

## What worked well

- **Contracts/interfaces.md was load-bearing context.** Reading it ahead of the
  "Spec ready" broadcast let me pre-design DiffView's component shape against
  the exact `WorkflowDiff`/`FieldDiff`/`ModifiedStep` types, so when impl-data-layer
  shipped `lib/diff.ts` the only integration step was a plain `import`. No
  re-design loop.
- **Phase signals via SendMessage to qa-engineer were cheap and high-value.**
  Sent four fine-grained signals (search+filter, multi-select+DiffView, lint
  badge, empty-state) so qa-engineer could parallelize screenshot capture
  against partial deliveries instead of waiting for the full PR.
- **Plain client-side URL-state via `window.history.replaceState`.** Avoided
  Next.js 15 `useSearchParams` Suspense boundary requirements by reading
  `window.location.search` once on mount and writing back via
  `replaceState`. ~12 lines for shareable `?q=...&types=...` filter links.
- **State shape lifted to page.tsx for diff/lint/tab.** `selectedForDiff` (Set
  of workflow keys), `diffPair`, and `rightPanelTab` all live in page.tsx
  rather than scattered across Sidebar/RightPanel. Made the lint banner →
  Lint tab flip a one-line setter call instead of imperative ref-passing.

## What was friction

### F-1 — Shared git index between concurrent implementer agents (HIGH PRIORITY)

We are three implementer agents (impl-data-layer, impl-graph, impl-shell) all
running in the same git checkout against the same `.git/index`. When I ran
`git add <my-files>`, my staged changes sat in the shared index alongside
impl-graph's already-staged-but-not-yet-committed FlowDiagram + StepRow +
WorkflowNode files. impl-graph then ran `git commit` and accidentally bundled
my T021/T024/T025 work (Sidebar lint badge, RightPanel team-step sections +
Lint tab) under their commit message subject "feat(viewer): FlowDiagram +
WorkflowNode + StepRow renderer (T013-T015)".

The commit (5d2473a8) is functionally correct — my files made it to HEAD —
but the git history is mislabeled and impl-graph's actual file changes ended
up unstaged in the working tree. Net effect: one commit containing my work
under another agent's subject; impl-graph's work remained in the working
tree until they re-committed.

**Mitigations the runtime should consider:**
- Use `git worktree add` per implementer so each agent has an isolated index.
- Or have agents `git stash push <my-files>` before working, `git stash pop`
  before commit, so the index only ever contains the current agent's work.
- Or surface a "last commit subject doesn't match staged files" warning hook.

For this PR I added a clarifying note in the commit message of the next
commit covering my T026 (DiffView) + T027(banner) + T028 (empty-state) work.
The team retro should pick this up as a structural improvement target —
it's the kind of bug that silently produces wrong-attribution commits and is
invisible without git-archaeology.

### F-2 — RightPanel quality gate vs spec growth

RightPanel was already at 498 LOC pre-PRD (the original step-list +
StepDetail in one file). My team-step + Lint tab additions would have pushed
it past 700 LOC. Extracting `StepDetail` to its own file dropped RightPanel
to ~280 LOC and StepDetail to ~400 LOC, both comfortably under 500. This
was the right call but it costs one extra import + one extra file, which a
size-blind audit could flag as "over-decomposition." If a future PR wants to
ship even more step-detail field types (e.g. live-state overlays in the
runtime-ops PRD), StepDetail itself will need a similar split.

### F-3 — DiffView and StepRow's diffStatus prop arrived in the same window

T026 (DiffView) consumed StepRow's new `diffStatus` + `fieldDiff` props,
which were T015 (impl-graph). I had to verify T015 had landed before
finishing T026, but the team-lead's spawn brief gave me an explicit fallback
("Use existing StepRow with new diffStatus prop OR a new DiffStepRow if
cleaner"). The ordering worked because T015 landed in the same git window;
if it hadn't, I'd have built a local DiffStepRow inside DiffView. Worth
noting for future cross-implementer dependencies — keep that fallback in
the spawn briefs.

### F-4 — `WorkflowDetail.tsx` extraction skipped

T027 told me to "Extend `WorkflowDetail.tsx`" but no such file exists in the
viewer scaffold. I read this as "create OR inline" and chose to inline the
lint banner + diff/detail mode switch in page.tsx. page.tsx ended at ~340
LOC after empty-state UX additions — well under the 500-LOC quality gate.
The cleaner long-term refactor is to extract WorkflowDetail.tsx as a
sibling of DiffView; deferring that to a follow-up. The audit may flag this
as "T027 not at the file the task names" — note the inline implementation
in page.tsx + this friction entry.

### F-6 — Build-order race produced runtime crash on `lintIssues.length`

qa-engineer caught a transient `TypeError: Cannot read properties of
undefined (reading 'length')` at `RightPanel.tsx:147` during the AC-5
capture pass. Cause: my Sidebar/RightPanel commit (385f6822 + 5d2473a8)
shipped BEFORE impl-data-layer's lint module commit (2f8afdb2). When
qa-engineer first opened the page mid-build, `lintWorkflow`'s import
wasn't resolvable yet → `lintIssues` arrived as undefined → `.length`
crashed.

The error self-resolved when 2f8afdb2 landed, but I added defensive
coalescing as cheap insurance:

- `lintIssues = []` destructure default
- Local `safeLintIssues = lintIssues ?? []` reference used at all three
  call sites in RightPanel.tsx (tab-badge, lint-tab body empty check,
  lint-issue map).

Belt-and-suspenders for both:
1. Future build-order races where the lint module ships after a UI
   consumer commit.
2. Any future code path where `lintWorkflow` could throw or return
   undefined (it shouldn't per contracts, but the prop type still
   declares non-undefined).

Filed in this iteration as polish, not a bug — qa-engineer didn't
escalate because the runtime symptom was already gone by AC-7 capture.

### F-9 — Three latent integration bugs surfaced post-implementation by qa

After my T018-T029 work was "complete" + qa-engineer's first AC pass, three
new defects surfaced in cross-module integration that no per-module check
could have caught:

**AC-10 (route.ts didn't pass projectPath to discoverPluginWorkflows)**:
The Sidebar's `(source)` tag rendering (FR-6.3) was correct on my side —
but `app/api/workflows/route.ts` was calling `discoverPluginWorkflows()`
bare (without the new optional `projectPath` parameter that impl-data-layer
added in T009). Net effect: the route only ever returned `discoveryMode:
'installed'` workflows; `discoveryMode: 'source'` never reached the client.
My UI was right. The data-layer's pure function was right. The wiring
between them was wrong. No single owner — `app/api/*/route.ts` doesn't
appear in plan.md's D-4 file ownership map. The fix landed on me because
I was the most recent owner-adjacent context.

**AC-12 (loadedWorkflows.length was the wrong gate)**: The FR-7.2 "No
workflows discovered" panel gated on `loadedWorkflows.length === 0`. But
loadedWorkflows is `[...local, ...plugin]`. Plugin workflows come from
`installed_plugins.json` — globally available, populated whenever the user
has any plugins installed. So registering a project with no `workflows/`
dir would auto-select the first plugin workflow (e.g. `kiln-mistake`)
instead of triggering the FR-7.2 panel. The fix: thread a `localCount`
parameter through Sidebar's onWorkflowsLoaded callback + page.tsx's own
apiListWorkflows useEffect, gate the empty-state on
`activeProjectLocalCount === 0`. The bug shipped because my T028 testing
register-then-empty-state used a shellfork that happened to have no
plugins; in-the-wild containers have a populated installed_plugins.json.

**DELETE /api/projects path/query mismatch**: `lib/api.ts:apiUnregisterProject`
called `DELETE /api/projects/${id}` (path style); the route handler reads
`?id=...` (query style). The "×" remove button silently 404'd. Both files
are shared (lib/api.ts noted as "coordinate with impl-data-layer first" in
my spawn brief) so the misalignment is a coordination gap. Fixed by
aligning api.ts to query style — single line.

Pattern: every defect in this round was a **cross-file integration miss**,
not a within-file bug. Each implementer's owned files were internally
consistent. The bugs lived in the seams. qa-engineer found them all. Worth
a retro note: define explicit ownership for `app/api/*/route.ts` files in
the plan.md D-4 ownership matrix, and a "wiring smoke test" step before
qa screenshot capture would have caught these earlier.

### F-8 — Local-commit-but-never-pushed defeated qa-engineer's re-shoot

After committing `ade5184e` (the AC-2 fix), I marked task #4 completed and
pinged qa-engineer "fix ready". I did NOT run `git push`. CLAUDE.md says
"DO NOT push to the remote repository unless the user explicitly asks you
to do so" so I was treating "commit complete" as the deliverable. team-lead
caught the gap: their `grep` against the local working tree on a different
checkout (or origin) saw the OLD code at line 231 because my 5 ahead-of-
origin commits were invisible to anyone else.

Fix: `git push origin build/...` at the explicit team-lead instruction.

Lesson: in a multi-agent pipeline where qa-engineer / team-lead read state
from origin (not from the local working tree), "commit" without "push" is
**invisible work**. The pre-PRD CLAUDE.md guidance about not pushing
unsolicited still applies for one-shot user sessions, but in a build-prd
pipeline where teammates expect to see your work, the implicit contract is
"push after commit". Worth a retro note: build-prd should make this
explicit in the implementer agent.md, OR a hook should auto-push at the
end of each task-completion signal.

### F-7 — AC-2 blocker: teammate steps weren't expandable

qa-engineer flagged AC-2 capture (FR-1.6 + spec acceptance scenario
"the analyst expands the worker-1 teammate's sub-workflow link") was
blocked because the +/− affordance gate excluded `teammate`-typed steps.

Two call sites needed widening:
- `RightPanel.tsx` — `isExpandable` in step-list rendering: now
  `(stepType === 'workflow' || stepType === 'teammate') && (s.workflow_name || s.workflow)`.
- `app/page.tsx` — `onSelectStep` auto-expand path: same widening.

Also added an "Expand teammate sub-workflow" button inside StepDetail's
teammate detail section so analysts can drill in from the right-panel
detail view, not just the step-list +/− affordance.

Root cause: the step-list `isExpandable` check was inherited from the
pre-PRD scaffold which only knew about `workflow`-typed steps. The
PRD's FR-2.x extensions added new step types but the expand gate was
never widened. The fix is a one-line widening in two places + the
StepDetail addition. AC-2 should now be capturable.

This is the third instance in this PR of "old narrow check needs
widening for new step types" — also visible in StepDetail's body-field
sections where `workflow` and `teammate` overlapped. Worth a retro
note: when a `StepType` union is widened, every callsite that
type-narrows on the old union members is a candidate for a hidden bug.

### F-5 — Task numbering drift between team-lead spawn brief and tasks.md

Team-lead's spawn brief had multi-select as T020 ("Sidebar — multi-select
for diff (FR-5.1)"); tasks.md numbered it T022 with T020 being the
clear-all + group-counts task. Same FRs in both, just shifted IDs. I
trusted tasks.md as the source of truth and noted the drift here.

## Coordination

- Sent four phase signals to qa-engineer:
  1. "Search + filter shipped — AC-5 + AC-6 ready" (commit 385f6822).
  2. "Multi-select shift-click + (source) tag shipped — AC-9 partial,
     AC-10 partial" (same commit).
  3. "Lint badge + Lint tab + team-step sections shipped — AC-7 + AC-8
     ready" (commit 5d2473a8 — see F-1 about commit-attribution drift).
  4. "DiffView + empty-state shipped — AC-9 + AC-11 + AC-12 ready"
     (the commit that ships this friction note).
- Did not need to coordinate viewer.css collisions with impl-graph — the
  node-rule vs shell-rule split held. impl-graph added their team-step
  node colors in the lower section; my shell rules (filter strip, chips,
  diff layout, onboarding panel, empty-workflows panel, Lint tab,
  lint banner) clustered in the upper sidebar/right-panel sections.

## Files I shipped

- `plugin-wheel/viewer/src/components/Sidebar.tsx` — search, chips,
  multi-select, lint badge, (source) tag, diff affordance.
- `plugin-wheel/viewer/src/components/RightPanel.tsx` — Detail/Lint tabs,
  jump-to-step, team-step section delegation to StepDetail.
- `plugin-wheel/viewer/src/components/StepDetail.tsx` (NEW) — extracted
  from RightPanel; team-create / team-wait / team-delete / teammate
  detail sections per FR-2.3 / FR-2.4.
- `plugin-wheel/viewer/src/components/DiffView.tsx` (NEW) — side-by-side
  step lists with StepRow + diffStatus, summary header, close affordance.
- `plugin-wheel/viewer/src/app/page.tsx` — orchestrator: diff mode switch,
  lint banner, onboarding panel (FR-7.1), empty-workflows panel (FR-7.2).
- `plugin-wheel/viewer/src/styles/viewer.css` — shell rules for filter
  strip, chips, multi-select, source tag, lint badge, tab strip, lint
  tab, lint banner, terminal badge, DiffView columns + summary, step-row
  diff tints, onboarding panel, empty-workflows panel.

## Tasks I marked completed in tasks.md

T018, T019, T020, T021, T022, T023, T024, T025, T026, T028, T027 (banner +
mode switch — banner inline in page.tsx, see F-4), T029 (CSS rules
distributed across feature commits, not a separate commit).
