---
name: wheel-status
description: Show the status of all running workflows. Displays workflow name, current step, progress, session/agent IDs, elapsed time, and any pending-user-input rows.
---

# Wheel Status — Check Workflow Progress

Display the current state of all active workflows, including any steps waiting on user input (FR-015, wheel-user-input).

## Step 1: Invoke the `wheel-status` CLI

The full rendering logic (including FR-015's pending-input rows with reason + elapsed time) lives in `plugin-wheel/bin/wheel-status`. This skill just invokes it.

```bash
PLUGIN_DIR="$SKILL_BASE_DIR/../.."
"${PLUGIN_DIR}/bin/wheel-status"
```

## Rules

- This skill takes no arguments.
- Read-only — the CLI does not modify any state.
- If a state file is corrupted (invalid JSON), the CLI will report the error and continue. If this happens repeatedly, run `/wheel:wheel-stop` to clean up.
- Rows marked `[awaiting input]` show the step id, the reason passed to `wheel flag-needs-input`, and the elapsed time since the flag was set (format: `Nm Ss` or `Ns`).
