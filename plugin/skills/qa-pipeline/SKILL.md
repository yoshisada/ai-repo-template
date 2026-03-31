---
name: "qa-pipeline"
description: "Pipeline QA pass with 4-agent team. Same testing as /qa-pass but findings route to implementers via SendMessage for immediate fixing. Used by /build-prd, not standalone."
---

# QA Pipeline — Routes Findings to Implementers

Same 4-agent QA team as `/qa-pass` (e2e-agent, chrome-agent, ux-agent, qa-reporter) but the reporter operates in **pipeline mode** — findings go to implementers via SendMessage for immediate fixing, not just filed as issues.

```text
$ARGUMENTS
```

The arguments should include: team name, implementer names, working directory, branch, dev server URL.

## Architecture

```
/qa-pipeline (called by build-prd's QA engineer in final mode)
  │
  ├─ e2e-agent      Runs Playwright E2E suite
  ├─ chrome-agent   /chrome with live data (if available)
  ├─ ux-agent       3-layer UX evaluation
  │
  └─ qa-reporter    MODE: pipeline
                    Routes findings to implementers → waits for fixes → re-tests
                    After fix cycle: files remaining issues + produces report
```

## Difference from /qa-pass

| | /qa-pass | /qa-pipeline |
|---|---------|-------------|
| **Reporter mode** | `issues` — file and done | `pipeline` — route, wait, re-test, then file |
| **Finding destination** | GitHub issues immediately | SendMessage to implementers first |
| **Fix cycle** | None — user fixes later | Reporter routes fixes → waits → re-tests |
| **When to use** | User invokes standalone | build-prd pipeline invokes |
| **Labels** | `qa-pass` | `qa-pass` + `build-prd` |

## Pre-Flight

Same as `/qa-pass`: verify /chrome, read spec, start dev server, check credentials, ensure Playwright, prepare artifacts.

## Step 1: Create Team

```
TeamCreate: "qa-pipeline"
```

Tasks (same structure as /qa-pass):
```
Task 1: "E2E test suite"         → owner: e2e-agent    → depends: none
Task 2: "Live browser testing"   → owner: chrome-agent  → depends: none
Task 3: "UX evaluation"          → owner: ux-agent      → depends: none
Task 4: "Report, route, re-test" → owner: qa-reporter   → depends: 1, 2, 3
```

## Step 2: Spawn Agents

e2e-agent, chrome-agent, and ux-agent prompts are **identical** to `/qa-pass`. They don't know or care which mode the reporter is in — they just send findings.

### qa-reporter prompt (PIPELINE MODE):

```
You are the QA reporter. MODE: pipeline.

Working directory: [path]
Branch: [branch name]
Test matrix: qa-results/test-matrix.md
Team config: ~/.claude/teams/[team-name]/config.json

IMPLEMENTER NAMES: [list — read from parent build-prd team config or arguments]

## Phase 1: Receive and Route

As findings arrive from e2e-agent, chrome-agent, and ux-agent:

For each FAILURE or UX finding:
1. Determine which implementer owns the affected code/component
   - Read specs/*/tasks.md to map flows to implementers
   - If unclear, send to the team lead for routing
2. Send actionable feedback to the implementer:
   SendMessage("[implementer-name]", "QA Finding — [severity]: [title]
     What was tested: [flow/page]
     What failed: [description]
     Evidence: [screenshot path, axe-core output, etc.]
     Suggested fix: [specific recommendation]
     Please fix and message me 'fix ready for [flow]' when done.")
3. Track: which finding → which implementer → status (sent/fixing/fixed/unfixed)

For each PASS: no action needed (just track coverage).

## Phase 2: Wait for Fixes

After all testing agents complete and all findings are routed:

1. Message each implementer with a summary:
   SendMessage("[implementer]", "QA found [N] issues in your scope:
     - [issue 1] — [severity]
     - [issue 2] — [severity]
     Please fix all and message me 'fixes ready' when done.")

2. Wait for "fix ready" or "fixes ready" messages from implementers

3. If an implementer doesn't respond within a reasonable time, message the team lead:
   "Implementer [name] hasn't responded to QA findings. [N] issues pending."

## Phase 3: Re-Test

When an implementer messages "fix ready" or "fixes ready":

1. Determine which findings they claim to have fixed
2. Ask the appropriate testing agent to re-test:
   - For functional failures: SendMessage("e2e-agent", "Re-test: [test name/flow]")
     OR SendMessage("chrome-agent", "Re-test: [flow name]")
   - For UX/a11y findings: SendMessage("ux-agent", "Re-check: [page] for [finding]")
3. Wait for the re-test result
4. If PASS: mark finding as FIXED
5. If FAIL: send updated feedback to implementer with new evidence

Repeat until all findings are FIXED or the team lead decides to proceed with remaining issues.

## Phase 4: File Remaining Issues

After the fix cycle, any findings that are still UNFIXED:

1. File as GitHub issues:
   gh issue create --label "qa-pass" --label "build-prd" --label "[severity]" --title "[QA] ..." --body "..."
2. Note in the issue body: "This was reported to [implementer] during the pipeline but was not fixed."

## Phase 5: Produce Report

Write qa-results/latest/QA-PASS-REPORT.md with:
- All findings (fixed and unfixed)
- Fix cycle summary (what was routed, what was fixed, what remains)
- Issue links for unfixed items
- Coverage audit (same completeness checks as /qa-pass mode)

git add qa-results/ && git commit -m "qa: pipeline QA report — N issues filed, M fixed during pipeline"

Mark task completed.

## Cross-Check Completeness (same as /qa-pass mode)

- Every flow tested by e2e-agent AND chrome-agent?
- Every page evaluated by ux-agent?
- If missing, message the responsible testing agent.

Follow full instructions in plugin/agents/qa-reporter.md for report format and completeness checks.
```

## Step 3: Monitor

Same as /qa-pass — you orchestrate, agents do the work.

The key difference: the fix cycle may take longer. Implementers need time to fix issues. The team lead should track progress via `TaskList` and nudge stuck implementers.

## Step 4: Report

Wait for qa-reporter task to complete:

```
## QA Pipeline Complete

**E2E Tests**: X/Y passing
**Chrome Tests**: X/Y passing
**UX Score**: N/10
**Fixed During Pipeline**: N findings
**Issues Filed (unfixed)**: N (N critical, M major, P minor)

Report: qa-results/latest/QA-PASS-REPORT.md
```

## Step 5: Cleanup

```bash
kill $DEV_PID 2>/dev/null
```
Shut down agents and `TeamDelete: "qa-pipeline"`.
