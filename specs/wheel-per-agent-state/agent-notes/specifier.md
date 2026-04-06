# Specifier Friction Notes

## What went well
- PRD was thorough and prescriptive — the 11 FRs mapped directly to spec FRs with no ambiguity.
- The "previous feature" PRD (wheel-session-guard) provided essential context for understanding what `guard.sh` currently does and why the ownership model is changing.
- File list in the PRD made it clear which files change and which don't.

## What was confusing
- The relationship between `engine_init` and `state_init` was unclear at first. `engine_init` currently calls `state_init` internally if state doesn't exist, but in the new design the skill calls `state_init` directly and hooks call `engine_init` with an already-resolved path. The PRD doesn't spell out that `engine_init` should stop creating state.
- The PRD says "guard.sh — simplified or removed" which is ambiguous. I chose to keep the file but replace the function with `resolve_state_file` since hooks still need a shared function.

## What could be improved
- The PRD's open question about "How does the skill access session_id?" is unresolved. The spec and plan assume it's available but don't specify the mechanism. The implementer will need to figure this out (likely an environment variable or extraction from conversation context).
- The PRD mentions `engine_kickstart` needs to use session_id-only filename but doesn't mention that `engine_init` also needs to change. These are tightly coupled and should be documented together.
