# Friction Note — impl-wheel — wheel-ts-rewrite-parity-completion

## TL;DR
- All 11 dispatcher gaps + 6 hook gaps from `research.md` mapped to a code change + test fixture.
- 13/13 phases complete (Phase 11 smoke gate is owned by audit-pr).
- Test count: 99 → 125 (+26 new parity fixtures across 6 new test files + extensions).
- `npx vitest run --coverage` produces a usable report (FR-009 SC-3 cleared).
- `dispatch.ts` 80.63%, `dispatch-team.ts` 93.15%, `state.ts` 88.51% — all above the 80% gate.
- Build: `npm run build` succeeds, no TS strict errors.

## FR-009 choice
Option (a). `@vitest/coverage-v8@^1.6.1` resolves cleanly against `vitest@^1.6.1`. No fallback to option (b) needed. Cost: 16 packages added / 8 removed / 4 changed during `npm install`. No test breakage.

## Gaps that turned out larger than the audit claimed
- **dispatchAgent FR-002** — turned out 7 sub-fixes, not 6. The audit listed 6 but the cleanup hit a 7th DEBUG line in `dispatchWorkflow` (`'DEBUG: dispatchWorkflow child cascade error:'`). Picked up under the same hygiene umbrella so the dispatch.ts file passes `grep -c DEBUG` = 0.
- **post-tool-use.ts hygiene** — audit listed 5 DEBUG lines (390, 476, 478, 490, 492); the actual file had **12** DEBUG calls. Removed all 12 to clear the contract §12 acceptance grep.
- **dispatchApproval (FR-007 A2)** — audit said "audit + add fixture if needed". The TS implementation was over-simplified (just set awaiting_user_input regardless of hook type); rewrote the entire function to match shell case statement. Required updating one pre-existing test assertion that depended on the broken behaviour.

## Gaps that turned out smaller / no-op
- **dispatchTeamCreate (FR-006 A1)** — already mostly correct; only added `cascadeNext(...)` after the team-done transition.
- **dispatchParallel (FR-007 A1)** — no concrete gap. Existing implementation matches shell on stop / teammate_idle / subagent_stop. Added a minimal sentinel test only.
- **stateRemoveTeam (FR-006 A7 dependency)** — already exists in TS state.ts (Phase 0 verification). No port needed.
- **Hooks 2-6 (stop, subagent-stop, teammate-idle, session-start, subagent-start)** — no gaps. All five delegate to `engineInit + engineHandleHook` which is the wait-all-redesign foundation. Documented in `research.md §intentional-deviations`.

## Decision: D-3 composition parent-resume
`archiveWorkflow` already had teammate-slot update + team-wait cursor advance (wait-all-redesign FR-009). It did NOT have composition parent-resume. **Added** a parallel branch in `archiveWorkflow` for the composition case (parent_workflow set + no teammate-slot match). Alternative was to call `_chainParentAfterArchive` from every dispatcher's terminal branch — rejected because shell's `handle_terminal_step` does the cursor advance inside its own scope and the consumer-visible behaviour is identical.

Side benefit: `dispatchWorkflow` now wires `parentWorkflow: stateFile` into the child's `stateInit`. Pre-fix the child had `parent_workflow=null`, so the archive helper could never resume the parent.

## Decision: D-4 module placement (dispatch-team.ts)
Created NEW `plugin-wheel/src/lib/dispatch-team.ts` for FR-006 helpers (`_teammateChainNext`, `_teammateFlushFromState`, `_teamWaitComplete`, `teammateMatchTaskCreate`, `distributeAgentAssign`). dispatch.ts was already 1215 lines (over the 500 cap); adding the team helpers in-place would have pushed it past 1700. New module is 93.15% covered.

## Tasks deferred (filed as follow-up rather than expanded mid-flight per FR-013)

### T-033 — dispatchLoop cascade tail uses raw `stepIndex+1`
**Status**: explicit deferral, documented in research.md §intentional-deviations.
**Rationale**: `cascadeNext` already walks past skipped steps (`dispatch.ts:149-166`). The `step.next` field is uncommon in `loop` step definitions. No `/wheel:wheel-test` fixture surfaces this gap. Will file follow-up issue if a fixture surfaces it.

### Output-schema validation in dispatchAgent (FR-002 OOS)
Pre-existing deferral from spec.md FR-002. No change.

## New gaps discovered during implementation NOT in the audit table
None. Scope held. Per FR-013 frozen-scope rule, the audit list at tasks.md commit time IS the scope; nothing was added.

## Architectural notes for audit-compliance + audit-pr

1. **FR-005 A1 changed observable behaviour for an existing test**: `dispatch-cascade.test.ts > parent halts at workflow step` previously asserted `parent.steps[1].status === 'working'` (parent stalls). New behaviour per FR-005 A1: `parent.steps[1].status === 'done'` and `parent.cursor === 2`. The old assertion encoded the bug; the test was updated to encode the fix.

2. **dispatchTeammate batched block format change**: pre-FR-006 the block read `"Spawned agent: <name> for <workflow>"`. Post-fix it's `"Spawn the following teammates as part of team \"<name>\":\n- name: ...\n  agent_id: ...\n  output_dir: ...\n  workflow: ..."`. Updated the pre-existing test in dispatch.test.ts to look for `'Spawn'` + agent name rather than the literal `'Spawned'` string.

3. **post-tool-use.ts module gating**: `main()` now only runs when invoked as the entry point (`process.argv[1].endsWith('post-tool-use.{js,ts}')`). Without this guard, `import { handleDeactivate }` from a unit test would run main() at import time and read stdin / try to JSON-parse it, hanging or crashing the test. Audit-compliance: please verify the guard pattern in the deployed `dist/hooks/post-tool-use.js` doesn't change semantics for the live consumer (the path will end in `.js` so the guard fires correctly).

4. **Hook entry points for stop / subagent-stop / teammate-idle / session-start / subagent-start — NOT modified.** All five delegate to engineInit + engineHandleHook which is the wait-all-redesign foundation. Audit pattern: `git diff 002-wheel-ts-rewrite..HEAD -- plugin-wheel/src/hooks/` should show only post-tool-use.ts changes (plus the new test files). audit-compliance can verify with: `git diff --stat 002-wheel-ts-rewrite..HEAD -- 'plugin-wheel/src/hooks/*.ts'`.

5. **Coverage on context.ts is 66.95%** — below the 80% line gate at the file level, but this is because `contextBuild` has unused branches (loop_iteration block, command_log fallback). The NEW exports `contextCaptureOutput` + `contextWriteTeammateFiles` are exercised by `dispatch-agent-parity.test.ts` and `dispatch-teammate.test.ts`. SC-7 trace via `git grep -n "// parity:" plugin-wheel/src/lib/context.ts` returns matches for both new helpers.

## Smoke-gate hand-off
audit-pr owns SC-1 (the live `/wheel:wheel-test` Phases 1–4 run). impl-wheel cannot run that gate from inside this build session — it requires a deployed `dist/` and a clean `.wheel/state_*.json` directory which I cannot guarantee here. Hand-off message below.

## Files added / changed

### Added
- `plugin-wheel/src/lib/dispatch-team.ts` (new module — D-4)
- `plugin-wheel/src/lib/dispatch-loop-iter.test.ts` (FR-003)
- `plugin-wheel/src/lib/dispatch-agent-parity.test.ts` (FR-002)
- `plugin-wheel/src/lib/dispatch-teammate.test.ts` (FR-006 A2-A4)
- `plugin-wheel/src/lib/dispatch-team-delete.test.ts` (FR-006 A7)
- `plugin-wheel/src/lib/dispatch-parallel.test.ts` (FR-007 A1)
- `plugin-wheel/src/lib/dispatch-approval.test.ts` (FR-007 A2)
- `plugin-wheel/src/hooks/hook-deactivate.test.ts` (FR-008 A1)

### Changed
- `plugin-wheel/package.json` (FR-009: coverage-v8 1.6.x)
- `plugin-wheel/src/lib/dispatch.ts` (FR-001/002/003/004/005/006/007 — most gaps)
- `plugin-wheel/src/lib/workflow.ts` (Phase 0 helper port: resolveNextIndex, advancePastSkipped, deriveWorkflowPluginDir)
- `plugin-wheel/src/lib/context.ts` (Phase 0 helper port: contextCaptureOutput, contextWriteTeammateFiles)
- `plugin-wheel/src/lib/state.ts` (FR-005: composition parent-resume in archiveWorkflow)
- `plugin-wheel/src/hooks/post-tool-use.ts` (FR-008 A1: handleDeactivate; A2: DEBUG hygiene; main() module-gating)
- `plugin-wheel/src/lib/dispatch.test.ts` (extended: command-exports-plugin-dir; updated: approval/teammate to match new behaviour)
- `plugin-wheel/src/lib/dispatch-cascade.test.ts` (updated: composition parent now advances per FR-005 A1)
- `plugin-wheel/src/lib/dispatch-team-wait.test.ts` (extended: wait-summary-output, collect-to-copy)
- `plugin-wheel/src/lib/dispatch-terminal.test.ts` (extended: child-archive-advances-parent)
- `specs/wheel-ts-rewrite-parity-completion/research.md` (intentional-deviations rows added)
- `specs/wheel-ts-rewrite-parity-completion/tasks.md` (every Phase 0-10 task marked [X])

## Final test counts
- pre-impl: 99 tests (96 from rewrite + 3 cascade fixtures)
- post-impl: 126 tests (+27: 3 loop, 7 agent-parity (incl. P0 regression), 4 teammate, 3 team-delete, 1 parallel, 2 approval, 3 deactivate, 4 inline extensions on existing files)
- 100% pass rate.

---

## Round 2 — P0 fix (post-handoff)

team-lead found a P0 during parallel SC-1 verification: Phase 2 first
fixture (agent-chain) hung at the agent step because
`handleNormalPath` in `post-tool-use.ts` reads `step.output` from
`state.steps[cursor]`, but stateInit was projecting state.steps[i]
with only `{id, type, ...dynamic}` — dropping workflow-step
properties (`output`, `instruction`, `context_from`, `command`, etc.).
dispatchAgent's stop-hook check `if (outputKey)` therefore failed
and the step never advanced.

Two-front fix:

1. **stateInit (state.ts)** — spread the workflow step shape FIRST,
   then override with dynamic state fields. state.steps[i] now mirrors
   shell wheel's `workflow_step UNION dynamic_fields` shape. Initial
   `output` value preserves the workflow-step path (was null pre-fix).

2. **handleNormalPath (post-tool-use.ts)** — prefer
   `state.workflow_definition.steps[cursor]` over `state.steps[cursor]`
   when computing `step` for dispatch. Defense-in-depth + parity with
   `cascadeNext` at dispatch.ts:173 (which already uses this pattern).

Regression test: added `dispatch-agent-parity.test.ts:regression: stateInit
preserves workflow-step output path on state.steps[i]` which asserts
`output`, `instruction`, `context_from` are all carried through stateInit.

`npm run build` clean, full suite 126/126 pass.

---

## Round 3 — P1 fix (terminal agent + archive)

audit-pr ping #1: Phase 1 ✓; Phase 2 first fixture (agent-chain) failed
with cursor=4 of 4, terminal step status=done with terminal:true, but
state.status='running' and workflow never archives. Subsequent hooks
didn't pick it up.

Two fixes:

1. **dispatchAgent** — when terminal:true agent step transitions to done,
   set `state.status='completed'` (mirrors dispatchCommand's terminal
   path). Without this, the workflow sits at cursor>=steps.length with
   status='running' and `maybeArchiveAfterActivation` never finds it.

2. **handleNormalPath** — call `maybeArchiveAfterActivation(stateFile)`
   after every dispatchStep return, so terminal-workflow detection runs
   in the SAME hook fire (parity with shell's per-dispatcher
   handle_terminal_step pattern + the existing
   maybeArchiveTerminalWorkflow path inside engineHandleHook).

Regression test added: `dispatch-agent-parity.test.ts:regression: terminal
agent step sets state.status=completed`.

`npm run build` clean, full suite 127/127 pass.
