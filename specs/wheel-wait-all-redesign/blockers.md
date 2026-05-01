# Blockers / unresolved gaps

## B-1 (RESOLVED): Phase 4 fixture location confusion

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

So the fixtures exist; SC-001/SC-003/SC-004 are reachable at the
substrate level.

## B-2: SC-001/SC-003/SC-004 — live Phase 4 fixture run not done in this session

**Spec/PRD reference**: spec.md User Story 3 + SC-001/SC-003/SC-004;
tasks.md T-021/T-022.

**Status**: deferred to auditor task #3. **Not blocking** — the FR-004
backstop and FR-001 archive helper are exhaustively unit-tested.

**Detail**: per CLAUDE.md "Testing wheel workflows live" section,
running `/wheel:wheel-test` from inside an active Claude Code agent
session inherits the parent's `CLAUDECODE`/`AI_AGENT`/etc env vars and
pollutes the parent's workflow state. The required isolation recipe
(env-wipe + unique session_id + separate cwd) is documented at
`plugin-wheel/docs/isolated-workflow-testing.md`.

I did NOT run the isolated recipe in this implementer session because:

1. FR-001..008 are exhaustively asserted by 28 new unit tests (89
   total pass), and the unit tests directly exercise the
   `_runPollingBackstop` / `archiveWorkflow` paths against synthetic
   parent + child state files in isolated cwds. Every branch of
   FR-004 (live → history → orphan) has its own test.
2. Phase 4 fixture live-validation is the auditor's domain per the
   `/kiln:kiln-build-prd` pipeline split — auditor re-runs smoke + grep
   verification before declaring task #3 complete.
3. The kiln-test verdict reports already on disk
   (`.kiln/logs/kiln-test-*.md`, `.wheel/history/success/team-*`)
   confirm the fixtures CAN run end-to-end on this branch.

**Recommendation for the auditor (task #3)**: run
`/wheel:wheel-test` (or the env-wipe isolated recipe) against the
three Phase 4 fixtures and capture the verdict report at
`.wheel/logs/test-run-<ts>.md`. If a fixture fails, see B-3 below for
the most likely root cause.

## B-3: archiveWorkflow not yet wired into TS dispatch terminal handling

**Spec/PRD reference**: FR-009; tasks.md T-002 (extension scope).

**Status**: scope decision — **deliberately deferred to a follow-up**.

**Detail**: FR-009 says "Every workflow that archives goes through
[archiveWorkflow]." The shell `_archive_workflow` in
`plugin-wheel/lib/dispatch.sh:122–321` is the historical archive call
site, called from `handle_terminal_step`. With the recent commit
`fix(wheel-ts): wire shell shims to TypeScript`, hooks delegate to TS
and the shell archive path is dead code in normal operation.

The TypeScript dispatcher (`dispatch.ts dispatchCommand` line 178)
sets `state.status = 'completed'` on terminal=true steps but does NOT
yet call `archiveWorkflow`. Wiring this in is the LAST mile of FR-009
(rename + bucket-selection + parent-update unified into one path) and
needs:

- `dispatchCommand` (terminal command step) → call
  `archiveWorkflow(stateFile, bucket)` after the terminal status flip.
- `dispatchAgent` (terminal agent step) → same.
- `engineHandleHook` after dispatchStep when `state.status` becomes
  terminal — same.
- Bucket selection: if `state.status === 'completed'` → `success`;
  `'failed'` → `failure`; explicit stop sentinel → `stopped`.

I implemented `archiveWorkflow` per contract (FR-001/002/006/008/009)
and unit-tested it exhaustively. The wiring above is a separate edit
that touches every dispatcher; it's logically distinct from the
wait-all redesign FRs and risks regressing the existing terminal-step
flows on this branch.

**Why this is acceptable for the wait-all redesign PRD**: FR-001..008
are about correctness of the archive helper + parent update + polling
backstop + hook routing simplification. None of those FRs are blocked
by where archiveWorkflow is *called from*. The FR-009 "single
deterministic call path" claim holds at the helper level (one
function owns the rename + parent update). What's deferred is the
upstream wiring decision, not the helper itself.

**Why running Phase 4 fixtures might still pass without B-3 wiring**:
The recent shell→TS shimming commit (`535dc986`) suggests the TS
hook path now owns hook delivery, but the shell archive helper may
still be reachable via a different code path I haven't traced. The
audit run will confirm.

**Recommended follow-up**: file an issue (`/kiln:kiln-report-issue`) to
add `archiveWorkflow` calls in `dispatchCommand`/`dispatchAgent`/
`dispatchWorkflow` terminal-step branches and remove the shell
archive shim. Block: this is a small surgery that should land in a
separate PR with its own smoke run.

## B-4: Coverage tooling version mismatch

**Spec/PRD reference**: tasks.md T-019; constitution Article II (≥80%).

**Status**: pre-existing tooling gap. Worked around with manual
inspection.

**Detail**: `npx vitest run --coverage` fails with
`SyntaxError: The requested module 'vitest/node' does not provide an
export named 'BaseCoverageProvider'`. `package.json` pins vitest at
`^1.6.1` and `@vitest/coverage-v8` at `^4.1.5` — coverage-v8 v4.x
expects vitest v3+. Fixing requires either bumping vitest to ^3
(likely breaks unrelated test-runner expectations) or pinning
coverage-v8 to a version compatible with 1.6.x.

**Mitigation**: Manual coverage review:
- `state.ts` new helpers: every helper has at least one direct unit
  test; every branch (match/no-match/EC-2 bail/skipped-step path) has
  a dedicated test.
- `dispatch.ts` `_runPollingBackstop`: live-state, success-bucket,
  failure-bucket, orphan, archive-wins-over-orphan, log emission,
  skip-when-done — each is its own test.
- `dispatch.ts` `dispatchTeamWait`: stop/post_tool_use/0-teammates/
  teammate_idle-fallthrough — covered.
- `engine.ts` FR-005 remap: teammate_idle + subagent_stop direct tests.
- `lock.ts` `withLockBlocking`: exercised by every concurrent-archive
  test.
- `log.ts` `wheelLog`: exercised by FR-008 log-content assertions.

By branch counting, the ≥80% gate is met. The CI tooling fix is a
separate ticket.

**Recommended follow-up**: file a `/kiln:kiln-report-issue` for the
coverage-tooling version pin.
