---
name: "qa-checkpoint"
description: "Run a quick QA checkpoint — test recently completed flows, record video of failures, and send feedback to implementers. Fast iterative pass, not a full suite run."
---

## QA Checkpoint

Run a targeted QA pass on recently completed user flows. This is the fast feedback loop — test what's new, report issues, get out.

```text
$ARGUMENTS
```

If arguments specify which flows or implementer to test, scope to those. Otherwise, auto-detect from tasks.md.

### Step 1: Determine What to Test

```bash
# Read tasks.md to find recently completed tasks
# Compare against qa-results/checkpoints.md to find what's new since last checkpoint
```

1. Read `specs/*/tasks.md` — find all tasks marked `[X]`
2. Read `qa-results/checkpoints.md` (if it exists) — find what was already tested
3. Read `qa-results/test-matrix.md` — map completed tasks to user flows
4. The delta = flows that have backing tasks marked `[X]` but haven't been tested yet

If there's nothing new to test, report "No new flows to test since last checkpoint" and exit.

**Credential check**: If any new flows are marked `blocked:credentials` in the test matrix, check if `qa-results/.env.test` now exists and has the needed values. If yes, unblock those flows and include them. If no, skip them and note "still blocked — awaiting credentials" in the checkpoint log.

### Step 2: Start Dev Server

```bash
# Detect and start
DEV_CMD=$(node -e "const p=require('./package.json'); console.log(p.scripts?.dev || p.scripts?.start || '')" 2>/dev/null)
if [ -n "$DEV_CMD" ]; then
  npm run dev &
else
  npx vite &
fi
DEV_PID=$!

# Wait for ready (up to 30s)
DEV_URL="http://localhost:5173"
for i in $(seq 1 30); do
  curl -s "$DEV_URL" > /dev/null 2>&1 && break
  sleep 1
done

# Verify
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DEV_URL")
if [ "$HTTP_STATUS" != "200" ]; then
  echo "Dev server not responding (status: $HTTP_STATUS)"
  kill $DEV_PID 2>/dev/null
  # Report to team lead and exit
fi
```

Use the port from `qa-results/playwright.config.ts` if it exists (from `/qa-setup`).

### Step 3: Write/Update Tests for New Flows

For each untested flow:
1. If a test stub exists in `qa-results/tests/` (from `/qa-setup`), flesh it out with real steps
2. If no stub exists, write a new test file

Test rules:
- `video: 'on'` for failures, `video: 'retain-on-failure'` acceptable for checkpoints to save time
- Use accessible selectors ONLY (getByRole, getByLabel, getByText, getByTestId)
- NO `page.waitForTimeout()` — use auto-waiting assertions
- Every test name references its US/FR
- For flows requiring credentials: load from `qa-results/.env.test` via `dotenv` or `process.env`. NEVER hardcode credentials in test scripts. NEVER log or screenshot credential values.

### Step 4: Run Tests (Targeted)

```bash
cd qa-results
# Run only the new/updated tests
npx playwright test --config=playwright.config.ts --grep "US-003|US-004" 2>&1 | tee checkpoint-output.log
TEST_EXIT=$?
```

### Step 5: Send Feedback to Implementers

This is the critical step. For each result:

**For failures** — Send via `SendMessage` to the responsible implementer:

```
QA Checkpoint Feedback — FAIL: US-003 (Add to cart)

What I tested: [user flow steps]
What happened: [actual behavior]
Expected: [expected behavior]
Screenshot: qa-results/screenshots/[name].png
Video: qa-results/videos/[name].webm (if captured)

Severity: Critical / Major / Minor
Please fix and message me "fix ready for US-003" when done.
```

**For passes** — Brief confirmation to the implementer:

```
QA Checkpoint: US-004 (View cart) PASSING on desktop. Looks good.
```

### Step 6: Log Checkpoint

Append to `qa-results/checkpoints.md`:

```markdown
## Checkpoint N — [timestamp]

### Tested (new since checkpoint N-1):
- US-003: Add to cart — **FAIL** (feedback sent to impl-ui)
- US-004: View cart — **PASS**

### Cumulative: X/Y flows passing

### Blocking issues: N (sent to implementers)
```

### Step 7: Cleanup

```bash
kill $DEV_PID 2>/dev/null
```

### Step 8: Handle Re-tests

When an implementer messages "fix ready for [flow]":
1. Start dev server again
2. Run only the previously failing test
3. If passing: update checkpoints.md, confirm to implementer
4. If still failing: send updated feedback with new details
5. Kill dev server

### Output

Report to team lead:
- Checkpoint number
- Flows tested this pass
- Pass/fail counts
- Issues sent to which implementers
- Cumulative progress (X/Y total flows passing)

### Rules

- Be FAST — checkpoint should take < 5 minutes
- Only test what's new — don't re-run passing tests
- Always send feedback directly to the responsible implementer, not just the team lead
- Record video of failures (pass videos can wait for final pass)
- If dev server won't start, report immediately and exit — don't block
- Don't read source code — black-box testing only
