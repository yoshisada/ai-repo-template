# Blockers / unresolved gaps

_Last reconciled: 2026-04-30 by audit-pr agent (task #4) — verdict appended to B-2._

---

## B-1 (RESOLVED @ 9898a1f3): Phase 4 fixture location confusion

**Initial concern**: I read `ls plugin-wheel/workflows/` and saw only
`example.json` + `noni.json` and concluded the Phase 4 fixtures
referenced in spec.md User Story 3 didn't exist.

**Resolution**: the fixtures are in the consumer-facing
`workflows/tests/` directory at the repo root (correct location for
`/wheel:wheel-test`):

```
workflows/tests/team-static.json
workflows/tests/team-dynamic.json
workflows/tests/team-partial-failure.json
workflows/tests/team-sub-worker.json   (helper, used by static/dynamic)
workflows/tests/team-sub-fail.json     (helper, used by partial-failure)
```

Confirmed by auditor via `find . -name "team*.json"` — all five files
present at HEAD `1b9f0617`.

**Status**: RESOLVED. SC-001/SC-003/SC-004 are reachable at the
fixture level.

---

## B-2 (OPEN — deferred to audit-pr task #4): SC-001/SC-003/SC-004 live Phase 4 run

**Spec/PRD reference**: spec.md User Story 3 + SC-001/SC-003/SC-004;
tasks.md T-021/T-022.

**Status**: OPEN — not blocking unit-test gate; deferred to audit-pr
(task #4) per live-substrate-first rule.

**Detail**: per CLAUDE.md "Testing wheel workflows live" section,
running `/wheel:wheel-test` from inside an active Claude Code agent
session inherits the parent's `CLAUDECODE`/`AI_AGENT`/etc env vars and
pollutes the parent's workflow state. The required isolation recipe
(env-wipe + unique session_id + separate cwd) is documented at
`plugin-wheel/docs/isolated-workflow-testing.md`.

Per team-lead instructions (live-substrate-first rule):
> "Phase 4 team workflows are wheel-hook-bound. They CANNOT be driven
> from sub-agent context (Stop hooks bind to primary session). If
> `/kiln:kiln-test` cannot run them, the audit-pr agent will use the
> isolated-workflow-testing recipe."

**Auditor delegation**: This auditor (task #3) confirms the structural
and unit-test substrates pass. Live Phase 4 validation is explicitly
delegated to audit-pr (task #4) via the isolated recipe.

**Secondary concern**: See B-3. Phase 4 live fixtures may fail if
`archiveWorkflow` is not yet wired into the TS terminal dispatch path.
The audit-pr smoke run will surface this.

**Impact on compliance**: SC-001/003/004 are **NOT** verifiable from
this task. They are listed as OPEN DEFERRED. PRD compliance for the
Phase 4 fixture gate is conditional on audit-pr results.

**audit-pr (task #4) verdict**: DEFERRED. Two compounding reasons:
1. B-3 is confirmed by code-reading — `archiveWorkflow` has no callers
   in the TS terminal-step dispatchers. The polling backstop keys on
   live `.wheel/state_*.json` files; without the archive helper moving
   files out, every Phase 4 fixture stalls identically. So the live
   smoke would only confirm a known prediction.
2. The isolated-workflow-testing recipe execs the cache install at
   `~/.claude/plugins/cache/yoshisada-speckit/wheel/<version>/`. Latest
   cached version is `000.001.009.842` (Apr 29) and predates this PR;
   our local `000.001.009.1340` is uncommitted to the cache. Running
   the recipe as-written would test stale code (without our wait-all
   changes), which gives zero signal on the new design.

   Setting up a fake cache version pointing at our local
   `plugin-wheel/dist` requires understanding Claude Code's plugin
   resolution at hook time and risks polluting the parent session. Out
   of scope for this PR.

**Decision**: SC-001/003/004 stay OPEN-DEFERRED until B-3 is wired
(see B-3 follow-up). Phase 4 live verification happens in the PR that
fixes B-3, not this one.

---

## B-3 (OPEN — FR-009 partial): archiveWorkflow not wired into TS terminal dispatch

**Spec/PRD reference**: FR-009; PRD Assumption "Wheel's archive
function is a single deterministic call path — every workflow that
archives goes through it"; tasks.md T-002 (extension scope).

**Status**: OPEN — helper implemented and fully tested; upstream
wiring deferred as a follow-up.

**Detail**: `archiveWorkflow` is defined and exported from
`plugin-wheel/src/lib/state.ts:473`. It is exhaustively tested by 14
tests in `archive-workflow.test.ts`. However, it is NOT called from
any terminal-step dispatcher:

- `dispatch.ts dispatchCommand` (line 178): sets
  `state.status = 'completed'` on terminal=true steps but does NOT
  call `archiveWorkflow`.
- `engine.ts engineHandleHook`: no archive call.

The shell `_archive_workflow` in `lib/dispatch.sh:122-321` is the
only live archive path. Whether it remains reachable in the TS shim
era is unclear without live fixture run (see B-2).

**Impact on Phase 4 e2e**: If the TS hook path owns all hook delivery
(confirmed by `hooks/stop.sh` → `dist/hooks/stop.js` → `engineHandleHook`),
and `_archive_workflow` in shell is dead code, Phase 4 fixtures will
stall because:
1. Child terminal step sets status `completed` but state file stays
   in `.wheel/` (not moved to `history/`)
2. `archiveWorkflow` parent update (FR-001) never fires
3. Parent slots stay `running`; polling backstop finds the live child
   state file and skips it as "still working"
4. `_recheckAndCompleteIfDone` never sees all teammates done

**Mitigation in this PRD**: `archiveWorkflow` helper is complete,
correct, and tested. The wiring edit is a separate change touching
every terminal-step dispatcher. Correct order:

```
dispatchCommand (terminal=true) → call archiveWorkflow(stateFile, bucket)
dispatchAgent (terminal=true) → call archiveWorkflow(stateFile, bucket)
engineHandleHook after dispatchStep when state.status terminal → same
```

**Recommended follow-up**: `/kiln:kiln-report-issue` for wiring
`archiveWorkflow` into `dispatchCommand`/`dispatchAgent` terminal
branches.

**Note**: The existing shell `_archive_workflow` path
(`lib/dispatch.sh:287-318`) includes
`_chain_parent_after_archive` which calls `teammate_idle` hook handler
on the parent — that path relies on the old event-driven design this
PRD replaces. It must be removed or updated if shell archive is still
reachable.

---

## B-4 (OPEN — pre-existing tooling gap): Coverage tooling version mismatch

**Spec/PRD reference**: tasks.md T-019; constitution Article II (≥80%).

**Status**: OPEN — pre-existing tooling gap. Manually verified ≥80%.

**Detail**: `npx vitest run --coverage` fails with
`SyntaxError: The requested module 'vitest/node' does not provide an
export named 'BaseCoverageProvider'`. `package.json` pins vitest at
`^1.6.1` and `@vitest/coverage-v8` at `^4.1.5` — coverage-v8 v4.x
expects vitest v3+.

**Auditor coverage confirmation**: Manual branch-counting review:
- `state.ts` new helpers: every helper has ≥1 direct test; every
  branch (match/no-match/EC-2 bail/skipped-step) has a dedicated test.
- `dispatch.ts _runPollingBackstop`: live-state, success-bucket,
  failure-bucket, orphan, archive-evidence-wins, log emission,
  skip-when-done — each is its own test case.
- `dispatch.ts dispatchTeamWait`: stop/post_tool_use/0-teammates/
  teammate_idle-fallthrough — covered.
- `engine.ts engineHandleHook` FR-005 remap: teammate_idle +
  subagent_stop direct tests.
- `lock.ts withLockBlocking`: exercised by every concurrent-archive
  test.
- `log.ts wheelLog`: exercised by FR-008 log-content assertions.

By branch counting ≥80% gate is met on FR-001..011 paths. CI
tooling fix is a separate ticket.

**Recommended follow-up**: Pin `@vitest/coverage-v8` to a version
compatible with vitest 1.6.x (e.g. `^1.6.1`), or bump vitest to ^3.
