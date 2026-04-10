# Issue 004: dispatch_command loses command exit code

## Summary
`dispatch_command` captures command output and exit code like this:

```bash
output=$(eval "$command" 2>&1) || true
cmd_exit_code=${PIPESTATUS[0]:-$?}
```

The `|| true` resets `$?` to 0 and `PIPESTATUS[0]` to 0 for the `true`
command, so `cmd_exit_code` is ALWAYS 0 regardless of whether the subshell
succeeded or failed. The step is then always marked "done".

## Reproduction
Run `/wheel:wheel-run tests/team-sub-fail`. The single step runs
`echo ... && exit 1`. Expected: step status "failed", workflow status
"failed", archived to `.wheel/history/failure/`. Observed: step "done",
workflow "running", archived to `.wheel/history/success/`.

## Fix
```bash
output=$(eval "$command" 2>&1) && cmd_exit_code=0 || cmd_exit_code=$?
```
or equivalently an if/else around the assignment. This preserves the
subshell's real exit code.

## Status
Fixing in this session.
