# Agent Friction Notes: impl-engine

## What Went Well

- **Pre-reading during wait**: Reading all 5 owned files, the PRD, and the dispatch/context/workflow libs while waiting for the specifier gave me full context when unblocked. Zero ramp-up time once spec artifacts appeared.
- **Architecture already supports team types**: The stop hook already delegates to `dispatch_step`, so T026 (stop hook routing for team types) was already satisfied by the existing architecture. No code changes needed.
- **Phases 1-2 committed together**: State functions + engine routing are tightly coupled. Committing them together made sense since they form the foundation.

## Friction Points

- **Kiln hook gate (require-spec.sh)**: The hook blocks edits to `plugin-wheel/lib/*.sh` until at least one task is marked `[X]` in tasks.md. Had to mark T001 `[X]` before I could write the state.sh code that implements T001. This is a chicken-and-egg problem for the first task. Workaround: mark the task first, then implement.
- **File read freshness**: The Edit tool requires a "fresh" read even if the file was read earlier in the conversation. Had to re-read state.sh before the first edit even though I'd already read it thoroughly during the wait phase.
- **Specifier wait time**: Polled for ~4 minutes before spec.md appeared, then another ~3 minutes for tasks.md. Total blocked time: ~7 minutes. Not a problem since I used the time productively, but a "ready" signal from the specifier would be more efficient than polling.
- **tasks.md concurrent edits**: The impl-step-types agent was also editing tasks.md to mark their tasks. Got one "file modified since read" error due to concurrent edits. Minor — just re-read and retry.

## Suggestions for Future Runs

- Have the specifier send the unblock message only after ALL artifacts are committed (not just spec.md). I started reading spec.md before plan.md and tasks.md existed.
- Consider a shared lock or turn-taking protocol for tasks.md edits when multiple implementers write to it concurrently.
- The team-lead could pre-mark T001 as `[X]` to avoid the hook gate chicken-and-egg problem, or the hook could exempt the first task.
