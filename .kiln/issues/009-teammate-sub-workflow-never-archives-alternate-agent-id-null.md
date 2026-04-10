# Issue 009: Teammate sub-workflow state files leak because alternate_agent_id is never set

## Summary
When running a team workflow (`tests/team-static`), each teammate worker runs `tests/team-sub-worker` as its sub-workflow. The workers send their haiku via SendMessage, get shutdown, and the parent `team-wait` completes cleanly — BUT the workers' own sub-workflow state files never archive. They're left in `.wheel/` frozen at cursor=1 (step `do-work`, status `working`).

## Reproduction
1. `/wheel-run tests/team-static`
2. Follow the stop-hook flow: TeamCreate → Agent spawn (3 workers) → wait for SendMessage haikus → TeamDelete
3. Parent workflow archives cleanly to `.wheel/history/success/team-static-test-*.json`
4. Check `.wheel/state_*.json` — observe 3 orphaned `team-sub-worker` state files with:
   - `workflow_name: team-sub-worker`
   - `status: running`
   - `cursor: 1`
   - `steps[1].id: do-work`, `status: working`
   - **`alternate_agent_id: null`** ← the smoking gun

## Root cause (hypothesized)
`alternate_agent_id` is supposed to be set via commit `11b576b` ("fix: map teammate raw agent IDs to team-format IDs via atomic mkdir lock") so the post_tool_use / subagent_stop / teammate_idle hooks can resolve `worker-1@test-static-team` → the raw-id-keyed state file (`state_a1e8cce65cf2af681.json`).

When `alternate_agent_id` is null, the hooks can't find the state file when the worker emits tool uses or stop events, so the wheel engine inside the worker's sub-agent context never drives the sub-workflow past the `do-work` agent step. The worker agent itself completes (writes output, SendMessages, approves shutdown), but its wheel state is never updated.

Possible causes to investigate:
1. The atomic mkdir lock from 11b576b isn't firing for workers spawned by the `teammate` step dispatcher — maybe the dispatch code path doesn't write `alternate_agent_id` into the state before the worker starts
2. A race where the worker's first tool call (ToolSearch) happens before the mapping is written
3. The mapping is only applied when spawning via `dispatch_teammate` / `dispatch_team_create` but not when the worker itself activates its own sub-workflow via `activate.sh`

## Why parent still works
`team-wait` doesn't read child sub-workflow state. It tracks `.teams.<ref>.teammates[*].status`, which gets updated via the subagent_stop hook on the PARENT's state file when the worker's Claude Code agent terminates. Parent archives cleanly because workers SendMessage + shutdown regardless of their own sub-workflow state.

## Impact
- Silent orphan state file accumulation in `.wheel/` after every team-static run
- Each run adds N orphans where N = teammate count
- Eventually `validate-workflow.sh` notices them and logs "Note: Other workflows already running" which is misleading
- No functional regression for the parent workflow, but it's a cleanup/hygiene bug

## Workaround
After each team run, `mv .wheel/state_<id>.json .wheel/history/stopped/` for any `team-sub-worker` states left behind. Pass 2 already accumulated many of these — see `.wheel/history/stopped/state_a*-orphan-*.json`.

## Status
**Fixed.** Root cause was the mkdir-based lock in `post-tool-use.sh`: keyed on `agent_map_${tid}` (stable across runs) and never cleaned up. Second and subsequent runs hit stale lock dirs, `mkdir` failed, the claim loop fell through, and `alternate_agent_id` stayed null.

The underlying reason a lock existed at all was that PostToolUse hook input for Bash doesn't include `team_name`/`name`, so the hook had to guess which teammate slot it represented by scanning the parent state and claiming one atomically.

**Resolution**: eliminated the ambiguity at the source. Each teammate spawn instruction now includes an explicit `--as <tid>` flag in the activate.sh invocation (e.g. `activate.sh tests/team-sub-worker --as worker-1@test-static-team`). The post-tool-use hook parses the flag from the command string via bash parameter expansion and writes `alternate_agent_id` directly — no parent scan, no lock, no race. The entire mkdir-lock claim loop is removed.

Verified: after the fix, a fresh team-static run produced three child sub-workflow archives with correct `alternate_agent_id` values (`worker-1@test-static-team`, `worker-2@test-static-team`, `worker-3@test-static-team`), all reaching the terminal `done` step, no orphaned state files left behind.
