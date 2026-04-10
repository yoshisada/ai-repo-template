# Issue 008: Blind teammate spawn before stop-hook instruction disrupts team-wait tracking

## Summary
When running a team workflow (e.g. tests/team-static) in the main chat, if I spawn teammates via Agent BEFORE the stop hook has instructed me to do so, the hook's post_tool_use dispatch for the teammate step captures the spawn as a "pending" teammate registration but never transitions the teammate status properly. Later, when the real stop-hook-instructed spawns come in, they land with name conflicts (worker-1 → worker-1-2) which the subagent_stop / teammate_idle handlers can't match back to the state's teammates map. team-wait then hangs with teammates stuck in `running` even after they terminate.

## Reproduction
1. Activate tests/team-static in the main chat
2. After TeamCreate runs, Agent-spawn worker-1/2/3 directly without waiting for the stop hook instruction
3. End turn — stop hook prompts "Spawn 3 teammate agent(s)..." as if none are running
4. Spawn the 3 again — they get names worker-1-2, worker-2-2, worker-3-2
5. Workers complete their sub-workflows, write output files, shut down
6. team-wait step shows only worker-1 as completed; worker-2, worker-3 still `running`
7. Parent workflow hangs on wait-all until state is manually patched

## Secondary failure
Even after team-wait completes and the workflow reaches the `team-delete` cleanup step, calling TeamDelete did nothing because:
- TeamDelete was called while `cleanup` step status was still `pending` (stop hook hadn't transitioned it yet)
- dispatch_team_delete post_tool_use handler only acts when status == `working`
- Result: team was deleted from Claude Code side but parent state still had `.teams["create-team"]` entry and `cleanup` step stuck pending

## Root cause
Two intertwined issues:
1. **Blind Agent spawns** by the lead before the stop-hook transitions the teammate step from `pending` to `working` let duplicate spawns happen, which then get auto-renamed (worker-1 → worker-1-2) and break name-based tracking.
2. **TeamDelete timing race** — calling TeamDelete before the stop hook has transitioned the cleanup step to `working` leaves the state out of sync with reality.

## Workaround
- Always wait for stop hook instructions before spawning teammates or calling TeamDelete in the main chat
- If the state gets wedged, manually patch `.teams.<ref>.teammates.<n>.status = "completed"` and `.steps[N].status = "done"`, then manually move the state file to `.wheel/history/success/`

## Status
Documented as a main-chat hazard. The wheel engine works fine when the lead follows hook instructions strictly. A belt-and-suspenders fix would be:
1. dispatch_teammate's post_tool_use handler should only accept spawns when step_status is `working` (auto-advanced by the stop hook)
2. dispatch_team_delete's post_tool_use handler should transition `pending` → `done` on TeamDelete call even if the stop hook hasn't run yet
