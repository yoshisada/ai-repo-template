# Wheel Test Workflow Run Tracker

Running each test workflow via `/wheel:wheel-run` skill. Documenting pass/fail + issues.

## Pass 1

| Workflow | Status | Notes | Issue |
|---|---|---|---|
| count-to-100 | pass | verified via direct engine kickstart | — |
| loop-test | pass | | — |
| team-sub-fail | pass | command exit-code propagation fixed | #004 |
| command-chain | pass | | — |
| branch-multi | pass | | — |
| agent-chain | pass | SubagentStop auto-complete fixed | #003 |
| example | pass | | — |
| composition-mega | pass | inline chain works | — |
| team-sub-worker | pass | run standalone AND as child | — |
| team-static | pass | 3 static teammates, team-wait drives | — |
| team-dynamic | pass | stdout-overwrites-file bug fixed | #006 |
| team-partial-failure | pass (parent) | bad-worker refuses shutdown; force-cleaned team dir | #007 |

Pass 1 complete. All 12 workflows archived successfully. Fixes committed during this pass:
- #003 (subagent-stop auto-complete gate)
- #004 (command exit code propagation)
- #006 (dispatch_command clobbering command-produced output files)
- #007 (bad-worker won't shutdown — workaround; root fix pending)
