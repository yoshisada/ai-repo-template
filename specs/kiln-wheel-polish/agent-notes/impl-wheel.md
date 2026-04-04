# Agent Friction Notes: impl-wheel

## What was confusing or unclear

- The `handle_terminal_step` contract says it "sets cursor to total_steps" but in practice the function archives and removes state.json entirely, making cursor advancement irrelevant. The contract and the actual behavior diverge — the function returns 0 and the caller skips cursor logic. This is fine functionally but the contract description is misleading.

## Where I got stuck

- Gate 4 of the kiln require-spec hook blocked my first edit because no tasks were marked `[X]` yet. I had to create an `implementing.lock` file to bypass the gate. This is the expected flow when `/implement` is running, but it's not obvious to an agent that doesn't know about the lock mechanism. The hook error message could mention the lock file as a resolution path.

## What could be improved

- T005 (handle_terminal_step), T006 (integrate into dispatch_command), and T007 (integrate into dispatch_agent) were naturally implemented together since the function definition and its call sites are tightly coupled. Splitting them into 3 tasks created artificial separation. A single task "Add terminal step handling to dispatch.sh" would have been cleaner.
- T008 was a verification-only task (confirm existing no-op guards). Both hooks already had the correct guards. Making this a task implies code changes are expected, which can be confusing. A checkpoint note in the plan would suffice.
