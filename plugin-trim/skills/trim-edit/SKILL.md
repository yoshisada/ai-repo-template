---
name: trim-edit
description: Edit Penpot designs via natural language. Changes are logged and stay in Penpot until pulled.
---

# trim-edit — Natural Language Design Editing

Modify Penpot designs by describing changes in natural language. The edit is applied in Penpot via MCP, logged to `.trim-changes.md`, and does NOT sync to code. The developer reviews the change in Penpot and runs `/trim-pull` when ready.

## User Input

```text
$ARGUMENTS
```

## Step 1: Validate Input (FR-001)

The user MUST provide a natural language description of the desired edit.

- If `$ARGUMENTS` is empty: print "Usage: `/trim-edit <description>`\nExample: `/trim-edit make the sidebar narrower and change the accent color to blue`" and STOP.
- Otherwise, note the edit description for the workflow.

## Step 2: Check Penpot MCP Availability

Verify that Penpot MCP tools are available by checking for `mcp__penpot-*` tools.

- If no Penpot MCP tools are available: print "Penpot MCP is required for /trim-edit. Install and configure the Penpot MCP server." and STOP.

## Step 3: Run Workflow (FR-001, FR-025)

Delegate to the trim-edit wheel workflow:

```
/wheel-run trim:trim-edit
```

The workflow executes these steps in order:
1. **resolve-trim-plugin** — finds the trim plugin install path at runtime
2. **read-design-state** — reads `.trim-components.json` and `.trim-config` for context (FR-002)
3. **apply-edit** — interprets the natural language description and applies targeted changes to the Penpot design via MCP (FR-003)
4. **log-change** — appends an entry to `.trim-changes.md` with timestamp, request, actual changes, and affected frames (FR-005, FR-006)

Pass the user's edit description to the workflow context so the `apply-edit` agent step can use it.

## Step 4: Report Results (FR-004)

After the workflow completes, read the outputs and report:

```
Design edit applied in Penpot.

  Request:    {user's description}
  Changes:    {summary from apply-edit output}
  Frames:     {affected Penpot frames}
  Logged to:  .trim-changes.md

Changes are in Penpot only — code has NOT been modified.
Run /trim-pull when you're ready to sync to code.
Run /trim-verify to visually check the changes match your expectations.
```

## Rules

- **No code modification** — edits stay in Penpot only (FR-004)
- **Always log** — every edit MUST be recorded in `.trim-changes.md` (FR-005)
- **Targeted changes** — apply only what was requested, do not regenerate the entire design (FR-003)
- **Context-aware** — read existing components and config before editing (FR-002)
- **Changelog is a decision trail** — each entry MUST include enough context to understand the change without viewing the Penpot diff (FR-006)
