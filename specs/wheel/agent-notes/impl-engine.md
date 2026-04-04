# Friction Notes: impl-engine

## What Went Well

- Interface contracts in `contracts/interfaces.md` were clear and complete -- every function had defined params, return types, and exit codes. Zero ambiguity during implementation.
- The plan's architecture decision to make hooks thin dispatchers (AD-006) kept hook files simple (30-40 lines each) while concentrating logic in testable lib modules.
- Phase ordering was correct -- no circular dependencies encountered. State -> Workflow+Lock -> Dispatch+Context+Engine -> Hooks was the right sequence.

## Friction Points

1. **tasks.md concurrent edits**: The tasks.md file was being modified by the other implementer (impl-plugin) at the same time. Multiple edit attempts failed with "file modified since read" errors. This required re-reading the file before each edit. In a real multi-agent pipeline, tasks.md would benefit from per-agent task sections or a lock mechanism.

2. **Workflow file discovery convention**: The contracts don't specify how hooks discover which workflow file to use. I implemented a convention (first `.json` in `workflows/` or `WHEEL_WORKFLOW` env var) but this should be documented in the spec or contracts.

3. **Command step chaining (FR-020)**: The `exec "$0"` re-exec pattern for chaining consecutive command steps requires the hook script to export `WHEEL_HOOK_SCRIPT` and `WHEEL_HOOK_INPUT` globals. This is an implicit contract not captured in interfaces.md.

4. **PostToolUse hook output**: The contract says PostToolUse outputs JSON but the hook is "logging only, never blocks." In practice, the hook exits silently (no stdout) since Claude Code PostToolUse hooks don't consume response JSON the same way PreToolUse hooks do.

## Suggestions for Future

- Add a `WHEEL_WORKFLOW` discovery mechanism to the engine (e.g., `.wheel/config.json` with a `workflow` field) rather than relying on convention.
- Consider adding `set -euo pipefail` guard to lib modules (currently only in hooks) for stricter error handling.
- The dispatch_command `eval` for executing shell commands is necessary for flexibility but should be documented as a security consideration for consumer projects.
