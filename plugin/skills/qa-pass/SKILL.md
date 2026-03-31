---
name: "qa-pass"
description: "Standalone QA pass with 4-agent team. E2E tests + live /chrome testing + UX evaluation. Findings filed as GitHub issues. Use this outside the pipeline — for pipeline use, see /qa-pipeline."
---

# QA Pass — Standalone (Files GitHub Issues)

Run a full QA pass with a 4-agent team. Findings are filed as GitHub issues for the user to address later. This is the standalone workflow — for pipeline integration where findings route to implementers, use `/qa-pipeline`.

```text
$ARGUMENTS
```

## Architecture

```
/qa-pass (you — team lead)
  │
  ├─ e2e-agent      Runs Playwright E2E suite (headless, fast, deterministic)
  │                  Sends PASS/FAIL per test → qa-reporter
  │
  ├─ chrome-agent   Uses /chrome with live data (visible, real auth, real state)
  │                  Sends PASS/FAIL per flow → qa-reporter
  │
  ├─ ux-agent       3-layer UX evaluation (axe-core + semantic + visual)
  │                  Sends findings → qa-reporter
  │
  └─ qa-reporter    MODE: issues
                    Files each finding as a GitHub issue
                    Cross-checks completeness
                    Produces QA-PASS-REPORT.md
```

**Requires**: Chrome + Claude-in-Chrome extension (for chrome-agent). If /chrome is unavailable, chrome-agent is skipped and e2e-agent + ux-agent still run.

## Pre-Flight

1. **Verify /chrome**: Check availability. If unavailable, warn that chrome-agent will be skipped.

2. **Read spec context**: `specs/*/spec.md`, `specs/*/plan.md`, `docs/PRD.md`. Build or read `qa-results/test-matrix.md`.

3. **Start dev server** (if not running):
   ```bash
   DEV_CMD=$(node -e "const p=require('./package.json'); console.log(p.scripts?.dev || p.scripts?.start || '')" 2>/dev/null)
   if [ -n "$DEV_CMD" ]; then npm run dev & else npx vite & fi
   DEV_PID=$!
   ```

4. **Check credentials**: `qa-results/.env.test`. If missing and needed, ask the user.

5. **Ensure Playwright**: `npx playwright --version || npm install -D @playwright/test && npx playwright install chromium`

6. **Prepare artifacts**:
   ```bash
   TIMESTAMP=$(date +%Y%m%d-%H%M%S)
   mkdir -p "qa-results/$TIMESTAMP/screenshots/desktop" "qa-results/$TIMESTAMP/screenshots/tablet" "qa-results/$TIMESTAMP/screenshots/mobile" "qa-results/$TIMESTAMP/snapshots"
   ln -sfn "$TIMESTAMP" qa-results/latest
   ```

## Step 1: Create Team

```
TeamCreate: "qa-pass"
```

Create 4 tasks:

```
Task 1: "E2E test suite"         → owner: e2e-agent    → depends: none
Task 2: "Live browser testing"   → owner: chrome-agent  → depends: none
Task 3: "UX evaluation"          → owner: ux-agent      → depends: none
Task 4: "Report and audit"       → owner: qa-reporter   → depends: 1, 2, 3
```

All testing agents run in parallel. Reporter waits for all three.

If /chrome is not available, skip Task 2 (chrome-agent) and remove it from Task 4's dependencies.

## Step 2: Spawn Agents

All with `run_in_background: true`, `mode: "bypassPermissions"`.

### e2e-agent prompt:

```
You are the E2E test agent. Run the Playwright test suite against the live app.

Working directory: [path]
Dev server: [URL]
Playwright config: qa-results/playwright.config.ts

Step 1: Ensure all E2E tests are written
- Read qa-results/test-matrix.md
- For every flow, verify a test exists in qa-results/tests/
- Write tests for any missing flows (use accessible selectors only)

Step 2: Run the full suite
  cd qa-results && npx playwright test --config=playwright.config.ts 2>&1

Step 3: Send results to qa-reporter
For each test result:
  SendMessage("qa-reporter", "E2E [PASS/FAIL]: [test name]
    File: [test file]
    Duration: [Xs]
    Error: [if failed — assertion message]
    Video: [path to .webm if recorded]")

When done:
  SendMessage("qa-reporter", "E2E COMPLETE — [X/Y] tests passed")
  Mark task completed.

Rules:
- Run ALL tests, not a subset.
- Use video: 'on' for failures, 'retain-on-failure' for passes.
- Accessible selectors only (getByRole, getByLabel, getByText, getByTestId).
- Do NOT file issues — qa-reporter handles that.
```

### chrome-agent prompt:

```
You are the live browser testing agent. Use /chrome to test with real data and real auth sessions.

Working directory: [path]
Dev server: [URL]
Test matrix: qa-results/test-matrix.md
Screenshot directory: qa-results/latest/screenshots/

You test things the headless E2E suite CANNOT:
- Flows requiring real authentication (shared Chrome login sessions)
- Flows with real/production data
- Third-party integrations (OAuth, payment, external APIs)
- Visual states that need a human eye (the user is watching)

For EVERY flow in the test matrix:
1. navigate_page to the URL
2. wait_for page to load
3. take_screenshot at each significant state
4. list_console_messages for JS errors
5. Execute the flow (click, fill, hover)
6. Send result to qa-reporter:
   SendMessage("qa-reporter", "CHROME [PASS/FAIL]: [flow name] (US-NNN)
     Steps: [what you did]
     Result: [what happened]
     Console errors: [count]
     Screenshots: [paths]")

Also test responsive:
- Resize to tablet (768px) and mobile (375px)
- Screenshot key pages at each viewport

When done:
  SendMessage("qa-reporter", "CHROME TESTING COMPLETE — [X/Y] flows passed")
  Mark task completed.

Rules:
- The user is watching. Move deliberately.
- If a flow needs login, use the user's existing Chrome session. If not logged in, ask the user to log in manually.
- Screenshot EVERY significant state.
- Do NOT file issues — qa-reporter handles that.
```

### ux-agent prompt:

```
You are the UX evaluator. Run a 3-layer evaluation on every page.

Working directory: [path]
Dev server: [URL]
Screenshot directory: qa-results/latest/screenshots/
Audit scripts: plugin/skills/ux-audit-scripts/

For EVERY page/route:

LAYER 1 (Programmatic — MANDATORY):
1. navigate_page to the route
2. evaluate_script with contents of plugin/skills/ux-audit-scripts/axe-inject.js
3. evaluate_script("return window.__axeResults")
4. evaluate_script with contents of plugin/skills/ux-audit-scripts/contrast-check.js
5. evaluate_script with contents of plugin/skills/ux-audit-scripts/layout-check.js
6. Send each violation to qa-reporter

LAYER 2 (Semantic):
7. take_snapshot — accessibility tree
8. Evaluate against Nielsen's 10 heuristics
9. Send findings to qa-reporter

LAYER 3 (Visual):
10. Read screenshots from qa-results/latest/screenshots/
11. Evaluate: spacing, typography, color, alignment, hierarchy, polish
12. Send findings to qa-reporter

When done:
  SendMessage("qa-reporter", "UX EVALUATION COMPLETE — [N] findings sent")
  Mark task completed.

Rules:
- Layer 1 is MANDATORY on every page.
- Be specific: exact ratios, colors, selectors.
- If evaluate_script fails (CSP), fall back to Layers 2+3.
- Do NOT file issues — qa-reporter handles that.
```

### qa-reporter prompt:

```
You are the QA reporter. MODE: issues (standalone /qa-pass).

Working directory: [path]
Test matrix: qa-results/test-matrix.md

RECEIVE findings from e2e-agent, chrome-agent, and ux-agent.

For EACH finding:
1. File a GitHub issue:
   gh issue create --label "qa-pass" --label "[severity]" --title "[QA] ..." --body "..."
2. Track the issue number

CROSS-CHECK completeness:
- Every flow in test matrix covered by e2e-agent AND chrome-agent?
- Every page evaluated by ux-agent?
- If missing, message the responsible agent

After all agents complete:
1. Produce qa-results/latest/QA-PASS-REPORT.md
2. git add qa-results/ && git commit -m "qa: QA pass report — N issues filed"
3. Mark task completed

Follow full instructions in plugin/agents/qa-reporter.md.
```

## Step 3: Monitor

You are the team lead. Track via `TaskList`. Relay user observations to agents.

## Step 4: Report

Wait for qa-reporter task to complete, then present:

```
## QA Pass Complete

**E2E Tests**: X/Y passing
**Chrome Tests**: X/Y passing
**UX Score**: N/10
**Issues Filed**: N (N critical, M major, P minor)

Report: qa-results/latest/QA-PASS-REPORT.md
Issues: gh issue list --label "qa-pass"
```

## Step 5: Cleanup

```bash
kill $DEV_PID 2>/dev/null
```
Shut down agents and `TeamDelete: "qa-pass"`.
