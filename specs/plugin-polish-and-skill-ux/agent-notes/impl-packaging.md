# Agent Friction Notes: impl-packaging

## What was confusing or unclear

- The task list includes T015 and T016 (Phase 9 validation) which are cross-cutting and not explicitly assigned to either implementer. I assumed they were mine since they primarily validate packaging concerns (package.json files array, backwards compat for workflows/init).
- The contract says to add syncWorkflows() and "call it from syncShared()" but init.mjs didn't previously import `readFileSync` or `basename` — the contract should note required import additions.

## Where I got stuck

- No real blockers. The tasks were well-scoped and the existing codebase patterns (copyIfMissing, ensureDir) made the implementation straightforward.

## What could be improved

- The contract for FR-006 references "lines 88-96" but line numbers shift as edits are made. Use a code pattern or function reference instead.
- T015/T016 ownership should be explicitly assigned to one of the implementers in the parallel execution plan.
