---
name: trim-verify
description: Visually verify rendered code matches Penpot designs. Walks user flows, screenshots each step, compares via Claude vision.
---

# verify — Visual Verification

Compare rendered code against Penpot designs by walking each tracked user flow in a headless browser, screenshotting each step, fetching the corresponding Penpot frame, and using Claude vision to identify semantic visual differences. Outputs a verification report.

## User Input

```text
$ARGUMENTS
```

Optional: a specific flow name to verify. If omitted, all flows are verified.

## Step 1: Check Prerequisites (FR-007)

1. Read `.trim/flows.json`. If not found or empty: print "No user flows defined. Run `/trim:trim-flows add <name>` to define flows before verifying." and STOP.
2. If `$ARGUMENTS` specifies a flow name: verify it exists in `.trim/flows.json`. If not found: print "Flow '{name}' not found. Run `/trim:trim-flows list` to see available flows." and STOP.
3. Ensure `.trim/verify/` directory exists for screenshot storage (FR-012).

## Step 2: Check Browser Availability (FR-008)

Check for Playwright:
```bash
npx playwright --version 2>/dev/null
```

- If Playwright is available: use headless Playwright for screenshots (default)
- If Playwright is unavailable: check for /chrome MCP tools (`mcp__claude-in-chrome__*`)
- If neither is available: print "Neither Playwright nor /chrome MCP is available. Install Playwright (`npx playwright install`) or configure /chrome MCP." and STOP.

## Step 3: Run Workflow (FR-007, FR-025)

Delegate to the verify wheel workflow:

```
/wheel:run trim:trim-verify
```

The workflow executes these steps in order:
1. **resolve-trim-plugin** — finds the trim plugin install path at runtime (FR-026)
2. **read-flows** — reads `.trim/flows.json` and validates the structure (FR-009)
3. **capture-screenshots** — walks each flow step in headless Playwright (or /chrome), screenshots each step, fetches corresponding Penpot frames via MCP (FR-008, FR-009)
4. **compare-visuals** — uses Claude vision to compare each screenshot against its Penpot counterpart, identifying layout shifts, color differences, missing/extra elements, typography mismatches, spacing issues (FR-010)
5. **write-report** — generates `.trim/verify-report.md` with per-step results, updates `last_verified` in `.trim/flows.json`, stores screenshots in `.trim/verify/` (FR-011, FR-012)

If a specific flow name was provided, pass it as context so only that flow is verified.

## Step 4: Report Results

After the workflow completes, read the outputs and report:

```
Visual verification complete.

  Flows:      {N} verified
  Steps:      {M} total
  Pass:       {P}
  Fail:       {F}

  Report:     .trim/verify-report.md
  Screenshots: .trim/verify/

{If failures, list top mismatches:}
  Mismatches:
    - {flow}/{step}: {brief description}
    - ...
```

## Rules

- **Read-only** — verification does NOT modify code or Penpot designs (FR-007)
- **Screenshots are gitignored** — all artifacts go to `.trim/verify/`, not committed (FR-012)
- **Claude vision for comparison** — use semantic visual analysis, not pixel-diffing (FR-010)
- **Per-step reporting** — every flow step gets a pass/fail result with description (FR-011)
- **Flow-driven** — verification walks tracked user flows, not individual pages (FR-009)
- **Headless default** — use Playwright headless unless /chrome is specified or Playwright unavailable (FR-008, NFR-001)
