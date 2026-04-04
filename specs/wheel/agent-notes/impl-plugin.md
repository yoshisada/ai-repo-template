# Impl-Plugin Agent Notes

## What Went Well
- Phase 1 (plugin structure) had zero dependencies and completed immediately
- Example workflow design (command + agent + command) effectively demonstrates all three interaction patterns in 3 steps
- Integration tests caught a real Bash gotcha: `((VAR++))` returns exit code 1 when VAR starts at 0, which fails under `set -euo pipefail`. Fixed by using `VAR=$((VAR + 1))` instead.
- Tests pass against impl-engine's lib modules (state.sh, workflow.sh, lock.sh) without needing the full engine/hooks -- good separation of concerns

## Friction Points
- The `set -euo pipefail` + arithmetic increment bug cost one debug cycle. This is a well-known Bash pitfall but easy to miss. Future shell test templates should use `VAR=$((VAR + 1))` by default.
- init.mjs hook merging logic needs to handle the case where a consumer already has hooks on the same events from other plugins. Current implementation checks for exact command match, but the nested structure (matcher + hooks array) makes dedup slightly awkward.
- Parallel task execution between impl-engine and impl-plugin worked well since file ownership was clearly delineated. No conflicts.

## Test Coverage
- 45 assertions across 4 test suites, all passing
- Covers: linear workflow (US1), resume (US2), command steps (US1), branch/loop control flow (US5)
- Not covered by my tests: parallel fan-out/fan-in (US3), approval gates (US4), audit trail (US6) -- these depend on hooks and engine dispatch owned by impl-engine
