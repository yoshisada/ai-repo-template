---
name: trim-redesign
description: Full UI redesign in Penpot. Reimagines visual design while preserving information architecture and user flows.
---

# trim-redesign — Full UI Redesign

Generate a complete new Penpot design that reimagines the visual design while preserving the information architecture (pages, navigation, user flows). Reads the PRD, existing components, current design, and user flows for context. All changes are logged with rationale.

## User Input

```text
$ARGUMENTS
```

Optional context or direction for the redesign (e.g., "dark theme", "modernize the dashboard", "switch to a card-based layout").

## Step 1: Check Penpot MCP Availability

Verify that Penpot MCP tools are available.

- If unavailable: print "Penpot MCP is required for /trim-redesign. Install and configure the Penpot MCP server." and STOP.

## Step 2: Run Workflow (FR-013, FR-025)

Delegate to the trim-redesign wheel workflow:

```
/wheel-run trim:trim-redesign
```

The workflow executes these steps in order:
1. **resolve-trim-plugin** — finds the trim plugin install path at runtime (FR-026)
2. **gather-context** — reads PRD, `.trim-components.json`, `.trim-flows.json`, `.trim-config` (FR-014)
3. **read-current-design** — fetches the entire current Penpot design state via MCP (FR-014)
4. **generate-redesign** — reimagines the visual design preserving information architecture (pages, navigation, user flows), applies to Penpot via MCP (FR-015)
5. **log-changes** — appends a comprehensive redesign entry to `.trim-changes.md` with rationale (FR-016)

Pass the user's context/direction (if provided) to the workflow so `generate-redesign` can incorporate it.

## Step 3: Report Results (FR-017)

After the workflow completes, read the outputs and report:

```
UI redesign applied in Penpot.

  Direction:    {user's context or "full redesign"}
  Preserved:    Information architecture, navigation, user flows
  Redesigned:   {summary — layout, colors, typography, component styling}
  Logged to:    .trim-changes.md

Changes are in Penpot only — code has NOT been modified.
Review the redesign in Penpot, then run /trim-pull when ready to sync to code.
Run /trim-verify to check the redesign against your expectations.
```

## Rules

- **No code modification** — redesigned design stays in Penpot only (FR-017)
- **Preserve information architecture** — pages, navigation structure, and user flows MUST be maintained (FR-015)
- **Comprehensive logging** — the changelog entry MUST document what was redesigned and the rationale for each major change (FR-016)
- **Context-aware** — reads PRD, components, flows, and current design before redesigning (FR-014)
- **Reuse existing components** — the redesign should work with the existing component library where possible (NFR-005)
