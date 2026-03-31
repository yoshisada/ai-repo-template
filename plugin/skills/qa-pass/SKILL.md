---
name: "qa-pass"
description: "Full visible QA walkthrough using /chrome with a 3-agent team: qa-agent (functional testing), ux-agent (3-layer UX evaluation), and qa-reporter (files GitHub issues, audits completeness). Requires Chrome + Claude-in-Chrome extension."
---

# QA Pass — Live Browser Walkthrough with Agent Team

Run a complete, visible QA pass using a coordinated 3-agent team. The user watches in real time as Chrome navigates every flow. Findings are filed as GitHub issues automatically.

```text
$ARGUMENTS
```

**Requires**: Chrome + Claude-in-Chrome extension. If `/chrome` is not available, tell the user to install it and restart with `claude --chrome`.

## Architecture

```
/qa-pass (you — team lead)
  │
  ├─ qa-agent     Walks through every flow in visible Chrome
  │               Sends PASS/FAIL per flow → qa-reporter
  │
  ├─ ux-agent     3-layer UX evaluation (axe-core + semantic + visual)
  │               Sends findings → qa-reporter
  │
  └─ qa-reporter  Files GitHub issues, cross-checks completeness,
                  produces final QA-PASS-REPORT.md
```

## Pre-Flight

1. **Verify /chrome is available.** If not:
   > "/chrome is not available. Install the Claude-in-Chrome extension and restart with `claude --chrome`."

2. **Read spec context**: `specs/*/spec.md`, `specs/*/plan.md`, `docs/PRD.md`. If a test matrix exists at `qa-results/test-matrix.md`, use it. Otherwise, build one from the spec.

3. **Start the dev server** (if not already running):
   ```bash
   DEV_CMD=$(node -e "const p=require('./package.json'); console.log(p.scripts?.dev || p.scripts?.start || '')" 2>/dev/null)
   if [ -n "$DEV_CMD" ]; then npm run dev & else npx vite & fi
   DEV_PID=$!
   ```
   Wait for server. Detect port from config.

4. **Check for credentials**: If flows require auth, check `qa-results/.env.test`. If missing, ask the user directly (they're watching).

5. **Prepare artifacts directory**:
   ```bash
   TIMESTAMP=$(date +%Y%m%d-%H%M%S)
   QA_DIR="qa-results/$TIMESTAMP"
   mkdir -p "$QA_DIR/screenshots/desktop" "$QA_DIR/screenshots/tablet" "$QA_DIR/screenshots/mobile" "$QA_DIR/snapshots"
   ln -sfn "$TIMESTAMP" qa-results/latest
   ```

## Step 1: Create the QA Team

```
TeamCreate: "qa-pass"
```

Create 3 tasks:

```
Task 1: "Functional QA walkthrough"
  owner: qa-agent
  depends: none

Task 2: "UX evaluation (3-layer)"
  owner: ux-agent
  depends: none  (runs in parallel — uses /chrome on the same live app)

Task 3: "Report and audit completeness"
  owner: qa-reporter
  depends: Task 1, Task 2
```

## Step 2: Spawn Agents

Spawn all 3 agents with `run_in_background: true` and `mode: "bypassPermissions"`.

### qa-agent prompt:

```
You are the functional QA tester. Use /chrome to walk through every user flow in visible Chrome.

Working directory: [path]
Dev server: [URL]
Test matrix: qa-results/test-matrix.md (or build from specs/*/spec.md)
Screenshot directory: qa-results/latest/screenshots/

For EVERY flow in the test matrix:
1. navigate_page to the starting URL
2. wait_for page to load
3. take_screenshot to qa-results/latest/screenshots/desktop/[flow]-initial.png
4. Execute the flow (click, fill, hover, etc.)
5. take_screenshot at each significant state change
6. list_console_messages — check for JS errors
7. Send result to qa-reporter:
   SendMessage("qa-reporter", "FUNCTIONAL [PASS/FAIL]: [flow name] (US-NNN)
     Steps: [what you did]
     Result: [what happened]
     Expected: [what should happen]
     Console errors: [count]
     Screenshots: [paths]")

After all desktop flows, test responsive:
- Resize to tablet (768px) and re-check key pages
- Resize to mobile (375px) and re-check key pages
- Send responsive results to qa-reporter

When done with ALL flows:
SendMessage("qa-reporter", "FUNCTIONAL TESTING COMPLETE — [X/Y] flows passed")
SendMessage("ux-agent", "Screenshots ready at qa-results/latest/screenshots/")
Mark task completed via TaskUpdate.

Rules:
- Test EVERY flow. Comprehensive coverage is mandatory.
- Send results to qa-reporter AS YOU GO — don't batch at the end.
- If a flow fails, screenshot the failure and continue — don't stop.
- Check console errors on EVERY page.
- Do NOT file issues — qa-reporter handles that.
```

### ux-agent prompt:

```
You are the UX evaluator. Run a 3-layer evaluation on every page of the live app.

Working directory: [path]
Dev server: [URL]
Screenshot directory: qa-results/latest/screenshots/
Audit scripts: plugin/skills/ux-audit-scripts/

You have /chrome access. For EVERY page/route:

LAYER 1 (Programmatic — run FIRST):
1. navigate_page to the route
2. Read plugin/skills/ux-audit-scripts/axe-inject.js and pass to evaluate_script
3. Retrieve results: evaluate_script("return window.__axeResults")
4. Read plugin/skills/ux-audit-scripts/contrast-check.js and pass to evaluate_script
5. Read plugin/skills/ux-audit-scripts/layout-check.js and pass to evaluate_script
6. Send each violation/failure to qa-reporter with evidence

LAYER 2 (Semantic):
7. take_snapshot — read the accessibility tree
8. Evaluate against Nielsen's 10 heuristics
9. Send each finding to qa-reporter

LAYER 3 (Visual):
10. Read screenshots from qa-results/latest/screenshots/
11. Evaluate: spacing, typography, color, alignment, hierarchy, polish
12. Send each finding to qa-reporter

When done with ALL pages:
SendMessage("qa-reporter", "UX EVALUATION COMPLETE — [N] total findings sent")
Mark task completed via TaskUpdate.

Rules:
- Layer 1 is MANDATORY on every page. No skipping.
- Send findings to qa-reporter, not the user.
- Be specific: include exact ratios, colors, element selectors.
- If evaluate_script fails (CSP), fall back to Layers 2+3 and note it.
- Do NOT file issues — qa-reporter handles that.
```

### qa-reporter prompt:

```
You are the QA reporter and completeness auditor.

Working directory: [path]
Test matrix: qa-results/test-matrix.md
Pages/routes: [from plan.md]

Your job:
1. Receive all findings from qa-agent and ux-agent via SendMessage
2. File each finding as a GitHub issue:
   gh issue create --label "qa-pass" --title "[QA] ..." --body "..."
3. Cross-check completeness:
   - Did qa-agent test every flow in the test matrix?
   - Did ux-agent evaluate every page?
   - If something is missing, message the responsible agent
4. After both agents complete, produce qa-results/latest/QA-PASS-REPORT.md
5. Commit qa-results/ and mark task completed

{If running inside build-prd pipeline, also add --label "build-prd" to every issue.}

Follow the full instructions in your agent definition (plugin/agents/qa-reporter.md).
```

## Step 3: Monitor

You are the team lead. Messages arrive automatically.

- If an agent reports being stuck, provide guidance via `SendMessage`
- If an agent can't access /chrome, help troubleshoot
- Track progress via `TaskList`
- The user is watching — if they point something out, relay it to the relevant agent

## Step 4: Wait for Report

The qa-reporter produces the final report after both agents complete. Wait for its task to be marked completed, then:

1. Read `qa-results/latest/QA-PASS-REPORT.md`
2. Present the summary to the user:

```
## QA Pass Complete

**Functional**: X/Y flows passing
**UX Score**: N/10
**Issues Filed**: N (N critical, M major, P minor)
**Coverage**: All flows tested / All pages evaluated

Reports:
- qa-results/latest/QA-PASS-REPORT.md
- GitHub issues: [link to qa-pass label filter]

Next steps:
- Run /fix [issue] to fix specific bugs
- Run /qa-pass again after fixes to verify
```

## Step 5: Cleanup

```bash
kill $DEV_PID 2>/dev/null
```

Shut down agents:
```
SendMessage("qa-agent", { type: "shutdown_request" })
SendMessage("ux-agent", { type: "shutdown_request" })
SendMessage("qa-reporter", { type: "shutdown_request" })
TeamDelete: "qa-pass"
```

## Rules

- This is a VISIBLE walkthrough — the user is watching. Move deliberately.
- All 3 agents run in parallel where possible (qa-agent and ux-agent can both use /chrome on the same app).
- The qa-reporter is the ONLY agent that files GitHub issues. qa-agent and ux-agent send findings to the reporter.
- The qa-reporter audits completeness — it catches missed flows and pages.
- If /chrome disconnects, report what was completed and suggest re-running.
- The team lead (you) does NOT test or evaluate — you orchestrate.
