---
name: trim-flows
description: Manage user flows for verification and QA. Subcommands: add, list, sync, export-tests.
---

# trim-flows — User Flow Management

Define, list, sync, and export user flows stored in `.trim/flows.json`. Flows track the steps a user takes through the application — each step maps to a page, component, and Penpot frame. Flows feed visual verification (`/trim-verify`) and QA test generation.

## User Input

```text
$ARGUMENTS
```

## Step 1: Parse Subcommand (FR-018)

Parse `$ARGUMENTS` for one of: `add <name>`, `list`, `sync`, `export-tests`.

- If empty or unrecognized: print usage and STOP:
  ```
  Usage: /trim-flows <subcommand>

  Subcommands:
    add <name>      Define a new user flow interactively
    list            Display all tracked flows
    sync            Map flow steps to Penpot frames and code routes
    export-tests    Generate Playwright test stubs from flows
  ```

## Step 2: Execute Subcommand

### Subcommand: `add <name>` (FR-019, FR-020)

1. Extract the flow name from `$ARGUMENTS` (everything after "add ").
2. If no name provided: ask for a flow name.
3. Ask the developer to describe the flow steps. For each step, collect:
   - **action**: What happens (navigate, click, fill, select, scroll, wait)
   - **target**: CSS selector, component name, or URL path
   - **page**: The route/URL for this step
   - **component**: (optional) Component name involved
4. Continue collecting steps until the developer says they're done.
5. Read `.trim/flows.json` if it exists. If not, start with an empty array.
6. Build the new flow object following the schema (FR-019):
   ```json
   {
     "name": "<name>",
     "description": "<developer's description>",
     "steps": [
       {
         "action": "<action>",
         "target": "<target>",
         "page": "<page>",
         "component": "<component or null>",
         "penpot_frame_id": null
       }
     ],
     "last_verified": null
   }
   ```
7. Append the flow to the array and write `.trim/flows.json`.
8. Report: "Flow '{name}' added with {N} steps. Run `/trim-flows sync` to map steps to Penpot frames."

### Subcommand: `list` (FR-021)

1. Read `.trim/flows.json`. If not found: print "No flows defined. Run `/trim-flows add <name>` to create one." and STOP.
2. Display a formatted table:
   ```
   User Flows (.trim/flows.json)

   | Flow        | Steps | Last Verified       |
   |-------------|-------|---------------------|
   | login       | 5     | 2026-04-09T14:30:00 |
   | checkout    | 8     | never               |
   ```
3. Print total: "{N} flows, {M} steps total"

### Subcommand: `sync` (FR-022)

1. Read `.trim/flows.json`. If not found: print "No flows to sync." and STOP.
2. Check Penpot MCP availability. If unavailable: warn and skip Penpot frame mapping.
3. For each flow, for each step:
   a. If `penpot_frame_id` is null: attempt to map by matching the page/component to a Penpot frame via MCP.
   b. If the page corresponds to a code route: note the mapping.
4. Write updated `.trim/flows.json` with any new frame IDs.
5. Report: "Synced {N} flows. Mapped {M} steps to Penpot frames. {K} steps still unmapped."

### Subcommand: `export-tests` (FR-023, FR-024)

1. Read `.trim/flows.json`. If not found: print "No flows to export." and STOP.
2. Determine the project test directory. Check for: `tests/`, `test/`, `e2e/`, `__tests__/`. Default to `tests/e2e/`.
3. For each flow, generate a Playwright test file:
   ```typescript
   // Generated from .trim/flows.json — flow: {name}
   // FR-023: One test per flow, one step per assertion
   import { test, expect } from '@playwright/test';

   test('{flow.name}: {flow.description}', async ({ page }) => {
     // Step 1: {step.action} {step.target}
     {generated assertion code}
     // Step 2: ...
   });
   ```
4. Map each step action to Playwright code:
   - `navigate` → `await page.goto('{target}');`
   - `click` → `await page.click('{target}');`
   - `fill` → `await page.fill('{target}', '{value}');`
   - `select` → `await page.selectOption('{target}', '{value}');`
   - `scroll` → `await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));`
   - `wait` → `await page.waitForSelector('{target}');`
5. Write each test file to the test directory.
6. Report: "Generated {N} test files from {M} flows. Test directory: {path}"

## Rules

- **Human-readable JSON** — `.trim/flows.json` MUST be formatted with 2-space indentation (FR-019, NFR-003)
- **Schema compliance** — every flow MUST have name, description, steps array, last_verified (FR-019)
- **Every step has required fields** — action, target, page are required; component and penpot_frame_id are optional (FR-019)
- **Valid actions only** — action must be one of: navigate, click, fill, select, scroll, wait
- **QA-ready** — flows MUST include enough detail for Playwright test generation without manual discovery (FR-024)
