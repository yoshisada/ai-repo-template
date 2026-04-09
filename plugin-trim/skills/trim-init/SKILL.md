---
name: trim-init
description: Initialize trim for a project. Discovers Penpot files via MCP, creates .trim-config, and scans existing components for initial mappings.
---

# trim-init — Initialize Penpot Connection

Set up trim for this project by discovering available Penpot files via MCP, selecting the target file, and creating the configuration and initial component mappings.

## User Input

```text
$ARGUMENTS
```

Optional: Penpot file ID to skip discovery (e.g., `trim-init abc123-def456`).

## Steps

### 1. Check Existing Configuration

```bash
if [ -f .trim-config ]; then
  echo "Existing .trim-config found:"
  cat .trim-config
  echo ""
  echo "Re-running will update the configuration. Proceed?"
fi
```

### 2. Discover Penpot Files via MCP

Query the Penpot MCP to list available projects and files. This replaces manual ID entry.

Use the Penpot MCP tools to:
1. List available projects
2. For each project, list its files
3. Present the user with a numbered list:

```
Available Penpot files:

  1) Project: "My App" → File: "Design System" (3 pages, 12 components)
  2) Project: "My App" → File: "Marketing Site" (5 pages, 0 components) ← blank
  3) Project: "Side Project" → File: "MVP Mockups" (2 pages, 8 components)

Which file? (number, or paste a file ID):
```

**If the user provided a file ID in `$ARGUMENTS`**, skip discovery and use that ID directly.

**If MCP discovery fails** (server not connected, auth error), fall back to asking the user for the file ID manually.

### 3. Inspect the Selected File

After the user selects a file, read its contents via MCP:

1. List all pages in the file
2. Count components/frames on each page
3. Determine if the file is **blank** (no components, only empty pages) or **populated**

Report what was found:

```
File: "Design System" (file_id: abc123)
Pages:
  - Main (14 components, 3 frames)
  - Icons (8 components)
  - Colors (0 components — palette page)

Status: Populated — 22 existing components found.
```

Or:

```
File: "New Project" (file_id: def456)
Pages:
  - Page 1 (empty)

Status: Blank file — ready for design-first workflow or /trim-push.
```

### 4. Write Configuration

Write `.trim-config` with the discovered values. **No project_id required** — file_id is sufficient for all trim operations.

```bash
cat > .trim-config << TRIMCFG
# Trim configuration — maps this repo to its Penpot file
# Run /trim-init to update

# Penpot file UUID (required)
penpot_file_id = ${FILE_ID}

# Default page to sync (omit to sync all pages)
# default_page = Main

# Component mapping file path
components_file = .trim-components.json

# Override auto-detected framework (react, vue, svelte, html)
# framework = react
TRIMCFG
```

### 5. Build Initial Component Mappings

If the Penpot file has existing components, scan them and create initial `.trim-components.json` entries:

For each Penpot component found via MCP:
- Record: `penpot_component_id`, `penpot_component_name`
- Leave `code_path` as `null` (unmapped — user runs `/trim-pull` or manually maps)
- Set `last_synced` to now
- Set `sync_direction` to `"discovered"`

If the file is blank, create an empty `[]` mapping file.

```bash
COMP_FILE=.trim-components.json
if [ ! -f "$COMP_FILE" ]; then
  echo '[]' > "$COMP_FILE"
fi
```

### 6. Report

```
Trim initialized.

  File:            {file_name} ({penpot_file_id})
  Pages:           {N pages}
  Components:      {N existing} ({N mapped}, {N unmapped})
  File Status:     {Blank | Populated}

  Config:          .trim-config
  Mappings:        .trim-components.json

Next steps:
  - File is blank?     → /trim-design to generate a design from your PRD
  - File has designs?  → /trim-pull to generate code from Penpot
  - Have code already? → /trim-push to push components to Penpot
  - Want to check?     → /trim-diff to compare code vs design
```

## Rules

- **File ID is the only required identifier** — no project_id needed
- **Always try MCP discovery first** — only fall back to manual ID entry if MCP fails
- **Scan existing components** — don't create a blank mapping when Penpot already has components
- **Idempotent** — running again updates in place, preserves user-set values (framework, default_page)
- **Report blank vs populated** — this informs the user's next step
