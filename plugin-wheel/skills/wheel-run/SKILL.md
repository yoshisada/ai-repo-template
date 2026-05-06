---
name: wheel-run
description: Start a workflow by name or plugin:name. Validates the workflow JSON, creates per-agent state file, and activates hook interception. Usage: /wheel:wheel-run <workflow-name> or /wheel:wheel-run <plugin>:<workflow-name>
---

# Wheel Run — Start a Workflow

Start a named workflow so that wheel hooks begin intercepting Claude Code events. Supports both local workflows (`workflows/<name>.json`) and plugin-provided workflows (`<plugin>:<workflow-name>`).

## User Input

```text
$ARGUMENTS
```

## Step 1: Validate and Resolve

Run the validation script. It resolves the workflow file (including plugin workflows), validates the JSON, checks for duplicates and circular references, and prints a short JSON summary — **without exposing workflow step details to your context**.

```bash
"$SKILL_BASE_DIR/../../bin/validate-workflow.sh" "$ARGUMENTS"
```

If this fails, **stop here** and show the error to the user.

On success it prints a JSON object like:
```json
{"name": "my-workflow", "step_count": 5, "activate_name": "my-workflow", "plugin_dir": "/path/to/plugin"}
```

## Step 2: Activate

Run activate.sh directly in its own Bash call. The hook intercepts it and creates the state file. Do not combine it with other commands (e.g., `mkdir -p .wheel && activate.sh`) — the hook's regex for detecting activate.sh expects the command to start with `activate.sh` or a path prefix, not with other commands chained before it.

```bash
<plugin_dir>/bin/activate.sh <activate_name>
```

The PostToolUse hook intercepts this call, reads the workflow file, creates the state file with proper ownership, and runs kickstart to advance through any automatic initial steps.

## Step 3: Confirm

```bash
echo "Workflow started. Hooks are now active."
echo "Run /wheel:wheel-status to check progress, /wheel:wheel-stop to deactivate."
```

That's it. Do NOT read the state file or workflow file — the hooks will tell you what to do next.

## Rules

- If `$ARGUMENTS` is empty, ask the user for a workflow name. List available workflows from `workflows/*.json` and installed plugins.
- Never create a state file directly — always go through activate.sh + hook.
- Plugin workflows are read-only (FR-030) — they execute from the plugin's install path. Users can copy to `workflows/` to customize, and the local copy takes precedence.

## Execution Behavior (NON-NEGOTIABLE)

After activation, **all workflow progression happens through hooks**. Do not manually advance the cursor, update step statuses, or modify state files yourself.

### The driving loop

Drive the workflow turn-by-turn. Each turn does exactly ONE of:

1. **Call the tool the hook just told you to call** (TeamCreate, Agent spawn, SendMessage, TeamDelete, …) — then end the turn. The PostToolUse hook will advance the cursor.
2. **End the turn** so the Stop hook can flip a `pending` step to `working` and emit instructions for the next call.

That's the entire loop: one tool call → end turn → read the hook's next instruction → repeat. Multiple cursor advances per turn are the hook's job, not yours.

### Trust the hooks (NON-NEGOTIABLE)

Hooks are authoritative. If a step seems stuck, **end your turn** — the Stop hook fires at turn boundaries and is the ONLY thing that transitions `pending` → `working`. Spinning more tool calls in the same turn cannot unstick a stop-gated transition; only ending the turn can.

Specifically, you MUST NOT:
- **Investigate wheel internals.** No reading `dist/lib/dispatch.js`, no grep of `post-tool-use.js`, no sed/cat of plugin source. The hooks are a black box. If they appear broken, that's a bug to file, NOT something for you to debug mid-run.
- **Manually invoke hooks** with simulated stdin to "test" them. Hook execution is the harness's job.
- **Run wheel-stop because a step looks stuck.** A `pending` step at end of turn is normal — the Stop hook will flip it next turn. Don't preempt it.
- **Re-call a tool that "didn't seem to work."** If TeamCreate succeeded, it succeeded. The cursor advances on the NEXT hook fire — usually after your turn ends. Calling TeamCreate again or TeamDelete-then-TeamCreate produces a worse state, not a better one.
- **Read the workflow JSON file or state files directly.** Use `/wheel:wheel-status` if you need to check progress; the hook's `additionalContext` text is the only progression signal you should act on.

### What "the hook told you to call" means

The PostToolUse / Stop hook returns `{"decision": "block", "additionalContext": "<instructions>"}` when it needs you to do something. The `additionalContext` text is the directive — read it once, do exactly what it says, end your turn. No paraphrasing, no "I'll also check X first," no follow-up verification calls.

If the hook returns `{"decision": "approve"}` and you didn't get an `additionalContext`, the workflow is either advancing automatically (commands/loops/branches handle themselves) or waiting on a Stop-hook transition — end your turn.

### Other invariants

- **Do NOT spawn sub-agents** for any workflow step — including `"type": "workflow"` steps. Workflow steps are like function calls: the referenced workflow runs inline in the same conversation, dispatched by the hook system.
- **Do NOT manually archive or delete state files.** The hook system owns the workflow lifecycle.
- **Do NOT batch multiple tool calls in one turn** trying to "make progress faster." One tool call per turn, then end. The hooks' Stop transitions need turn boundaries to fire.
