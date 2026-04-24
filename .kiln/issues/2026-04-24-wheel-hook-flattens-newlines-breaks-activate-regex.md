---
id: 2026-04-24-wheel-hook-flattens-newlines-breaks-activate-regex
title: Wheel PostToolUse hook flattens newlines in tool_input.command, silently breaking activate.sh detection in multi-line Bash calls
type: issue
date: 2026-04-24
status: open
severity: high
area: wheel
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-wheel/hooks/post-tool-use.sh
---

## Summary

`plugin-wheel/hooks/post-tool-use.sh:11` sanitizes the hook input JSON with `tr '\n' ' ' | sed 's/[[:cntrl:]]/ /g'` BEFORE jq parsing. This is intended to defend jq against raw control characters in JSON string values, but it also destroys literal newlines *inside* the `tool_input.command` string value — which is the command the LLM just executed via the Bash tool.

Once newlines are flattened, any multi-line Bash tool call gets joined into one long line before the hook's activate-detection regex sees it:

```bash
grep -E '^[[:space:]]*(bash[[:space:]]+)?("|'"'"')?(\./|/)?[^[:space:]()"'"'"']*activate\.sh([[:space:]]|$)'
```

The `^` anchor requires `activate.sh` at the start of a line (modulo leading whitespace / `bash` prefix / quotes). After the flatten, if anything precedes activate.sh on the combined line, the regex fails to match — and the hook silently classifies the call as `path=normal` instead of `path=activate`. No state file is created. The workflow never runs. The Bash call returns exit 0. There is no user-visible error.

## Reproducer

```bash
# WORKS — single-line activate call, regex matches
/path/to/activate.sh /path/to/workflow.json
```

```bash
# BREAKS — multi-line; activate.sh no longer at start of flattened line
echo "some input" > .wheel/outputs/roadmap-input.txt
/path/to/activate.sh /path/to/workflow.json
sleep 3
```

Log evidence (`.wheel/logs/wheel.log`):
```
2026-04-24T09:54:02Z|...|path=activate
2026-04-24T09:54:03Z|...|result=activate-failed workflow=... reason=unresolved-or-invalid
```

vs:
```
2026-04-24T09:58:25Z|...|path=normal
2026-04-24T09:58:25Z|...|result=no-state reason=unresolved
```

## Why this is high severity

- **Silent failure.** No error surfaces to the caller. activate.sh returns 0; `$?` looks fine; the only symptom is "no state file appeared" — easy to miss in automation.
- **Contract pushed onto callers.** The `/wheel:wheel-run` skill documents the workaround ("Run activate.sh as a **separate, single-line Bash call**"), but that makes the hook's parsing fragility a caller's problem. Any caller that deviates — including a future Claude deciding to batch shell work for efficiency — silently breaks workflow activation.
- **Latent by default.** Tests in `workflows/tests/` activate through the skill, which always produces single-line Bash calls, so the happy path never exercises the bug.

## Root cause

Line 11 of `post-tool-use.sh`:

```bash
HOOK_INPUT=$(printf '%s' "$RAW_INPUT" | tr '\n' ' ' | sed 's/[[:cntrl:]]/ /g')
```

The intent (per the preceding comment) is to let jq parse hook JSON that Claude Code emits with raw control characters inside string values. But jq already handles valid JSON with `\n` escape sequences natively — the preemptive flatten is unnecessary for well-formed JSON, and actively destructive when the command field legitimately contains newlines.

## Proposed fix

**Option A (preferred):** Drop the blanket sanitization. Try `jq` on `RAW_INPUT` directly. Only fall back to sanitization if the parse fails — and even then, prefer a JSON-aware approach (e.g., normalize via `python3 -c "import json,sys; ..."` which properly escapes control chars as `\uXXXX`) instead of `tr`.

**Option B:** Extract `tool_input.command` from raw JSON with `jq -r` FIRST (before any sanitization), operate on that value, and only sanitize other fields if needed downstream.

**Option C (minimum viable):** Loosen the activate-detection regex to find `activate.sh` anywhere in the command (not just at line-start), with an additional guard against prose-false-matches (e.g., require the match to be followed by a path-looking argument). Reopens the false-positive risk the current comment at line 127 warned about — less clean than A/B.

## Acceptance

- A multi-line Bash tool call that includes `/path/activate.sh <workflow>` anywhere in its body successfully activates the workflow (state file created, workflow progresses).
- The `/wheel:wheel-run` skill's "single-line Bash call" instruction can be removed.
- Existing single-line activation tests still pass.
- Hook logs for the fix: `path=activate` and `result=activate` on multi-line Bash commands.

## Pipeline guidance

This deserves the full pipeline — specifier → plan → tasks → implement → **auditor → retrospective**. Auditor verifies no silent-failure regression sneaks back in; retrospective should capture why the latent bug persisted (tests only cover the skill's happy path) and what tests would catch this class of bug in future (hook-input fuzzing on multi-line tool commands).
