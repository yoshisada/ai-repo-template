---
name: wheel-init
description: Initialize wheel for the current repo. Creates .wheel/, workflows/, merges hook config into .claude/settings.json. Safe to run multiple times.
---

# Wheel Init — Set Up Wheel for This Repo

Run the wheel init script from the installed plugin to scaffold the workflow engine into the current project.

## User Input

```text
$ARGUMENTS
```

## Step 1: Run Init

```bash
PLUGIN_DIR="$SKILL_BASE_DIR/../.."
FORCE_FLAG=""
if [[ "$ARGUMENTS" == *"--force"* ]]; then
  FORCE_FLAG="--force"
fi
node "${PLUGIN_DIR}/bin/init.mjs" init $FORCE_FLAG
```

This creates:
- `.wheel/` — runtime state directory
- `workflows/` — workflow definitions directory
- `workflows/example.json` — example 3-step workflow
- `.gitignore` entries for `.wheel/` state files
- `.claude/settings.json` — wheel hook configuration merged in

The script is idempotent — safe to run multiple times. Existing files are not overwritten unless `--force` is passed.

## Step 2: Run Update (if re-initializing)

If the user passes `update` as the argument, run update instead:

```bash
if [[ "$ARGUMENTS" == "update" ]]; then
  node "${PLUGIN_DIR}/bin/init.mjs" update
fi
```

This re-syncs hook configuration without touching user workflows.

## Usage

```
/wheel:wheel-init              # First-time setup
/wheel:wheel-init --force      # Re-scaffold, overwrite existing files
/wheel:wheel-init update       # Re-sync hooks after plugin update
```
