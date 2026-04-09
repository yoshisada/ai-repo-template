# Agent Friction Notes: Auditor

## What went well

- All 12 FRs had clear, verifiable acceptance criteria in the PRD. Every FR mapped to a specific file and code change, making verification straightforward.
- Task statuses were accurate: all 16 tasks in tasks.md were marked [X], matching the completed TaskList status for both implementers.
- The two-implementer split (packaging vs skills) kept file ownership clean with zero conflicts.

## What was confusing or unclear

- The audit task instructions say to "Run /audit" but as an agent I cannot invoke skills directly. I performed the audit manually by reading each FR against the code, which is what /audit does internally anyway.
- The task said "Blocked by: Tasks #2 and #3" but when I was first activated, Task #1 was still in_progress and #2/#3 were pending. The blocking chain was #1 -> #2/#3 -> #5, not just #2/#3 -> #5. The instructions could have mentioned this transitive dependency.

## Where I got stuck

- Initial activation came before any implementation was done. I had to send two "blocked" messages and wait for the team lead to confirm unblocking. This is correct behavior per the instructions, but it would be more efficient if the auditor agent was not spawned until its dependencies were actually complete.

## Suggestions for next time

- Spawn the auditor only after implementer tasks are confirmed completed, rather than at team creation time. This avoids idle waiting and wasted context.
- Clarify that the auditor should perform a manual code-level FR verification rather than literally invoking /audit (which is a skill, not runnable by sub-agents).
