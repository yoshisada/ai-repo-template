# Feature PRD: Wheel TS Dispatcher Cascade — Inline Step Chaining for Parity with Shell

## Parent Product

Wheel — hook-based workflow engine plugin (`plugin-wheel/`). See repo `CLAUDE.md` for product context. This PRD **folds into the in-progress TypeScript rewrite** on branch `002-wheel-ts-rewrite`. It is a peer to `2026-04-30-wheel-wait-all-redesign` — both PRDs ship as part of the rewrite, but this one is the load-bearing prerequisite for ANY other rewrite work to be useful (without it, no workflow progresses).

## Feature Overview

Add **inline step cascade** to the TS dispatchers (`dispatchCommand`, `dispatchLoop`, `dispatchBranch`, plus the activation hook entry point) so that auto-executable steps run back-to-back inside a single hook invocation, matching the shell wheel's existing behavior. Without this cascade, every command-chain workflow stalls at `cursor=0 pending` after activation because nothing triggers the next dispatch. With it, a 100-step counting loop completes in <5s end-to-end inside one PostToolUse hook fire.

## Problem / Motivation

The TS rewrite of wheel is structurally incomplete. The dispatcher functions exist (`dispatchCommand`, `dispatchAgent`, `dispatchTeamCreate`, etc.), and the activation hook creates state correctly, but **none of the dispatchers cascade through chained auto-executable steps**. Each dispatcher returns after one step. The shell version's equivalent cascade is what makes wheel actually progress workflows.

Empirical evidence: on 2026-05-01, the working-tree TS dist was deployed to the plugin cache and `/wheel:wheel-test` was run against the full test suite. **0 of 109 expected results passed.** Phase 1 simple workflows (`count-to-100`, `loop-test`, `team-sub-fail` — pure command/branch/loop steps) all hit the 60s phase timeout. Orphan state files cascaded across every subsequent test (one workflow's stuck state file contaminated the next test's count, producing the 109 failure tally). Run report: `.wheel/logs/test-run-20260501T194556Z.md`.

The shell version's `dispatch_step` recursively invokes itself for the next step until it hits something blocking (agent / team-create / team-wait) or the workflow archives. The TS code path:

```typescript
// dispatchCommand — TS
await stateSetStepStatus(stateFile, stepIndex, 'done');
if ((step as any).terminal === true) {
  // ... set workflow.status = 'completed'
}
return { decision: 'approve' };  // ← returns. Cursor not advanced. Next step not dispatched.
```

There is no recursive call. The hook returns to Claude Code with the workflow at `cursor=0 done`. The cursor isn't advanced. The next step isn't dispatched. The workflow is stuck.

In a *live* Claude Code session, every subsequent tool call triggers PostToolUse, which advances one step per call. So a 5-step workflow takes 5 unrelated tool calls to complete. A 100-step counting loop is hopeless. In automated `/wheel:wheel-test`, no tool calls follow the activation, so nothing advances at all.

This breaks every workflow type, not just Phase 4. Phase 4's `team-wait` redesign (PRD `2026-04-30-wheel-wait-all-redesign`) is downstream of this — without cascade, even the wait-all fix can't help because the workflow never reaches the `team-wait` step in the first place.

## Goals

- **G1**: `/wheel:wheel-test` Phase 1 (`count-to-100`, `loop-test`, `team-sub-fail`) all pass with no orphan state files. Workflows complete in <5s wall-clock each.
- **G2**: `/wheel:wheel-test` Phase 2 (`agent-chain`, `branch-multi`, `command-chain`, `example`, `sync`, `team-sub-worker`) all pass. Agent steps still block as expected; non-agent steps cascade.
- **G3**: `/wheel:wheel-test` Phase 3 (`composition-mega`) passes. The cascade respects child-workflow activation as a step type.
- **G4**: After this PRD lands AND `2026-04-30-wheel-wait-all-redesign` lands, Phase 4 (`team-static`, `team-dynamic`, `team-partial-failure`) all pass. Phase 4 is not a goal of this PRD on its own — only G1–G3 are. But this PRD is a hard pre-req for Phase 4.
- **G5**: Behavior matches shell wheel for every step type. Specifically: command/loop/branch cascade; agent/team-create/team-wait/teammate are blocking points where the cascade STOPS until the appropriate hook fires. No surprises.

## Non-Goals

- **Not a fix for shell wheel.** Shell already cascades correctly. Out of scope.
- **Not a redesign of the dispatcher contract.** Each dispatcher's signature, hook-type handling, and decision logic stay as they are today. This PRD only adds the cascade — at the END of each auto-executable dispatcher's success path.
- **Not a fix for the wait-all team-wait flow.** Phase 4 specifics live in `2026-04-30-wheel-wait-all-redesign`. This PRD makes it possible for that PRD's work to actually run.
- **Not a parity audit of every TS gap.** Scope is dispatcher cascade ONLY. Other rewrite gaps (workflow validation, registry resolution, lock semantics, log file paths, etc.) are separate PRDs if they surface.
- **Not a refactor of `engineHandleHook`.** That function already advances cursor by 1 after a single dispatch. This PRD's cascade lives INSIDE the dispatchers, not the engine — same shape as shell. Engine continues to handle the post-dispatch cursor advance for non-cascading paths (agent step done via output-file detection, team-wait completion, etc.).
- **Not a change to the activation contract.** `activate.sh` stays a no-op; the hook still does the work. The hook's `handleActivation` will gain a final cascade call after state is initialized.
- **Not a change to the workflow JSON schema.** Existing workflows run unchanged.

## Target Users

Inherited from parent product. Specifically benefits:

- **Anyone who runs `/wheel:wheel-test`** — Phases 1–3 stop being permanent red.
- **Plugin authors** writing workflows for kiln/clay/shelf/trim — auto-executable workflow chains actually execute.
- **The 002-wheel-ts-rewrite branch** — without this, the rewrite is stuck and can't merge.
- **Phase 4 PRD author** (the wait-all redesign) — unblocks downstream Phase 4 verification.

## Core User Stories

1. **As a plugin author**, I run `bash activate.sh count-to-100.json` from any cwd. The hook returns within 5 seconds with the workflow archived to `.wheel/history/success/`. No orphan state file. No manual nudging.
2. **As `/wheel:wheel-test` runner**, all Phase 1 fixtures complete inside their 60s phase budget. Phase 2 fixtures complete inside their 60s phase budget. Phase 3 fixtures complete inside their 60s phase budget.
3. **As a workflow author**, my workflow JSON has a sequence of `command` → `command` → `branch` → `command` → `agent` → `command`. The first four steps cascade inside one hook fire. The agent step blocks correctly. After the agent step's output file is written, the trailing `command` cascades to terminal.
4. **As a kiln pipeline runner** (`/kiln:kiln-build-prd`), I activate the pipeline workflow. Setup commands run inline. Block at the first agent step, as designed. After the agent step's output, post-agent cascade runs inline. Pipeline progresses without me needing to fire arbitrary tool calls to nudge it.
5. **As a wheel internals reader**, when I open `dispatchCommand` in TS source, I see a clear cascade tail: "if next step is auto-executable, dispatch it; recurse." Same pattern as shell. No surprise.

## Functional Requirements

### FR-1 — Auto-executable step type catalog

The cascade must distinguish AUTO-EXECUTABLE step types from BLOCKING step types. This catalog MUST be a single source of truth (a constant or helper), not duplicated across dispatchers:

- **Auto-executable (cascade continues)**: `command`, `loop`, `branch`
- **Blocking (cascade STOPS, returns control to hook)**: `agent`, `team-create`, `teammate`, `team-wait`, `team-delete`, `parallel`, `approval`
- **Composite (cascade enters child)**: `workflow` — activates a child workflow inline; cascade continues against the CHILD's first step inside the child's state. When the child archives (per FR-009 of `2026-04-30-wheel-wait-all-redesign`), the parent's cursor advances and the parent cascade resumes.

### FR-2 — `dispatchCommand` cascade tail

After `dispatchCommand` marks the step `done` (success path) or `failed` (error path):

1. Read fresh state.
2. Compute `nextIndex` = `cursor + 1` (with branch-target / loop-iteration logic delegated to the existing helpers — `resolveNextIndex`, `advancePastSkipped`).
3. If `nextIndex >= state.steps.length`: return; `engineHandleHook` (or `handleActivation` for the activation path) will detect terminal cursor and trigger archive (per FR-009 of `2026-04-30-wheel-wait-all-redesign`).
4. Read `nextStep = state.steps[nextIndex]`.
5. If `nextStep.type` is auto-executable per FR-1: advance cursor, recursively call `dispatchStep(nextStep, hookType, hookInput, stateFile, nextIndex)`. Tail-recursive.
6. If `nextStep.type` is blocking per FR-1: advance cursor (so the next hook fire dispatches the blocking step), do NOT recurse. Return.

### FR-3 — `dispatchLoop` cascade tail

Same pattern as FR-2. The loop dispatcher already handles iteration logic; the cascade hooks in at the boundary where the loop has either completed all iterations (cascade to next step) or has decided to skip the loop body (cascade to step after loop). Reuses FR-2's "find next step + cascade if auto-executable" tail.

### FR-4 — `dispatchBranch` cascade tail

Same pattern as FR-2. The branch dispatcher resolves which target step to jump to via the existing `workflowGetBranchTarget` helper. After resolving the target, the cascade hooks in: advance cursor to the target index, dispatch if auto-executable, return otherwise.

### FR-5 — `handleActivation` post-init cascade

After `handleActivation` creates the state file (and persists `workflow_definition` per the wait-all redesign PRD's hook-init fix), it MUST trigger the initial cascade:

1. Read the new state's cursor (always 0 for fresh activation).
2. Read `step = state.steps[0]`.
3. If `step.type` is auto-executable: advance cursor (to 0 — semantics: "we're now working on step 0"), invoke `dispatchStep(step, 'post_tool_use', hookInput, stateFile, 0)`. The dispatcher's cascade tail (FR-2/3/4) handles the rest.
4. If `step.type` is blocking: do NOT cascade. Return. The Stop hook will handle the blocking step's prompt injection on the next agent turn.

The `engine.ts` archive wiring from `2026-04-30-wheel-wait-all-redesign` FR-009 still runs after the cascade returns (terminal-cursor detection triggers archive).

### FR-6 — Recursion bound

Cascade depth is bounded by workflow step count (≤ steps.length). For typical workflows (≤100 steps) this is well within Node's default call-stack budget (~10k frames). Loops with `iterations` semantics increment a counter, not the cascade depth — same pattern as shell. No iteration cap in scope for this PRD.

For pathological cases (10k+ steps, deeply-nested compositions), an explicit iteration-with-while-loop refactor could replace recursion. NOT in scope. Out-of-scope safety net: a hard cascade depth cap of 1000 returns gracefully with a logged warning, but does not throw.

### FR-7 — Hook-type pass-through

The cascade calls `dispatchStep` with the SAME `hookType` it received. If activation passes `'post_tool_use'`, the cascade uses `'post_tool_use'`. If a Stop-hook-driven cursor advance triggers the cascade (via `engineHandleHook` after FR-2/3/4 completes), it uses `'stop'`. The cascade is hook-type-agnostic — it just chains dispatches.

### FR-8 — Failure semantics

If a cascaded step fails (e.g., `dispatchCommand` catches an exec error and sets status `failed`), the cascade STOPS. The terminal-archive logic (per the wait-all redesign PRD's FR-009) detects the failed step and archives the workflow to `history/failure/`. Match shell behavior: a failed step doesn't try to dispatch the next.

### FR-9 — Logging

Every cascade transition MUST emit a `wheel.log` entry with phase `dispatch_cascade` recording: `from_step_id`, `to_step_id`, `from_step_type`, `to_step_type`, `hook_type`. Failures (cascade halt due to step failure) emit phase `dispatch_cascade_halt` with `step_id`, `step_type`, `reason`. Cursor advance emits phase `cursor_advance` (existing pattern, extend if needed).

This is for debuggability — a single `wheel.log` line per cascade hop tells the reader exactly what fired and why it stopped.

### FR-10 — Test fixtures

Three new vitest fixtures under `plugin-wheel/src/lib/dispatch-cascade.test.ts`:

1. **`dispatchCommand cascades through chained command steps`** — workflow with 3 command steps; activation triggers cascade; final state shows cursor past end, all three steps done, workflow archived to `history/success/`.
2. **`dispatchCommand stops cascade at agent step`** — workflow with `command → command → agent → command`; activation cascades through both commands, stops at agent (cursor=2, status=working from dispatchAgent). Trailing command does NOT execute. Test then writes the agent's output file, fires post_tool_use, and verifies the trailing command cascade-runs.
3. **`dispatchCommand cascade halts on step failure`** — workflow with `command(success) → command(fails) → command`. After cascade, state shows step 0 done, step 1 failed, step 2 still pending. Workflow archived to `history/failure/`.

Plus E2E coverage by re-enabling `/wheel:wheel-test` Phase 1–3 fixtures in CI (already exists but currently fails — start passing under this PRD).

## Absolute Musts

1. **Tech stack**: TypeScript (strict mode), Node 20+, `fs/promises`, `path`, no external npm deps. Inherited from `002-wheel-ts-rewrite` PRD.
2. **No regression in shell wheel.** This PRD only modifies TS code. Shell remains canonical until the rewrite ships. Any user on the cached shell version is unaffected.
3. **Lands inside the 002-wheel-ts-rewrite branch.** Either as a peer commit alongside `2026-04-30-wheel-wait-all-redesign`'s commits, or as a fast-follow on the same branch. Either way, ships as part of the rewrite's eventual PR. Do NOT cut a separate branch off main.
4. **`/wheel:wheel-test` Phases 1–3 are the acceptance gate.** No merge until those pass on the working-tree dist deployed to plugin cache. Current baseline: 0/109 (full test run report at `.wheel/logs/test-run-20260501T194556Z.md`).
5. **Do not introduce a step-type registry that decouples auto/blocking classification from existing dispatcher routing.** The catalog (FR-1) is a single helper; routing in `dispatchStep` is unchanged. No new abstraction layer.
6. **Cascade is opt-in per dispatcher, not a global engine feature.** `dispatchCommand` calls its own cascade tail. `dispatchAgent` does NOT cascade (agent steps are blocking; cascade only resumes after the agent's output file appears, which is handled by the existing `engineHandleHook` advance). No surprise behavior.

## Tech Stack

Inherited from `002-wheel-ts-rewrite` PRD. No additions or overrides.

## Impact on Existing Features

| Area | Impact |
|---|---|
| `dispatchCommand` (success + failure paths) | **Extended.** Cascade tail added; existing return semantics unchanged when next step is blocking. |
| `dispatchLoop` | **Extended.** Cascade tail added at loop-completion + loop-body-skip boundaries. |
| `dispatchBranch` | **Extended.** Cascade tail added after branch target resolution. |
| `dispatchAgent` | **Unchanged.** Agent steps are blocking. Cursor advance + downstream cascade is driven by post_tool_use detecting the agent's output file. |
| `dispatchTeamCreate`, `dispatchTeammate`, `dispatchTeamWait`, `dispatchTeamDelete`, `dispatchParallel`, `dispatchApproval` | **Unchanged.** All blocking. Cascade does not enter. |
| `dispatchWorkflow` (composition) | **Extended carefully.** When a composition step activates a child workflow, the child's first step cascades inside the CHILD's state (per FR-1's "Composite" case). Parent's cascade pauses; resumes when child archives via FR-009 of the wait-all redesign PRD. |
| `handleActivation` | **Extended.** Post-state-init triggers FR-5 cascade. |
| `engineHandleHook` | **Unchanged.** Continues to handle Stop/SubagentStop/TeammateIdle hook routing + post-dispatch cursor advance. The new cascade fires INSIDE dispatchers, before engineHandleHook's cursor-advance code path runs. |
| `archiveWorkflow` (wait-all redesign FR-009) | **Unchanged.** Triggered by terminal cursor detection, same as today. The cascade naturally terminates at the workflow boundary; the archive logic kicks in. |
| Workflow JSON schema | **Unchanged.** No new step types, no new fields. |
| `state_*.json` schema | **Unchanged.** Same `cursor` + `steps[]` shape. |
| Phase 1–3 test fixtures | **Start passing.** No fixture changes. Behavior change makes them work. |
| `/wheel:wheel-test` skill | **Unchanged.** Same harness, same fixture set. |
| Shell wheel | **Unchanged.** This PRD modifies TS only. |

## Success Metrics

1. **SC-1**: `/wheel:wheel-test` reports 100% pass on Phases 1–3 (10 of 10 expected results in the current fixture set, ignoring the 4 Phase 4 fixtures which depend on the wait-all redesign PRD). Baseline: 0/13 passing for non-Phase-4 fixtures (per 2026-05-01 test run). Verified by exit-0 of the test run with no orphan state files.
2. **SC-2**: A 100-step `count-to-100` loop completes in <5s wall-clock. Baseline: 60s timeout. Verified by inspecting the per-workflow duration column of the test run report.
3. **SC-3**: After `/wheel:wheel-test` exits, `.wheel/state_*.json` is empty. Baseline: 14+ orphan state files. Verified by `ls .wheel/state_*.json | wc -l` returning 0.
4. **SC-4**: `dispatchCommand` source size grows by ≤30 lines (the cascade tail is small; we're not refactoring). Verified by `wc -l` diff. (Soft target — if the right design needs more lines, that's acceptable; this is a complexity guardrail, not a hard cap.)

## Risks / Unknowns

- **R-1**: Recursive cascade hits Node's call-stack limit on long workflows. Mitigation: FR-6 documents the bound; the optional 1000-step cascade-depth cap returns gracefully. If a real workflow hits this cap in practice, refactor to iteration in a follow-up.
- **R-2**: A composition step (`type: workflow`) activates a child mid-cascade, and the child's lock semantics conflict with the parent's. Mitigation: composition uses separate state files with their own locks. The cascade in the parent PAUSES (returns control to the hook) when it hits a `workflow` step; the child's state file gets its own dispatch cycle. Same isolation as shell.
- **R-3**: `dispatchAgent`'s "output file detected → mark done → advance cursor" path needs to ALSO trigger the cascade for the post-agent step. Currently `dispatchAgent` advances cursor directly. The cascade hook needs to trigger from there, OR `engineHandleHook` needs to detect the cursor advance and call the cascade. Mitigation: clarify in plan-time which path owns the cascade trigger after agent completion. The cleanest design is: dispatchAgent calls `dispatchStep` for the next step after marking the agent done, mirroring FR-2.
- **R-4**: Subtle mismatches between shell `_chain_parent_after_archive` semantics and TS `archiveWorkflow` + cascade. The shell version cascades from PARENT after a child archives. The TS version's `archiveWorkflow` (per wait-all redesign FR-009) updates the parent's teammate slot but doesn't trigger the parent's cascade explicitly. Whose hook fire resumes the parent's cascade? Mitigation: this is in the wait-all redesign's scope, not this PRD's; the boundary is clean.
- **R-5**: A failed cascade step leaves the workflow in an inconsistent state if the failure happens between cursor advance and dispatch. Mitigation: order the operations carefully — advance cursor FIRST (so retry on next hook fire dispatches the right step), THEN dispatch. If dispatch fails, state is at `cursor=N, step[N].status=pending`; next hook fire retries. Idempotent.
- **R-6**: Behavioral divergence from shell for edge cases (e.g., a loop step with iteration_count=0, a branch with both targets pointing to the same step). Mitigation: write fixtures for each edge case observed in shell tests and replicate behavior. If shell has a bug, this PRD does NOT fix it — match shell, file a separate issue.
- **R-7**: Hook-firing latency: with cascade, a single PostToolUse hook fire might run a 100-step workflow inline. That blocks the parent process for the duration. Same as shell. Acceptable for typical workflows. If a workflow takes >30s of pure cascade, that's a workflow-design issue, not a wheel issue.

## Assumptions

- The shell wheel's `dispatch_step` cascade is the canonical reference. Read `~/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.842/lib/dispatch.sh` for the exact behavior to match. Every step type's cascade boundary in shell is the shape we replicate in TS.
- Existing helpers (`resolveNextIndex`, `advancePastSkipped`, `workflowGetBranchTarget`) cover the per-step-type "what's next?" logic. The cascade tail re-uses them; doesn't reinvent.
- `/wheel:wheel-test` is the canonical end-to-end gate. We do NOT need a separate live-Claude-Code subprocess test for this PRD's acceptance; the test harness exercises the same code path.
- `archiveWorkflow` from the wait-all redesign PRD is in place by the time this PRD merges. If not, the FR-009 archive trigger needs to be approximated by this PRD's terminal-cursor handling (small addition to handleActivation + engineHandleHook).
- The plugin cache deployment (`~/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.842/dist/`) reflects the working tree's `plugin-wheel/dist/` for verification runs. Deployment is via `cp -r plugin-wheel/dist/ <cache>/dist/` until the rewrite ships and a new cache version is published.

## Open Questions

- **Q1**: Does `dispatchAgent`'s "output file detected" path own the post-agent cascade, or does `engineHandleHook` route to a separate cascade trigger? Both are defensible; resolve at plan-time. Cleanest is dispatchAgent owning it (parallel to dispatchCommand).
- **Q2**: Should the cascade depth cap (FR-6 "1000 steps") emit a warning log entry or silently accept the limit? Default: log warning, halt cascade gracefully, leave state at the in-flight cursor for the next hook fire to resume. Resolve at plan-time.
- **Q3**: Composition step (`type: workflow`) cascade boundary: when a child workflow archives, what triggers the parent's cascade resume? The wait-all redesign PRD's FR-009 says "parent cursor advances when teammate slot transitions." Parallel question: when a COMPOSED CHILD (not a teammate) archives, does the parent advance via the same mechanism, or via a different "chain_parent_after_archive" path? Clarify at plan-time. May need a small extension to FR-009 for composition.
- **Q4**: Should this PRD ALSO ship the cascade for composition steps (FR-1 "Composite" case), or is that a follow-up PRD? Default: ship in this PRD because composition without cascade is just as broken as command without cascade. But if scope balloons, defer.
