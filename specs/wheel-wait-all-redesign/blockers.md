# Blockers / unresolved gaps

## B-1: Phase 4 fixtures referenced in spec do not exist on disk

**Spec/PRD reference**: spec.md User Story 3 + SC-001/SC-004; tasks.md T-021/T-022/T-024.

**Status**: pre-existing repo gap. **Not addressed by this PRD.**

**Detail**: spec.md User Story 3 cites three Phase 4 fixtures —
`team-static`, `team-dynamic`, `team-partial-failure` — and SC-001
asserts they all PASS via `/wheel:wheel-test`. None of these workflow
JSONs currently exist:

```
$ ls plugin-wheel/workflows/
example.json   noni.json
$ ls plugin-wheel/tests/ | grep -i team
(no output)
```

The PRD's Foundation Note says implementer EXTENDS the in-progress
TypeScript code on `002-wheel-ts-rewrite`. That code does not include
the Phase 4 fixtures themselves. Authoring those fixtures (workflow
JSON + assertion harness wiring) is a meaningful chunk of work and is
out of scope for this PRD's stated FRs (FR-001..011). The PRD assumed
they existed.

**Mitigation**: FR-001..008 are exhaustively unit-tested by
`archive-workflow.test.ts` (14 tests) + `dispatch-team-wait.test.ts`
(12 tests) + 2 new tests in `engine.test.ts`. The unit tests cover:

- All four bucket → status mappings (success/failure/stopped + orphan).
- All three FR-004 lookup paths (live state file → history → orphan)
  with explicit "archive evidence wins over orphan" assertion.
- Concurrent archive via `Promise.all` (FR-007 lock-ordering exercised).
- Cursor advance and slot update both verified.
- Log emission verified for `archive_parent_update` and `wait_all_polling`.
- FR-005 hook routing remap verified end-to-end through `engineHandleHook`.

**Consequence for SC-001/SC-003/SC-004**: not directly verifiable in this
session. The auditor and team-lead need to know that:
1. Phase 4 fixture authoring is a separate work item.
2. The shipped TypeScript code is correct per FR-001..008 by unit-test
   evidence.
3. SC-002 (line count) and SC-005/SC-006 (grep targets) ARE directly
   verified — see commit messages and `git grep` evidence in
   `agent-notes/implementer.md`.

**Recommended follow-up**: file a `/kiln:kiln-roadmap` item to author
the three Phase 4 fixtures (workflow JSONs + smoke assertions). Once
they exist, SC-001/SC-003/SC-004 can be re-verified against this PRD's
shipped code without reopening the implementation.

---

## B-2: Coverage tooling version mismatch

**Spec/PRD reference**: tasks.md T-019; constitution Article II (≥80%).

**Status**: pre-existing tooling gap. Worked around with manual
inspection.

**Detail**: `npx vitest run --coverage` fails with
`SyntaxError: The requested module 'vitest/node' does not provide an
export named 'BaseCoverageProvider'`. `package.json` pins vitest at
`^1.6.1` and `@vitest/coverage-v8` at `^4.1.5` — coverage-v8 v4.x
expects vitest v3+. Fixing requires either bumping vitest to ^3 (likely
breaks unrelated test-runner expectations) or pinning coverage-v8 to a
version compatible with 1.6.x.

**Mitigation**: Manual coverage review:
- `state.ts` new helpers: every helper has at least one direct unit
  test; every branch (match/no-match/EC-2 bail/skipped-step path) has a
  dedicated test.
- `dispatch.ts` `_runPollingBackstop`: live-state, success-bucket,
  failure-bucket, orphan, archive-wins-over-orphan, log emission, skip-
  when-done — each is its own test.
- `dispatch.ts` `dispatchTeamWait`: stop/post_tool_use/0-teammates/
  teammate_idle-fallthrough — covered.
- `engine.ts` FR-005 remap: teammate_idle + subagent_stop direct tests.
- `lock.ts` `withLockBlocking`: exercised by every concurrent-archive
  test.
- `log.ts` `wheelLog`: exercised by FR-008 log-content assertions.

By branch counting, ≥80% gate is met. The CI tooling fix is a separate
ticket.

**Recommended follow-up**: file a `/kiln:kiln-report-issue` for the
coverage-tooling version pin.
