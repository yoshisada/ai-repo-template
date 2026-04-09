# Interface Contracts: Plugin Polish & Skill UX

**Feature**: plugin-polish-and-skill-ux
**Date**: 2026-04-09

## Overview

This feature modifies existing plugin files (JSON configs, Node.js scaffolding, Markdown skills, and JSON workflow definitions). No new exported functions are introduced. The contracts below define the exact shape of changes to existing interfaces.

## Contract 1: plugin.json — Workflow Declaration (FR-001)

**File**: `plugin-kiln/.claude-plugin/plugin.json`
**Change**: Add `workflows` array field

```json
{
  "name": "kiln",
  "version": "<current>",
  "description": "<current>",
  "author": { "name": "yoshisada" },
  "homepage": "<current>",
  "workflows": [
    "workflows/report-issue-and-sync.json"
  ]
}
```

**Contract**: The `workflows` array contains relative paths (from plugin root) to workflow JSON files. Each path MUST correspond to a file that exists in the plugin's `workflows/` directory. The format matches the pattern used by `plugin-clay/.claude-plugin/plugin.json`.

## Contract 2: init.mjs — syncWorkflows() (FR-002)

**File**: `plugin-kiln/bin/init.mjs`
**Change**: Add `syncWorkflows()` function called from `syncShared()`

```javascript
// FR-002: Sync plugin workflows to consumer project
function syncWorkflows() {
  // Read plugin.json to get declared workflows
  // For each workflow path in the "workflows" array:
  //   - source: join(PLUGIN_ROOT, workflowPath)
  //   - dest: join(PROJECT_DIR, "workflows", basename(workflowPath))
  //   - Use copyIfMissing(source, dest, description) — never overwrites existing files
}
```

**Signature**: `function syncWorkflows() -> void` (sync, no params, no return)
**Side effects**: Copies workflow JSON files from plugin to consumer `workflows/` directory. Creates `workflows/` directory if needed. Skips files that already exist unless `--force` is passed.
**Called from**: `syncShared()` (both `init` and `update` commands)

## Contract 3: init.mjs — Remove src/tests (FR-006)

**File**: `plugin-kiln/bin/init.mjs`
**Change**: Delete lines 88-96 (the `for (const dir of ["src", "tests"])` block)

No new function. Simply remove the existing code that creates `src/` and `tests/` directories with `.gitkeep` files.

## Contract 4: wheel-run Pre-flight (FR-007, FR-008)

**File**: `plugin-wheel/skills/wheel-run/SKILL.md`
**Change**: Add Step 0 before current Step 1

```markdown
## Step 0: Pre-flight Check (FR-007, FR-008)

Check that wheel infrastructure exists before attempting workflow execution.

\```bash
# FR-007: Verify wheel directory exists
if [ ! -d ".wheel" ]; then
  echo "Wheel is not set up for this repo. Run \`/wheel-init\` to configure it."
  echo ""
  echo "Would you like to run /wheel-init now? (The workflow will start after setup completes.)"
  exit 1
fi
\```

If the `.wheel/` directory does not exist, stop and display the message above.
If the user accepts, run `/wheel-init` then retry the workflow.
```

**Contract**: Pre-flight MUST run before workflow resolution. MUST NOT block when `.wheel/` exists. Message MUST mention `/wheel-init` by name.

## Contract 5: /next Command Filtering (FR-009, FR-010)

**File**: `plugin-kiln/skills/next/SKILL.md`
**Change**: Add filtering rules to Step 4 (Classification and Prioritization)

```markdown
### Command Filtering (FR-009, FR-010)

After mapping findings to commands, filter all recommendations:

**Allowed commands** (whitelist):
`/build-prd`, `/fix`, `/qa-pass`, `/create-prd`, `/create-repo`, `/init`,
`/analyze-issues`, `/report-issue`, `/ux-evaluate`, `/issue-to-prd`,
`/next`, `/todo`, `/roadmap`

**Blocked commands** (never show):
`/specify`, `/plan`, `/tasks`, `/implement`, `/audit`,
`/debug-diagnose`, `/debug-fix`

**Replacement rules**: When the natural command mapping produces a blocked command,
replace it with the appropriate high-level equivalent:
- `/specify` -> `/build-prd`
- `/plan` -> `/build-prd`
- `/tasks` -> `/build-prd`
- `/implement` -> `/build-prd`
- `/audit` -> `/build-prd`
- `/debug-diagnose` -> `/fix <description>`
- `/debug-fix` -> `/fix <description>`
```

**Contract**: The `/next` output MUST contain zero blocked commands. Every recommendation MUST map to a whitelisted command.

## Contract 6: Issue Template Backlinks (FR-011)

**File**: `plugin-kiln/templates/issue.md`
**Change**: Add `repo` and `files` fields to frontmatter

```yaml
---
title: "<title>"
type: <bug|friction|improvement|feature-request>
severity: <blocking|high|medium|low>
category: <skills|agents|hooks|templates|scaffold|workflow|other>
source: <retro|manual|github-issue|pipeline-run>
github_issue: <number or null>
repo: <repo URL or null>
files:
  - <file path>
status: open
date: YYYY-MM-DD
---
```

**Contract**: Both fields are optional. `repo` is a string URL or null. `files` is a YAML list of file path strings or omitted. Existing issues without these fields remain valid.

## Contract 7: Report-Issue Auto-Detection (FR-012)

**File**: `plugin-kiln/skills/report-issue/SKILL.md`
**Change**: Add repo/file detection to Step 1 (Validate Input)

The skill MUST instruct the workflow agent to:
1. Run `gh repo view --json url -q '.url'` to populate `repo:` field (graceful failure if `gh` unavailable)
2. Extract file paths from the issue description text using pattern matching
3. Populate both fields in the created issue frontmatter

**Contract**: If `gh` is not available or not authenticated, `repo:` is set to null (no error). File extraction uses simple path pattern matching (paths containing `/` or common extensions).

## Contract 8: Trim-Push File Classification (FR-003)

**File**: `plugin-trim/workflows/trim-push.json`
**Change**: Add `classify-files` step after `scan-components`

```json
{
  "id": "classify-files",
  "type": "command",
  "command": "<classification script>",
  "output": ".wheel/outputs/trim-classify-files.txt"
}
```

**Output format**:
```
type=component path=src/components/Button.tsx
type=component path=src/components/Card.tsx
type=page path=src/app/dashboard/page.tsx
type=page path=src/app/settings/page.tsx
```

**Classification rules** (in priority order):
1. Files in `components/`, `lib/components/`, `ui/` directories -> component
2. Files in `pages/`, `app/*/page.*`, `routes/` directories -> page
3. Files that import layout components and are referenced by router -> page
4. Default: component

## Contract 9: Trim-Push Page-Level Behavior (FR-004, FR-005)

**File**: `plugin-trim/workflows/trim-push.json` (push-to-penpot agent instruction)
**File**: `plugin-trim/skills/trim-push/SKILL.md`

**Change to push-to-penpot agent instruction**: Add classification-aware behavior:

- Read classification output from `classify-files` step
- For files classified as "component": push to "Components" page with bento grid (existing behavior)
- For files classified as "page": create individual Penpot pages named after the route, push full-screen composed frames that reference component library elements

**Change to SKILL.md**: Update step descriptions and report format to distinguish component vs page push results.

**Contract**: The push-to-penpot agent MUST read the `classify-files` output. Components go to a single "Components" page. Pages get individual Penpot pages. The report MUST show counts for both types.
