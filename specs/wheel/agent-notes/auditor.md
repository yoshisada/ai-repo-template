# Auditor Friction Notes

**Agent**: auditor
**Date**: 2026-04-03
**Branch**: build/wheel-20260403

## What Went Well

1. **Clean implementation**: Both implementers delivered code that matches contracts/interfaces.md exactly. All function signatures aligned — no contract violations found.
2. **All 45 integration test assertions pass**: Tests cover US1 (linear workflow), US2 (resume), US1-S4 (command steps), and US5 (branch/loop). Good coverage of core scenarios.
3. **Bash syntax validation clean**: All 12 shell scripts pass `bash -n`.
4. **100% FR coverage**: Every PRD requirement has a corresponding implementation and most have test coverage.

## Friction Points

1. **Waited for blocked tasks**: As the auditor, I was spawned early but had to wait for tasks #1, #2, and #3 to complete. This idle time is wasted compute. Consider spawning the auditor only after implementation is confirmed complete.
2. **No test coverage for hooks themselves**: Integration tests validate lib/ functions directly, but don't test hook scripts end-to-end (would require simulating Claude Code hook stdin/stdout). FR-004 through FR-008 have implementation but no dedicated test. This is acceptable for an MVP but should be addressed before production use.
3. **No test for parallel fan-in (FR-009/FR-010)**: The most complex concurrency scenario — multiple SubagentStop hooks racing on the same parallel step — is not covered by integration tests. The mkdir-based locking is sound in theory but untested.
4. **No test for approval gates (FR-013)**: The dispatch_approval function exists but has no integration test.

## Recommendations

- Add hook-level integration tests that pipe JSON to stdin and verify stdout JSON (can be pure bash).
- Add a parallel fan-in test that simulates concurrent agent completion.
- Consider using `/qa-pass` on a consumer project that actually runs a wheel workflow end-to-end.
