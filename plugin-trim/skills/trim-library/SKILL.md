---
name: trim-library
description: Manage the bidirectional component library. Lists all tracked components with sync status, or syncs drifted components when called with 'sync'.
---

# library — Component Library Management

View and manage the bidirectional component library that tracks links between code components and Penpot components. Two modes: list (default) shows sync status of all components; sync mode auto-syncs drifted components.

## User Input

```text
$ARGUMENTS
```

- No arguments: list mode (display component status)
- `sync`: sync mode (auto-sync drifted components via wheel workflow)

## Steps

### 1. Validate Configuration

```bash
if [ ! -f .trim/config ]; then
  echo "ERROR: No .trim/config found. Run /trim:trim-init first to connect to your Penpot project."
  exit 1
fi
```

### 2. Determine Mode

Parse `$ARGUMENTS`:
- If empty or not "sync": **list mode**
- If "sync": **sync mode**

### 3a. List Mode (no args)

Read the component mapping file directly (no wheel workflow needed):

```bash
COMP_FILE=$(grep '^components_file=' .trim/config 2>/dev/null | cut -d= -f2 | tr -d ' ')
COMP_FILE=${COMP_FILE:-.trim/components.json}

if [ ! -f "$COMP_FILE" ] || [ "$(cat "$COMP_FILE")" = "[]" ]; then
  echo "No components tracked yet. Run /trim:trim-pull or /trim:trim-push to start tracking."
  exit 0
fi

jq -r '.[] | "\(.component_name)\t\(.code_path)\t\(.penpot_component_name)\t\(.last_synced)\t\(.sync_direction)"' "$COMP_FILE"
```

Display as a formatted table:

```
Component Library — {N} components tracked

  Name              Code Path                        Penpot Name          Last Synced              Direction
  ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
  Button            src/components/Button.tsx         Button               2026-04-09T12:00:00Z     pull
  Header            src/components/Header.tsx         Header               2026-04-09T11:30:00Z     push
  ...

Next: Run /trim:trim-library sync to auto-sync drifted components,
      or /trim:trim-diff for a detailed drift report.
```

### 3b. Sync Mode (`sync` arg)

Delegate to the library-sync wheel workflow:

```
/wheel:run trim:library-sync
```

The workflow executes these steps in order:
1. **read-config** — parses `.trim/config`
2. **read-mappings** — reads current `.trim/components.json`
3. **detect-framework** — detects UI framework and CSS approach
4. **check-git-timestamps** — gets last git modification time for each tracked code path
5. **resolve-trim-plugin** — resolves trim plugin install path at runtime
6. **sync-components** — determines sync direction per component (code wins if modified after last_synced, Penpot wins otherwise) and syncs via MCP
7. **update-mappings** — writes updated component mappings

After the workflow completes, report:

```
Library sync complete.

  Synced (push — code to Penpot):   {N}
  Synced (pull — Penpot to code):   {N}
  Skipped (already in sync):        {N}
  Flagged (deleted/missing):        {N}

  Updated: .trim/components.json
```

## Rules

- **Config required** — fail immediately if `.trim/config` is missing (FR-026)
- **List mode is offline** — no MCP calls needed, just read the JSON file (FR-020)
- **Sync direction by recency** — code wins if git shows modification after last_synced, Penpot wins otherwise (FR-021)
- **MCP only for sync** — all Penpot interactions during sync go through MCP tools (NFR-003)
