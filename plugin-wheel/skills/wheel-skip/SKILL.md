---
name: wheel-skip
description: Abandon a stalled interactive wheel step — writes a cancel sentinel and clears awaiting_user_input.
---

# Wheel Skip — Cancel a Stalled Interactive Step

When a workflow step is waiting on user input (set via `wheel flag-needs-input`) and you no longer want to answer, `/wheel:wheel-skip` writes a cancel sentinel to the step's output file and clears the `awaiting_user_input` flag. The next Stop hook fire advances the workflow past the cancelled step (downstream steps are expected to inspect the output shape and handle the `{"cancelled": true}` sentinel).

This skill is the documented escape hatch for FR-011 / FR-012. It is inline bash; no wheel workflow is dispatched.

## Step 1: Invoke the `wheel-skip` CLI

The full five-step logic (resolve state → check awaiting flag → write cancel sentinel → clear flag → confirmation) lives in `plugin-wheel/bin/wheel-skip` so it can be exercised by unit tests. This skill simply invokes it.

```bash
PLUGIN_DIR="$SKILL_BASE_DIR/../.."
"${PLUGIN_DIR}/bin/wheel-skip"
```

That's it. The CLI prints a friendly message if there's nothing to skip (exit 0), or confirms the skip after writing the sentinel and clearing the flag.

## Rules

- If no active workflow or no step is awaiting input, print a friendly message and exit 0 (not an error — `/wheel:wheel-skip` is a safe no-op in those cases).
- The cancel sentinel shape is always exactly `{"cancelled": true, "reason": "user-skipped"}`. Downstream steps that read the output are expected to check for this shape.
- If the output file already exists, it is overwritten (explicit abandon intent).
- If step 3 succeeds but step 4 fails, the output file is already written; the next Stop hook fire will still advance the workflow (acceptable v1 behavior per contracts §7.3).
- `on_cancel` hop routing is out of scope for v1 (FR-012).
