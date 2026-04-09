# Interface Contracts: Trim Plugin

**Feature**: Trim — Bidirectional Design-Code Sync Plugin
**Date**: 2026-04-09
**Status**: Draft

## Plugin Manifest

### plugin.json

```json
{
  "name": "trim",
  "version": "000.000.000.000",
  "description": "Bidirectional design-code sync via Penpot MCP. Pull designs into code, push code to Penpot, detect drift, manage component libraries, and generate designs from product context."
}
```

### package.json

```json
{
  "name": "@yoshisada/trim",
  "version": "000.000.000.000",
  "description": "Bidirectional design-code sync via Penpot MCP. Pull designs into code, push code to Penpot, detect drift, manage component libraries, and generate designs from product context.",
  "author": "yoshisada",
  "license": "MIT",
  "homepage": "https://github.com/yoshisada/ai-repo-template",
  "repository": {
    "type": "git",
    "url": "https://github.com/yoshisada/ai-repo-template.git",
    "directory": "plugin-trim"
  },
  "keywords": [
    "claude-code-plugin",
    "penpot",
    "mcp",
    "design-sync",
    "code-generation"
  ],
  "files": [
    ".claude-plugin/",
    "skills/",
    "workflows/",
    "templates/"
  ]
}
```

## Skill Interfaces

All skills are SKILL.md markdown files. Each skill's frontmatter MUST include `name` and `description`.

### /trim-config

**File**: `plugin-trim/skills/trim-config/SKILL.md`
**Frontmatter**:
```yaml
name: trim-config
description: Configure the Penpot project connection. Creates or updates .trim-config with project ID, file ID, default page, and component mapping path.
```
**Input**: `$ARGUMENTS` — optional key=value pairs to set non-interactively
**Output**: Creates/updates `.trim-config` at repo root
**Behavior**:
1. Check if `.trim-config` exists
2. If exists: display current values, allow user to update individual fields
3. If not exists: prompt for penpot_project_id and penpot_file_id (required), set defaults for optional fields
4. Write `.trim-config` in key-value format
5. Validate by reading back and confirming all required fields are present
6. Initialize empty `.trim-components.json` (as `[]`) if components file doesn't exist

**Does NOT delegate to a wheel workflow** — this is a simple interactive skill.

---

### /trim-pull

**File**: `plugin-trim/skills/trim-pull/SKILL.md`
**Frontmatter**:
```yaml
name: trim-pull
description: Pull a Penpot design into framework-appropriate code. Reads design via MCP, detects project framework, generates code, and updates component mappings.
```
**Input**: `$ARGUMENTS` — optional Penpot page name or component name to pull (defaults to config's default_page)
**Output**: Generated code files in project, updated `.trim-components.json`
**Behavior**: Delegates to `/wheel-run trim:trim-pull`

---

### /trim-push

**File**: `plugin-trim/skills/trim-push/SKILL.md`
**Frontmatter**:
```yaml
name: trim-push
description: Push code components to Penpot. Analyzes code structure and styles, creates or updates Penpot components via MCP, and updates component mappings.
```
**Input**: `$ARGUMENTS` — optional component path or glob to push (defaults to scanning all UI components)
**Output**: Created/updated Penpot components, updated `.trim-components.json`
**Behavior**: Delegates to `/wheel-run trim:trim-push`

---

### /trim-diff

**File**: `plugin-trim/skills/trim-diff/SKILL.md`
**Frontmatter**:
```yaml
name: trim-diff
description: Compare Penpot designs against code and report drift. Categorizes mismatches as code-only, design-only, style-divergence, or layout-difference with actionable suggestions.
```
**Input**: `$ARGUMENTS` — optional component name to diff (defaults to all tracked components)
**Output**: Drift report printed to console and written to `.wheel/outputs/trim-diff-report.md`
**Behavior**: Delegates to `/wheel-run trim:trim-diff`

---

### /trim-library

**File**: `plugin-trim/skills/trim-library/SKILL.md`
**Frontmatter**:
```yaml
name: trim-library
description: Manage the bidirectional component library. Lists all tracked components with sync status, or syncs drifted components when called with 'sync'.
```
**Input**: `$ARGUMENTS` — empty for list mode, `sync` for sync mode
**Behavior**:
- **List mode** (no args): Read `.trim-components.json`, display table of all components with sync status. Does NOT use a wheel workflow.
- **Sync mode** (`sync` arg): Delegates to `/wheel-run trim:trim-library-sync`

---

### /trim-design

**File**: `plugin-trim/skills/trim-design/SKILL.md`
**Frontmatter**:
```yaml
name: trim-design
description: Generate an initial Penpot design from product context. Reads PRD, existing components, and project conventions to create a structured Penpot design via MCP.
```
**Input**: `$ARGUMENTS` — description of what to design, or path to a PRD file
**Output**: Created Penpot design, updated `.trim-components.json`
**Behavior**: Delegates to `/wheel-run trim:trim-design`

## Workflow Interfaces

All workflows are JSON files following the wheel engine schema. Each workflow MUST have `name`, `version`, and `steps` fields.

### trim-pull.json

**File**: `plugin-trim/workflows/trim-pull.json`
**Steps**:

| Step ID | Type | Purpose | Output |
|---------|------|---------|--------|
| `read-config` | command | Parse `.trim-config` and validate required fields | `.wheel/outputs/trim-read-config.txt` |
| `detect-framework` | command | Detect UI framework from package.json/config files | `.wheel/outputs/trim-detect-framework.txt` |
| `read-mappings` | command | Read current `.trim-components.json` | `.wheel/outputs/trim-read-mappings.txt` |
| `resolve-trim-plugin` | command | Resolve trim plugin install path from `installed_plugins.json` | `.wheel/outputs/trim-resolve-plugin.txt` |
| `pull-design` | agent | Read Penpot design via MCP, generate framework-appropriate code, update component mappings | `.wheel/outputs/trim-pull-result.md` |
| `update-mappings` | command | Write updated component mappings to `.trim-components.json` | `.wheel/outputs/trim-update-mappings.txt` |

**Step `read-config` command**:
```bash
if [ ! -f .trim-config ]; then echo 'ERROR: .trim-config not found — run /trim-config first'; exit 1; fi; while IFS='=' read -r key val; do key=$(echo "$key" | tr -d ' '); val=$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'); [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue; echo "$key=$val"; done < .trim-config
```

**Step `detect-framework` command**:
```bash
echo "## Framework Detection" && FRAMEWORK="html"; CSS_APPROACH="plain-css"; if [ -f package.json ]; then DEPS=$(cat package.json | jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' 2>/dev/null); if echo "$DEPS" | grep -q '^react$'; then FRAMEWORK="react"; elif echo "$DEPS" | grep -q '^vue$'; then FRAMEWORK="vue"; elif echo "$DEPS" | grep -q '^svelte$'; then FRAMEWORK="svelte"; fi; if echo "$DEPS" | grep -q 'tailwindcss'; then CSS_APPROACH="tailwind"; elif echo "$DEPS" | grep -q 'styled-components'; then CSS_APPROACH="styled-components"; elif echo "$DEPS" | grep -q 'css-modules'; then CSS_APPROACH="css-modules"; fi; fi; OVERRIDE=$(grep '^framework=' .trim-config 2>/dev/null | cut -d= -f2 | tr -d ' '); if [ -n "$OVERRIDE" ]; then FRAMEWORK="$OVERRIDE"; fi; echo "framework=$FRAMEWORK" && echo "css_approach=$CSS_APPROACH"
```

**Step `read-mappings` command**:
```bash
if [ -f "$(grep '^components_file=' .trim-config 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo '.trim-components.json')" ]; then cat "$(grep '^components_file=' .trim-config 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo '.trim-components.json')"; else echo '[]'; fi
```

**Step `resolve-trim-plugin` command**:
```bash
TRIM_PATH=$(jq -r '.plugins | to_entries[] | .value[] | select(.installPath | contains("/trim/")) | .installPath' ~/.claude/plugins/installed_plugins.json 2>/dev/null | head -1); if [ -z "$TRIM_PATH" ]; then TRIM_PATH=plugin-trim; fi; echo "trim_plugin_path=$TRIM_PATH"
```

**Step `pull-design` agent instruction** (summary):
Read config and framework detection outputs. Use Penpot MCP tools to read the design. Generate framework-appropriate code matching the design's layout, spacing, colors, typography, and component hierarchy. Reuse existing components from mappings. Write new component entries for any newly created components. Context from: read-config, detect-framework, read-mappings, resolve-trim-plugin.

**Step `update-mappings` command**:
```bash
COMP_FILE=$(grep '^components_file=' .trim-config 2>/dev/null | cut -d= -f2 | tr -d ' '); COMP_FILE=${COMP_FILE:-.trim-components.json}; if [ -f ".wheel/outputs/trim-pull-result.md" ]; then MAPPINGS=$(grep -A1000 '```json' ".wheel/outputs/trim-pull-result.md" | grep -B1000 '```' | grep -v '```' | head -100); if [ -n "$MAPPINGS" ] && echo "$MAPPINGS" | jq . > /dev/null 2>&1; then echo "$MAPPINGS" | jq . > "$COMP_FILE"; echo "Updated $COMP_FILE"; else echo "No valid mapping update found in pull result"; fi; else echo "No pull result to process"; fi
```

---

### trim-push.json

**File**: `plugin-trim/workflows/trim-push.json`
**Steps**:

| Step ID | Type | Purpose | Output |
|---------|------|---------|--------|
| `read-config` | command | Parse `.trim-config` and validate | `.wheel/outputs/trim-read-config.txt` |
| `detect-framework` | command | Detect UI framework | `.wheel/outputs/trim-detect-framework.txt` |
| `scan-components` | command | Find UI component files in codebase | `.wheel/outputs/trim-scan-components.txt` |
| `read-mappings` | command | Read current `.trim-components.json` | `.wheel/outputs/trim-read-mappings.txt` |
| `resolve-trim-plugin` | command | Resolve trim plugin path | `.wheel/outputs/trim-resolve-plugin.txt` |
| `push-to-penpot` | agent | Create/update Penpot components via MCP from code analysis | `.wheel/outputs/trim-push-result.md` |
| `update-mappings` | command | Write updated component mappings | `.wheel/outputs/trim-update-mappings-push.txt` |

**Step `scan-components` command**:
```bash
echo "## Component Scan" && FRAMEWORK=$(grep '^framework=' .wheel/outputs/trim-detect-framework.txt 2>/dev/null | cut -d= -f2); case "$FRAMEWORK" in react) find src/components app/components components -name '*.tsx' -o -name '*.jsx' 2>/dev/null | head -50;; vue) find src/components app/components components -name '*.vue' 2>/dev/null | head -50;; svelte) find src/components src/lib/components src/routes -name '*.svelte' 2>/dev/null | head -50;; *) find src/components components -name '*.html' 2>/dev/null | head -50;; esac; echo "---"; echo "total=$(find src/components app/components components src/lib/components 2>/dev/null | wc -l | tr -d ' ')"
```

---

### trim-diff.json

**File**: `plugin-trim/workflows/trim-diff.json`
**Steps**:

| Step ID | Type | Purpose | Output |
|---------|------|---------|--------|
| `read-config` | command | Parse `.trim-config` | `.wheel/outputs/trim-read-config.txt` |
| `read-mappings` | command | Read `.trim-components.json` | `.wheel/outputs/trim-read-mappings.txt` |
| `scan-components` | command | Find current code components | `.wheel/outputs/trim-scan-components.txt` |
| `resolve-trim-plugin` | command | Resolve trim plugin path | `.wheel/outputs/trim-resolve-plugin.txt` |
| `generate-diff` | agent | Compare Penpot state vs code, produce categorized drift report | `.wheel/outputs/trim-diff-report.md` |

**Step `generate-diff` agent** (summary):
Read mappings and scanned components from context. For each tracked component, use Penpot MCP to read the current Penpot state and compare against code. Categorize each mismatch. For untracked components in either side, flag as code-only or design-only. Generate actionable report with pull/push/manual-review suggestions. Terminal step.

---

### trim-library-sync.json

**File**: `plugin-trim/workflows/trim-library-sync.json`
**Steps**:

| Step ID | Type | Purpose | Output |
|---------|------|---------|--------|
| `read-config` | command | Parse `.trim-config` | `.wheel/outputs/trim-read-config.txt` |
| `read-mappings` | command | Read `.trim-components.json` | `.wheel/outputs/trim-read-mappings.txt` |
| `detect-framework` | command | Detect UI framework | `.wheel/outputs/trim-detect-framework.txt` |
| `check-git-timestamps` | command | Get last git modification time for each tracked code path | `.wheel/outputs/trim-git-timestamps.txt` |
| `resolve-trim-plugin` | command | Resolve trim plugin path | `.wheel/outputs/trim-resolve-plugin.txt` |
| `sync-components` | agent | For each drifted component, determine direction and sync via Penpot MCP | `.wheel/outputs/trim-library-sync-result.md` |
| `update-mappings` | command | Write updated component mappings | `.wheel/outputs/trim-update-mappings-sync.txt` |

**Step `check-git-timestamps` command**:
```bash
COMP_FILE=$(grep '^components_file=' .trim-config 2>/dev/null | cut -d= -f2 | tr -d ' '); COMP_FILE=${COMP_FILE:-.trim-components.json}; if [ -f "$COMP_FILE" ]; then jq -r '.[].code_path' "$COMP_FILE" 2>/dev/null | while read -r path; do if [ -f "$path" ]; then MTIME=$(git log -1 --format='%aI' -- "$path" 2>/dev/null || echo 'unknown'); echo "$path=$MTIME"; else echo "$path=DELETED"; fi; done; else echo 'No component mappings file'; fi
```

---

### trim-design.json

**File**: `plugin-trim/workflows/trim-design.json`
**Steps**:

| Step ID | Type | Purpose | Output |
|---------|------|---------|--------|
| `read-config` | command | Parse `.trim-config` | `.wheel/outputs/trim-read-config.txt` |
| `read-mappings` | command | Read existing component library | `.wheel/outputs/trim-read-mappings.txt` |
| `detect-framework` | command | Detect UI framework and conventions | `.wheel/outputs/trim-detect-framework.txt` |
| `read-product-context` | command | Read PRD and project conventions | `.wheel/outputs/trim-product-context.txt` |
| `resolve-trim-plugin` | command | Resolve trim plugin path | `.wheel/outputs/trim-resolve-plugin.txt` |
| `generate-design` | agent | Create Penpot design via MCP using product context and existing library | `.wheel/outputs/trim-design-result.md` |
| `update-mappings` | command | Write mappings for newly created design components | `.wheel/outputs/trim-update-mappings-design.txt` |

**Step `read-product-context` command**:
```bash
echo "## Product Context" && if [ -f docs/PRD.md ]; then echo "--- PRD ---" && head -100 docs/PRD.md; fi && for prd in docs/features/*/PRD.md; do [ -f "$prd" ] || break; echo "--- $(basename $(dirname $prd)) ---" && head -50 "$prd"; done && echo "--- Conventions ---" && if [ -f .trim-config ]; then cat .trim-config; fi && echo "--- Existing Components ---" && COMP_FILE=$(grep '^components_file=' .trim-config 2>/dev/null | cut -d= -f2 | tr -d ' '); COMP_FILE=${COMP_FILE:-.trim-components.json}; if [ -f "$COMP_FILE" ]; then jq -r '.[].component_name' "$COMP_FILE" 2>/dev/null; else echo '(none)'; fi
```

## Template Interfaces

### trim-config.tpl

**File**: `plugin-trim/templates/trim-config.tpl`
**Content**: Default `.trim-config` with placeholder values and comments explaining each field.

### trim-components.tpl

**File**: `plugin-trim/templates/trim-components.tpl`
**Content**: Empty JSON array `[]` — the initial state of `.trim-components.json`.

## Common Patterns

### Config Reading (shared across all workflows)

Every workflow starts with a `read-config` command step that:
1. Checks `.trim-config` exists (errors if not)
2. Parses key-value pairs, skipping comments and blank lines
3. Writes parsed values to `.wheel/outputs/trim-read-config.txt`

### Plugin Resolution (shared across all workflows)

Every workflow includes a `resolve-trim-plugin` command step that:
1. Scans `~/.claude/plugins/installed_plugins.json` for a trim plugin path
2. Falls back to `plugin-trim/` if not found
3. Writes resolved path to `.wheel/outputs/trim-resolve-plugin.txt`

### Mapping Updates (shared across pull, push, design, library-sync)

Workflows that create or modify component links include a final `update-mappings` command step that:
1. Reads the agent step's output for a JSON mapping block
2. Validates it with `jq`
3. Writes to the components file specified in `.trim-config`
