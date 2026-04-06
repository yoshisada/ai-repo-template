# Implementer Friction Notes — wheel-per-agent-state

## What went well

- The contracts/interfaces.md was clear and unambiguous. Every function signature was specified with exact params, return types, and exit codes.
- The hook preamble pattern in the contracts made updating all 6 hooks mechanical — read stdin first, call resolve_state_file, pass result to engine_init.
- The plan's "Files NOT changing" section saved time by confirming dispatch.sh, workflow.sh, context.sh, and lock.sh didn't need modification.

## What was confusing

- **session_id access in skills**: The spec noted this as an "open question" (how the skill accesses session_id). I implemented it as CLAUDE_SESSION_ID env var with a generated fallback. The contracts didn't specify this — it would have been helpful to have a definitive answer from the specifier.
- **engine_init used to create state**: The old engine_init would create state.json if it didn't exist. The new signature removes that behavior, but the contracts didn't explicitly say "remove the state creation logic from engine_init" — I inferred it from "Does NOT create state if missing (hooks only run when state exists)" in the task description.

## Where I got stuck

- Nowhere significant. The 3-phase decomposition (libs -> hooks -> skills) had clean dependency ordering and each phase was self-contained.

## What could be improved

- The spec should resolve the session_id access mechanism definitively rather than leaving it as an open question for the implementer.
- The contracts could specify which existing functions are REMOVED (guard_check) alongside the new ones that replace them, to make the delta clearer.
