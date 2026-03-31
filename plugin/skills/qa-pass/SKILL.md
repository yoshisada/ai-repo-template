---
name: "qa-pass"
description: "Full visible QA walkthrough of the app using /chrome. The user watches in real time as every flow is tested. Includes functional testing + UI/UX evaluation. Requires Chrome + Claude-in-Chrome extension."
---

# QA Pass — Live Browser Walkthrough

Run a complete, visible QA pass of the application. The user watches in real time as Chrome navigates every flow, clicks every button, fills every form, and captures screenshots.

After the functional walkthrough, a UI/UX evaluator reviews the screenshots and provides design, usability, and accessibility feedback.

```text
$ARGUMENTS
```

**Requires**: Chrome browser + Claude-in-Chrome extension. If `/chrome` is not available, tell the user to install the Claude-in-Chrome extension and restart with `claude --chrome`.

## Step 1: Pre-Flight

1. **Verify /chrome is available**: Check that the Chrome browser tools are accessible. If not:
   > "/chrome is not available. To run a live QA pass, you need:
   > 1. Google Chrome or Microsoft Edge installed
   > 2. The Claude-in-Chrome extension (v1.0.36+) from the Chrome Web Store
   > 3. Start Claude Code with `claude --chrome` or run `/chrome` to enable
   >
   > Alternatively, run `/qa-final` for a headless Playwright-based QA pass (no visible browser)."

2. **Find the spec context**: Read `specs/*/spec.md`, `specs/*/plan.md`, and `docs/PRD.md` to understand what to test. If a test matrix exists at `qa-results/test-matrix.md`, use that. Otherwise, build one from the spec.

3. **Start the dev server** (if not already running):
   ```bash
   DEV_CMD=$(node -e "const p=require('./package.json'); console.log(p.scripts?.dev || p.scripts?.start || '')" 2>/dev/null)
   if [ -n "$DEV_CMD" ]; then npm run dev & else npx vite & fi
   DEV_PID=$!
   ```
   Wait for the server to be ready. Detect the port from config files.

4. **Check for credentials**: If flows require auth, check `qa-results/.env.test`. If missing, ask the user directly (they're watching — this is interactive).

5. **Prepare artifacts directory**:
   ```bash
   TIMESTAMP=$(date +%Y%m%d-%H%M%S)
   QA_DIR="qa-results/$TIMESTAMP"
   mkdir -p "$QA_DIR/screenshots" "$QA_DIR/gifs"
   ln -sfn "$TIMESTAMP" qa-results/latest
   ```

## Step 2: Live Walkthrough (Functional Testing)

Navigate the app using `/chrome` tools. For EVERY flow in the test matrix:

### Navigation Pattern

For each flow:

1. **Navigate** to the starting page:
   ```
   navigate_page → [URL]
   ```

2. **Wait** for the page to fully load:
   ```
   wait_for → page loaded / specific element visible
   ```

3. **Take a screenshot** of the initial state:
   ```
   take_screenshot → qa-results/latest/screenshots/[flow]-01-initial.png
   ```

4. **Take a snapshot** (DOM/accessibility tree) for WCAG analysis:
   ```
   take_snapshot → (stored in memory for UX evaluator)
   ```

5. **Execute the flow steps**: Click buttons, fill forms, navigate links:
   ```
   click → [element]
   fill → [input, value]
   hover → [element] (to check hover states)
   ```

6. **Screenshot each significant state change**:
   - After form submission
   - After navigation
   - After modal open/close
   - After data loads
   - Error states
   - Empty states
   - Loading states (capture DURING load, not just after)

7. **Check console for errors**:
   ```
   list_console_messages → check for JS errors/warnings
   ```

8. **Record the result**: PASS if the flow completes as expected, FAIL if not.

### What to Test (Comprehensive — EVERY Flow)

- **Every route/page** in the app — navigate to each one
- **Every form** — fill with valid data AND trigger at least one validation error
- **Every button** — click it, verify the result
- **Every navigation link** — follow it, verify destination
- **Every dropdown/modal/tab** — open and interact
- **Every CRUD operation** — create, read, update, delete
- **Every error state** — trigger 404s, empty states, network errors if possible
- **Responsive viewports** — resize browser for tablet (768px) and mobile (375px) checks

### Credential-Dependent Flows

If a flow requires login:
1. Navigate to the login page
2. If `qa-results/.env.test` has credentials, use `fill_form` to enter them
3. If the user is already logged in (Chrome shares sessions), proceed directly
4. If credentials aren't available, ask the user: "I need to log in for this flow. Can you log in manually? I'll wait."
5. Use `wait_for` to detect when login completes, then continue

### Console Error Tracking

After EVERY page navigation, run:
```
list_console_messages
```
Log any errors or warnings. JS errors during a flow mark it as a FAIL even if it visually looks correct — runtime errors are bugs.

## Step 3: Responsive Testing

After completing all flows at desktop width, resize and re-check key pages:

### Tablet (768x1024)
- Navigate to each main page
- Screenshot each
- Check layout reflow, navigation adaptation

### Mobile (375x667)
- Navigate to each main page
- Screenshot each
- Check: hamburger menu works, no horizontal scroll, touch targets adequate, text readable

## Step 4: Spawn UX Evaluator

After collecting all screenshots and snapshots, spawn the `ux-evaluator` agent:

```
Agent:
  name: "ux-evaluator"
  run_in_background: true
  prompt: |
    You are the UX evaluator. Review the QA pass artifacts and produce a UX evaluation report.

    Screenshots are at: qa-results/latest/screenshots/
    Read every screenshot in that directory.

    Spec context: [include spec summary]

    Produce your report at: qa-results/latest/UX-REPORT.md

    Follow the evaluation framework in your agent definition (4 lenses:
    heuristics, visual design, accessibility, interaction quality).
```

## Step 5: Generate Functional QA Report

While the UX evaluator runs in the background, write the functional portion of the report.

Write `qa-results/latest/QA-PASS-REPORT.md`:

```markdown
# QA Pass Report

**Date**: [timestamp]
**Feature**: [name from spec]
**Browser**: Chrome (visible via /chrome)
**Mode**: Live QA Pass
**Dev Server**: [URL]
**Flows Tested**: [N]

## Functional Results

| # | Flow | Source | Status | Screenshot | Console Errors | Notes |
|---|------|--------|--------|-----------|----------------|-------|
| 1 | [flow name] | US-NNN | PASS/FAIL | [screenshot path] | 0 | — |
| 2 | [flow name] | US-NNN | FAIL | [screenshot path] | 2 | [what failed] |

## Console Errors

| Page | Error | Severity |
|------|-------|----------|
| /dashboard | TypeError: Cannot read property 'map' of undefined | Error |
| /settings | Warning: Each child in a list should have a unique "key" prop | Warning |

## Responsive Testing

| Page | Desktop | Tablet | Mobile | Issues |
|------|---------|--------|--------|--------|
| / | PASS | PASS | FAIL | Horizontal scroll on mobile |
| /dashboard | PASS | PASS | PASS | — |

## Summary

- **Total Flows**: N
- **Passed**: N
- **Failed**: N
- **Console Errors**: N errors, M warnings
- **Responsive Issues**: N
- **Overall**: PASS / FAIL

[If FAIL: list blocking issues]
```

## Step 6: Wait for UX Report and Combine

Wait for the `ux-evaluator` agent to complete. Once `qa-results/latest/UX-REPORT.md` exists:

1. Read the UX report
2. Append a summary to the QA Pass Report:

```markdown
## UX Evaluation Summary

(Full report: qa-results/latest/UX-REPORT.md)

| Category | Score | Critical | Major | Minor | Suggestions |
|----------|-------|----------|-------|-------|-------------|
| Heuristics | N/10 | N | N | N | N |
| Visual Design | N/10 | N | N | N | N |
| Accessibility | N/10 | N | N | N | N |
| Interaction | N/10 | N | N | N | N |

### Top UX Findings
[List the top 3-5 most impactful findings from the UX report]
```

## Step 7: File Issues for Every Finding

For every failure, bug, or UX finding, run `/report-issue` to create a backlog entry. This ensures nothing gets lost and everything is actionable.

### Functional failures → file as bugs

For each flow that FAILED:

```
/report-issue QA FAIL: [flow name] (US-NNN) — [what failed]

Screenshot: qa-results/latest/screenshots/[name].png
Console errors: [list any JS errors on the page]
Expected: [what should have happened]
Actual: [what actually happened]
```

Use these classifications:
- **Type**: `bug`
- **Severity**: `blocking` if core flow, `high` if secondary flow, `medium` if edge case
- **Category**: infer from the affected area (e.g., `skills` if it's a plugin issue, `other` for app code)
- **Source**: `pipeline-run`

### Console errors → file as bugs

For each unique JS error found across pages:

```
/report-issue Console error on [page]: [error message]

Affected pages: [list all pages where this error appeared]
Screenshot: qa-results/latest/screenshots/[name].png
```

- **Type**: `bug`
- **Severity**: `high` if TypeError/ReferenceError (crash-level), `medium` if warning
- **Source**: `pipeline-run`

### UX findings → file by severity

For each finding from the UX evaluator report:

**Critical and Major UX findings** — file individually:
```
/report-issue [UX] [Category]: [finding title]

Details: [full description from UX report]
Screenshot: qa-results/latest/screenshots/[name].png
Suggested fix: [recommendation from UX evaluator]
WCAG reference: [if accessibility issue, cite the specific guideline]
```

- **Type**: `improvement` (or `bug` if it's an accessibility compliance failure)
- **Severity**: `high` for critical UX, `medium` for major UX
- **Category**: `other`
- **Source**: `pipeline-run`

**Minor and Suggestion UX findings** — batch into a single issue:
```
/report-issue [UX] Minor findings from QA pass (N items)

[List each minor finding on its own line with page and screenshot reference]
```

- **Type**: `improvement`
- **Severity**: `low`
- **Source**: `pipeline-run`

### Responsive failures → file as bugs

For each page that fails on a specific viewport:
```
/report-issue Responsive: [page] broken on [viewport] — [issue]

Screenshot (desktop): qa-results/latest/screenshots/desktop/[name].png
Screenshot ([viewport]): qa-results/latest/screenshots/[viewport]/[name].png
Issue: [horizontal scroll / overlapping elements / hidden nav / etc.]
```

- **Type**: `bug`
- **Severity**: `high` for mobile (most users), `medium` for tablet
- **Source**: `pipeline-run`

### Summary of filed issues

After filing all issues, list them:

```markdown
## Issues Filed

| # | File | Type | Severity | Summary |
|---|------|------|----------|---------|
| 1 | docs/backlog/2026-03-31-login-redirect-broken.md | bug | blocking | Login doesn't redirect to dashboard |
| 2 | docs/backlog/2026-03-31-contrast-submit-btn.md | bug | high | Submit button fails WCAG contrast |
| 3 | docs/backlog/2026-03-31-no-loading-indicator.md | improvement | medium | No loading state on data fetch |
| 4 | docs/backlog/2026-03-31-ux-minor-findings.md | improvement | low | 8 minor UX polish items |

Total: N issues filed to docs/backlog/
Run `/issue-to-prd` to bundle these into a PRD for fixing.
```

Append this table to the QA-PASS-REPORT.md as well.

## Step 8: Cleanup and Report

1. Kill the dev server if we started it:
   ```bash
   kill $DEV_PID 2>/dev/null
   ```

2. Present the results to the user:
   ```
   ## QA Pass Complete

   **Functional**: X/Y flows passing
   **Console Errors**: N
   **UX Score**: N/10 overall
   **Issues Filed**: N to docs/backlog/

   Reports:
   - Functional: qa-results/latest/QA-PASS-REPORT.md
   - UX Evaluation: qa-results/latest/UX-REPORT.md
   - Screenshots: qa-results/latest/screenshots/
   - Backlog: docs/backlog/ (N new entries)

   Next steps:
   - Run `/fix [issue]` to fix a specific bug
   - Run `/issue-to-prd` to bundle backlog items into a PRD
   - Run `/qa-pass` again after fixes to verify
   ```

## Rules

- This is a VISIBLE walkthrough — the user is watching. Move deliberately, not frantically.
- Take screenshots at EVERY significant state, not just final states. The user and UX evaluator need to see loading states, hover states, and transitions.
- Check console errors on EVERY page — JS errors are bugs even if the page looks fine.
- Test EVERY flow in the spec/test matrix. Comprehensive coverage is mandatory.
- If the user intervenes during the walkthrough (logs in manually, points something out), acknowledge it and incorporate their feedback.
- If a flow fails, screenshot the failure state and continue — don't stop the entire pass.
- The UX evaluator runs in the background on screenshots — you don't need to wait for it to continue testing.
- Always check responsive at minimum tablet and mobile viewports.
- If /chrome disconnects or Chrome crashes, report what was completed and suggest re-running.
