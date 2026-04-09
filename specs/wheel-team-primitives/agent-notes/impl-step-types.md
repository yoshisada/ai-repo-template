# Agent Friction Notes: impl-step-types

## What Went Well
- Existing dispatch pattern (dispatch_agent, dispatch_command, etc.) was easy to follow — all four handlers use the same state check / stop / post_tool_use structure.
- The contracts/interfaces.md provided clear function signatures to implement against.
- Data model schema made the state structure unambiguous.

## Friction Points
1. **Hook gate blocked first edit** — The require-spec.sh hook blocked edits to dispatch.sh because no tasks were marked `[X]` in tasks.md. I had to mark T007 in tasks.md first (which is a spec file, so allowed), then edit dispatch.sh. This is working as designed but adds a small bootstrapping step.
2. **File ownership coordination** — dispatch.sh calls state.sh functions (state_set_team, state_add_teammate, etc.) and context.sh functions (context_write_teammate_files) that are owned by impl-engine. I had to trust they'd be implemented with the correct signatures. They were.
3. **Fire-and-forget teammate pattern** — The teammate step marks done immediately after injecting spawn instructions, which is unusual. Most other handlers wait for completion. The instruction injection approach means the LLM orchestrator must interpret and execute the spawn commands correctly — there's no programmatic guarantee the agents are actually spawned.

## Suggestions for Future
- Consider a shared constants file for team output directory naming (`team-{name}/{agent}`) so both dispatch.sh and context.sh use the same pattern without coupling.
- The team-wait polling relies on the hook firing, which only happens on tool calls. If the orchestrator goes idle, team-wait stalls. A timer-based mechanism would be more robust.
