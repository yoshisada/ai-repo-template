# Issue 007: Teammate refuses shutdown after sub-workflow failure

## Summary
During `tests/team-partial-failure`, the `bad-worker` teammate runs
`tests/team-sub-fail` which is expected to exit-fail. After the sub-workflow
archives to `failure/`, the teammate returns to idle — but then refuses
shutdown_request messages. It sends idle notifications indefinitely and
TeamDelete reports "Cannot cleanup team with 1 active member(s)".

## Reproduction
1. `/wheel-run tests/team-partial-failure`
2. good-worker + bad-worker spawn, bad-worker's `team-sub-fail` archives to failure.
3. Parent workflow `verify` step confirms mixed results and archives to success.
4. Stop hook asks for TeamDelete.
5. SendMessage with `{"type":"shutdown_request"}` to bad-worker — good-worker
   responds and terminates, bad-worker just sends another idle notification.
6. TeamDelete fails: `Cannot cleanup team with 1 active member(s): bad-worker`.

## Likely cause
The wheel-runner agent loop, after its sub-workflow hit failed archival,
may be stuck waiting for hook instructions that never come, and isn't
processing inbox shutdown protocol messages. The good-worker path (normal
success) handles shutdown correctly.

## Workaround
Force-remove `~/.claude/teams/<team>/` and `~/.claude/tasks/<team>/`
directly to abandon the stuck teammate. The parent workflow itself
archived cleanly — only the team cleanup lingered.

## Status
bad-worker DID eventually shutdown on its own (~30s after the last
shutdown_request), long after the parent workflow was cleaned up
manually. So the root problem is latency, not a hard lockup: the
post-failure wheel-runner takes a very long time to drain shutdown
protocol messages compared to the normal success path. Parent workflow
passed. Follow-up: investigate why shutdown handling is delayed after
a failed sub-workflow archives.
