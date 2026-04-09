---
name: trim-push
description: Push code components to Penpot. Analyzes code structure and styles, creates or updates Penpot components via MCP, and updates component mappings.
---

# trim-push — Push Code Components to Penpot

Analyze code components in the project, extract their visual structure and styles, and create or update matching Penpot components via MCP. Existing Penpot components are updated in place; new components are created. Runs as a wheel workflow.

## User Input

```text
$ARGUMENTS
```

Optional: component path or glob to push (e.g., `src/components/Button.tsx`). If omitted, scans all UI component directories by framework convention.

## Steps

### 1. Validate Configuration

Check that `.trim/config` exists:

```bash
if [ ! -f .trim/config ]; then
  echo "ERROR: No .trim/config found. Run /trim-init first to connect to your Penpot project."
  exit 1
fi
```

### 2. Run Workflow

Delegate to the trim-push wheel workflow:

```
/wheel-run trim:trim-push
```

The workflow executes these steps in order:
1. **read-config** — parses `.trim/config` and validates required fields
2. **detect-framework** — detects UI framework and CSS approach
3. **scan-components** — finds UI component files by framework convention (e.g., `src/components/*.tsx` for React)
4. **read-mappings** — reads current `.trim/components.json`
5. **resolve-trim-plugin** — resolves trim plugin install path at runtime
6. **push-to-penpot** — creates/updates Penpot components via MCP from code analysis
7. **update-mappings** — writes updated component mappings to `.trim/components.json`

### 3. Report Results

After the workflow completes, read the outputs and report:

```
Push complete.

  Framework:       {detected framework}
  Components Found: {N from scan}

  Pushed:
    - {component name} — {created | updated} in Penpot
    ...

  Component Mappings:
    - {N} updated
    - {N} newly created

  Updated: .trim/components.json

Next: Open Penpot to view and edit the pushed components,
      then run /trim-pull to sync visual changes back to code.
```

## Rules

- **Config required** — fail immediately if `.trim/config` is missing (FR-026)
- **Structured components** — Penpot components must be editable, not screenshots (FR-015)
- **Update, don't duplicate** — if a component already exists in Penpot (per mappings), update it (FR-013)
- **Update mappings** — all new/updated components must be reflected in `.trim/components.json` (FR-016)
- **MCP only** — all Penpot interactions go through MCP tools (NFR-003)
