---
name: "qa-final"
description: "Run the complete QA suite — test ALL user flows with video recording on every test, run responsive/viewport tests, export video artifacts, and generate the QA report for the PR."
---

## QA Final Pass

Run the complete visual QA suite. This is the deliverable — every flow tested, every session recorded, full report generated.

```text
$ARGUMENTS
```

### Pre-Check

1. Verify Playwright is installed: `npx playwright --version`
2. Verify `qa-results/playwright.config.ts` exists (from `/qa-setup`)
3. Verify `qa-results/test-matrix.md` exists
4. Read `qa-results/checkpoints.md` to understand what was already tested and what issues were found/fixed
5. **Credential check**: If any flows in the test matrix are marked `blocked:credentials`, check if `qa-results/.env.test` now exists with the needed values. If yes, unblock those flows. If still missing, they will be reported as `SKIPPED (no credentials)` in the final report — send one last reminder to the team lead before proceeding.

If setup is missing, run `/qa-setup` first.

### Step 1: Ensure All Tests Are Written

Read `qa-results/test-matrix.md` and verify every flow (P0, P1, P2) has a test in `qa-results/tests/`.

For any missing tests:
- Write the full test with real steps (not stubs)
- Use accessible selectors only
- Reference the user story/FR in the test name
- For auth-dependent tests: load credentials from `qa-results/.env.test` via `dotenv` or `process.env`. NEVER hardcode credentials. NEVER log, screenshot, or expose credential values in video recordings.

Ensure ALL tests have `video: 'on'` (not `retain-on-failure` — we want video of passes too for the final report).

### Step 2: Start Dev Server

```bash
DEV_CMD=$(node -e "const p=require('./package.json'); console.log(p.scripts?.dev || p.scripts?.start || '')" 2>/dev/null)
if [ -n "$DEV_CMD" ]; then
  npm run dev &
else
  npx vite &
fi
DEV_PID=$!

DEV_URL="http://localhost:5173"
for i in $(seq 1 30); do
  curl -s "$DEV_URL" > /dev/null 2>&1 && break
  sleep 1
done

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DEV_URL")
if [ "$HTTP_STATUS" != "200" ]; then
  echo "FAIL: Dev server not responding (status: $HTTP_STATUS)"
  kill $DEV_PID 2>/dev/null
  exit 1
fi
```

Use the port from `qa-results/playwright.config.ts`.

### Step 3: Run Full Suite

```bash
cd qa-results

# Run ALL tests across ALL projects (desktop + mobile)
npx playwright test --config=playwright.config.ts 2>&1 | tee final-output.log
TEST_EXIT=$?
```

### Step 4: Run Responsive/Viewport Tests

If not already covered by the mobile-chrome project in the config, add explicit viewport tests:

| Viewport | Width | Height | Check |
|----------|-------|--------|-------|
| Desktop | 1280 | 720 | Full layout, navigation |
| Tablet | 768 | 1024 | Layout reflow, touch targets |
| Mobile | 375 | 667 | Mobile nav, no horizontal scroll |

For each viewport, verify:
- No overlapping elements or horizontal scroll
- Navigation is accessible (hamburger menu works on mobile)
- Touch targets >= 44x44px
- Critical text is not truncated
- Images/media are responsive

### Step 5: Collect Artifacts

```bash
# Create timestamped output directory
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
PROJECT_QA_DIR="qa-results/$TIMESTAMP"
mkdir -p "$PROJECT_QA_DIR/videos" "$PROJECT_QA_DIR/screenshots" "$PROJECT_QA_DIR/traces"

# Copy videos with descriptive names
for video in qa-results/test-results/*/video.webm; do
  test_name=$(basename $(dirname "$video"))
  cp "$video" "$PROJECT_QA_DIR/videos/${test_name}.webm"
done

# Copy traces
for trace in qa-results/test-results/*/trace.zip; do
  test_name=$(basename $(dirname "$trace"))
  cp "$trace" "$PROJECT_QA_DIR/traces/${test_name}-trace.zip"
done

# Copy screenshots
find qa-results/test-results -name "*.png" -exec cp {} "$PROJECT_QA_DIR/screenshots/" \;

# Copy JSON report
cp qa-results/reports/results.json "$PROJECT_QA_DIR/" 2>/dev/null

# Create latest symlink
ln -sfn "$TIMESTAMP" qa-results/latest
```

### Step 6: Generate QA Report

Write `qa-results/latest/QA-REPORT.md`:

```markdown
# QA Engineer Report

**Date**: [timestamp]
**Feature**: [feature name from spec]
**Branch**: [current git branch]
**Dev Server**: [URL]
**Checkpoints Run**: [N] (see qa-results/checkpoints.md)
**Issues Found & Fixed During Pipeline**: [N]

## Test Summary

| Metric | Value |
|--------|-------|
| Total Flows Tested | N |
| Passed | N |
| Skipped (no credentials) | N |
| Failed | N |
| Skipped | N |
| Video Recordings | N |
| Screenshots | N |

## Results by User Flow

### PASS: US-001 — [flow name]
- **Video**: `videos/[test-name].webm`
- **Duration**: Xs
- **Viewports**: Desktop, Mobile

### FAIL: US-003 — [flow name]
- **Video**: `videos/[test-name].webm`
- **Screenshot**: `screenshots/[name].png`
- **Error**: [what went wrong]
- **Expected**: [expected behavior]
- **Actual**: [actual behavior]
- **Severity**: Critical / Major / Minor
- **Checkpoint History**: [reported in checkpoint N, fix attempted? resolved?]

## Responsive Testing

| Viewport | Status | Issues |
|----------|--------|--------|
| Desktop (1280x720) | PASS/FAIL | [details] |
| Tablet (768x1024) | PASS/FAIL | [details] |
| Mobile (375x667) | PASS/FAIL | [details] |

## Feedback Loop Summary

| Checkpoint | Flows Tested | Passed | Issues Sent | Issues Fixed |
|------------|-------------|--------|-------------|--------------|
| 1 | N | N | N | N |
| ... | | | | |
| Final | N | N | N | — |

## Video Artifacts

All recordings: `qa-results/latest/videos/`

| Flow | Desktop Video | Mobile Video |
|------|-------------|-------------|
| US-001 | [link] | [link] |
| ... | | |

View traces: `npx playwright show-trace qa-results/latest/traces/[name]-trace.zip`

## Overall Verdict: [PASS / FAIL]
[If FAIL: blocking issues that must be fixed before merge]
```

### Step 7: Cleanup

```bash
kill $DEV_PID 2>/dev/null
```

### Step 8: Commit and Report

1. Stage and commit `qa-results/` to the branch:
   ```bash
   git add qa-results/
   git commit -m "qa: add visual QA report and video artifacts"
   ```

2. Report to team lead via `SendMessage`:
   - Overall PASS/FAIL verdict
   - Flows tested: X passed, Y failed
   - Issues caught and fixed during checkpoints: N
   - Remaining failures with severity
   - Path to report: `qa-results/latest/QA-REPORT.md`
   - Path to videos: `qa-results/latest/videos/`

3. If ANY critical or major failures remain, recommend blocking the PR.

### Output for Auditor

The auditor (audit-pr) should include in the PR body:

```markdown
## Visual QA Results

**Verdict**: [PASS/FAIL]
**Flows**: X/Y passing | **Videos**: [N recordings](qa-results/latest/videos/)
**Report**: [QA-REPORT.md](qa-results/latest/QA-REPORT.md)
**Feedback Loop**: N issues caught during implementation, M fixed before final pass
```

### Rules

- Record video of EVERY test — pass and fail. This is the final deliverable.
- Use accessible selectors only (getByRole, getByLabel, getByText, getByTestId)
- NO page.waitForTimeout() — use auto-waiting assertions
- Every test references its US/FR
- Test desktop AND mobile at minimum
- Don't read source code — black-box testing only
- All artifacts MUST be committed to the branch
- If Playwright is not available, STOP — do not fall back to curl
