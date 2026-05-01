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

- **Do NOT read the workflow JSON file.** The validation script handles that. You don't need to know step details — hooks will instruct you.
- **Do NOT read state files.** Use `/wheel:wheel-status` if you need to check progress.
- **Do NOT spawn sub-agents** for any workflow step — including `"type": "workflow"` steps. Workflow steps are like function calls: the referenced workflow runs inline in the same conversation, dispatched by the hook system.
- **Do NOT manually stop workflows.** Use `/wheel:wheel-stop` and let the hook handle archival.
- **Do NOT manually archive or delete state files.** The hook system owns the workflow lifecycle.
- Your only job after activation is to **execute the current step's work** as instructed by hooks, and let hooks handle progression to the next step.
