# Implementer Friction Notes: Wheel Manifest Enhancement (FR-028-031)

## Plugin Install Path Discovery

The spec assumed plugins live at `.claude/plugins/*/plugin.json`. The actual structure is more complex:

- Plugins are installed to `.claude/plugins/cache/<marketplace>/<plugin-name>/<version>/`
- The authoritative source is `~/.claude/plugins/installed_plugins.json` which maps plugin keys to `installPath` values
- Each installed plugin has `.claude-plugin/plugin.json` inside its install path

**Resolution**: `workflow_discover_plugin_workflows()` reads `installed_plugins.json` and follows `installPath` values rather than globbing a flat directory. This is more robust and handles the multi-marketplace layout correctly.

## Activate.sh and Plugin Workflows

For local workflows, `activate.sh` receives a bare name (e.g., `my-workflow`) and the PostToolUse hook resolves it to `workflows/<name>.json`. For plugin workflows, the absolute path is passed instead, since the workflow file lives outside the project directory (in the plugin cache). The hook needs to handle both cases.

**Potential issue**: The activate.sh hook currently expects `workflows/<name>.json` — it may need updating to handle absolute paths. This should be verified during smoke testing.

## Local Override Precedence (FR-030)

When `<plugin>:<name>` is used but a local `workflows/<name>.json` exists, the local copy takes precedence with a notice. This matches the spec's "copy to customize" pattern.

## No Engine Changes Needed

`engine.sh` did not need modification. The engine operates on workflow JSON content (loaded via `workflow_load`), not on file paths. Since `workflow_load` already accepts any file path, plugin workflows work without engine changes.
