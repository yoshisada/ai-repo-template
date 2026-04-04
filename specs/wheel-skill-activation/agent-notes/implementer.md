# Implementer Friction Notes — wheel-skill-activation

## What Went Well

- Contracts/interfaces.md was precise enough to implement all 12 tasks without ambiguity
- The hook guard clause pattern was consistent across all 6 hooks — easy to apply uniformly
- Phase dependencies were well-defined; no blocking surprises

## Friction Points

1. **Gate 4 blocked the first edit attempt**: The `require-spec.sh` hook blocked my initial edit to workflow.sh because no tasks were marked `[X]` yet. The implementing lock mechanism resolved this once I ran `/implement`. This is expected behavior but worth noting — raw edits outside `/implement` will always be blocked at Gate 4 for new features.

2. **No existing skill SKILL.md to reference**: plugin-wheel had no pre-existing skills, so I referenced the kiln plugin's skills for format. The contracts/interfaces.md provided the shell command patterns which was sufficient.

3. **engine_init() creates state.json if missing**: The specifier flagged this correctly. After the guard clause change, hooks only run when state.json exists, and engine_init only reaches the state_init call if state.json doesn't exist (which shouldn't happen with the guard in place). No code change was needed in engine.sh itself — the guard clause handles it.

## Suggestions for Future

- Consider adding a `plugin.json` manifest that declares skills so the plugin system can validate skill discovery at install time rather than relying on filesystem convention.
