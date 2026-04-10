# Issue 001: handle_terminal_step archives failed workflows to success/

## Summary
`handle_terminal_step` in `plugin-wheel/lib/dispatch.sh:123-125` chooses the archive directory by string-matching `*failure*` against the step ID. This is a fragile heuristic — a step with `id="fail-step"` that exits non-zero (like `tests/team-sub-fail`) is still archived to `.wheel/history/success/` because the id doesn't literally contain the substring "failure".

## Reproduction
Run `/wheel:wheel-run tests/team-sub-fail`. The single command step runs `echo ... && exit 1`. State transitions to `failed`, but the terminal archive lands in `success/` instead of `failure/`.

## Root cause
```bash
local archive_dir=".wheel/history/success"
if [[ "$step_id" == *"failure"* ]]; then
  archive_dir=".wheel/history/failure"
fi
```

It should use the actual execution result (state.status field or step status) instead of grepping the id.

## Fix
Check the state file's `status` field (or the specific step's `status`). If either is `"failed"`, archive to `failure/`. Otherwise `success/`. Preserve the step-id fallback only as a last resort for backward compat.

## Status
Fixing in this session.
