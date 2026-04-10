# Issue 005: wheel-runner subagent can't call team primitives

## Summary
Team workflows (`tests/team-static`, `tests/team-dynamic`,
`tests/team-partial-failure`) require the `TeamCreate`, `TeamDelete`, and
`Agent` deferred tools. The wheel-runner subagent starts without these in
its active tool registry — they must be loaded via `ToolSearch` first. The
subagent doesn't know to do that.

## Reproduction
Spawn a wheel-runner subagent and run `/wheel:wheel-run tests/team-static`.
The Stop hook's first instruction asks the subagent to call TeamCreate.
The subagent reports "tool not available" and the workflow stalls.

## Workarounds
1. Load tools at the start of the task prompt:
   `ToolSearch "select:TeamCreate,TeamDelete,Agent,SendMessage"`
2. Add team primitives to the `wheel-runner` agent definition's default tool
   list (if that agent is defined in this repo).
3. Have the wheel-run skill instructions include a tool-load step when the
   workflow has team-* step types.

## Status
Not a wheel engine bug — it's a tool-loading gap. Documented for follow-up.
For this pass, use option 1 (explicit ToolSearch in prompts).
