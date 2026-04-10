# Issue 003: SubagentStop auto-completes unfinished agent steps

## Summary
`dispatch_agent`'s `subagent_stop` case unconditionally marks the current step
done and calls `handle_terminal_step`, regardless of whether the step's
declared `output` file exists. This causes any agent step to be "completed"
prematurely whenever Claude Code fires a SubagentStop event on the enclosing
subagent session — even if the agent never wrote anything.

## Reproduction
1. Run `/wheel:wheel-run tests/agent-chain` inside a wheel-runner subagent.
2. Write the `draft-summary` step's output file.
3. Observed: Claude Code fires SubagentStop on the wheel-runner. The hook's
   `dispatch_agent subagent_stop` case marks `review-and-finalize` done without
   the agent ever writing `reports/health-report.md`.

## Log evidence (from a real run)
```
subagent_stop dispatch_step idx=3 id=review-and-finalize type=agent
subagent_stop handle_terminal_step step_id=review-and-finalize
```

## Root cause
The `subagent_stop` case was designed for a model where each agent step runs
in a separate Task subagent. In reality, the enclosing wheel-runner subagent
is ONE subagent running the whole workflow; SubagentStop fires on its turn
transitions and exit, not per-step. Auto-completing on SubagentStop is wrong.

## Fix
- `dispatch_agent subagent_stop`: only mark done if the step's output file
  exists (same gate as the `stop working` branch). Otherwise no-op.
- Same fix for `handle_terminal_step` chain path — only archive if output is
  actually present.

## Status
Fixing in this session.
