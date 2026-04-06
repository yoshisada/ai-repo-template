# Auditor Friction Notes: wheel-per-agent-state

## What went well

- Clean implementation — all 6 hooks follow an identical preamble pattern, making audit straightforward.
- `resolve_state_file` in guard.sh is well-structured with clear FR comments. Easy to trace each requirement.
- Contract signatures matched exactly. No deviations needed.
- Smoke tests all passed on first attempt — no bugs found.

## Friction

1. **Blocked for a long time**: My task was assigned before the specifier and implementer finished. I had to send multiple "not ready" messages. The pipeline should not assign auditor until Task #2 is actually marked completed.
2. **No automated tests to run**: The plugin has no test suite, so "smoke testing" means writing ad-hoc bash scripts. This is fragile and non-repeatable. A future improvement would be a `tests/` directory with bats or similar.
3. **set -euo pipefail + subshell capture**: All hooks use `set -euo pipefail` and then do `STATE_FILE=$(resolve_state_file ...)` followed by `if [[ $? -ne 0 ]]`. Under `set -e`, if `resolve_state_file` exits 1, the script exits before reaching the `$?` check. This works currently because `resolve_state_file` returns 1 via `return 1` (not `exit 1`) and the subshell captures it. But it's fragile — if someone adds `set -e` inside guard.sh, it would break. Worth documenting.

## Suggestions for next time

- Do not assign auditor task until implementer task status is `completed`.
- Consider adding a minimal smoke test script to the plugin itself.
