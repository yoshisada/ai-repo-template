# Issue 006: dispatch_command stored stdout in state's `.output` field instead of file path

## Summary
When a `command` step declares an `output` file path (e.g.
`.wheel/outputs/work-items.json`), `dispatch_command` wrote stdout to that
file — good — but then stored the **stdout text** in the state's
`.steps[$idx].output` field via `context_capture_output`. All other step
types store the file path there. This broke any downstream step that reads
`.steps[$idx].output` expecting a path.

## Reproduction
Run `tests/team-dynamic`. Step 1 `generate-work` produces a JSON array in
`.wheel/outputs/work-items.json`. Step 2 `spawn-workers` has `loop_from:
generate-work`, which reads `.steps[0].output`, expects either a file path
or raw JSON, then calls `jq type == "array"`. Observed: `.steps[0].output =
"5\nitems generated"` (stdout), fails `-f` check, fails JSON parse, step
marked `failed`.

## Root cause
`plugin-wheel/lib/dispatch.sh` line ~885:
```bash
context_capture_output "$state_file" "$step_index" "$truncated_output"
```
All other call sites pass `output_key` (the file path). This one was
inconsistent.

## Fix
When `.output` is declared, store the **file path** in state, not stdout.
stdout is already in `command_log[]` for audit.

```bash
if [[ -n "$output_key" ]]; then
  mkdir -p "$(dirname "$output_key")"
  printf '%s\n' "$truncated_output" > "$output_key"
  context_capture_output "$state_file" "$step_index" "$output_key"
fi
```

## Status
Fixed in this session.
