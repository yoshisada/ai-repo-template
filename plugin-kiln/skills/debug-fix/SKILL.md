---
name: "debug-fix"
description: "Apply a targeted fix based on a diagnosis, then verify it passes. Reverts on failure. Tracks every attempt in debug-log.md to avoid repeating failed approaches."
---

## Debug Fix

Apply a fix based on the diagnosis from `/debug-diagnose`, then verify it works. If verification fails, revert and report.

```text
$ARGUMENTS
```

The arguments should contain the diagnosis output from `/debug-diagnose`. If no arguments, check the conversation for the most recent diagnosis.

### Step 1: Pre-Fix Safety

Before touching any code:

1. **Check debug history**: Read `debug-log.md` — has this exact approach been tried before? If yes, STOP and try a different angle.

2. **Create a save point**:
```bash
# Stash or note the current state so we can revert cleanly
git stash push -m "debug-savepoint-$(date +%s)" --include-untracked 2>/dev/null
git stash pop  # immediately restore — we just want the stash as a safety net
# Or simply note the current HEAD
SAVE_POINT=$(git rev-parse HEAD)
echo "Save point: $SAVE_POINT"
```

3. **Verify the issue reproduces NOW** (not just "it failed earlier"):
```bash
# Run the specific failing test/command from the diagnosis
# If it now passes without any fix, the issue may have been resolved by another agent
```
If the issue no longer reproduces, report "Issue no longer reproduces — may have been fixed by another agent" and exit.

### Step 2: Apply the Fix

Based on the diagnosis, apply the smallest possible fix. Rules:

- **One logical change per attempt** — don't bundle multiple hypotheses into one fix
- **Match the diagnosis** — fix what the diagnosis identified, not something adjacent
- **Smallest diff** — prefer changing 1-3 lines over refactoring. Debugging is not the time to clean up code.
- **No symptom masking** — wrapping in try/catch, adding `|| null`, or suppressing errors is NOT a fix unless the diagnosis specifically calls for error handling
- **Contract compliance** — if the fix changes a function signature, check `specs/*/contracts/interfaces.md`. If it conflicts, flag to the team lead before proceeding.

#### Fix Patterns by Issue Type

**Visual/UI bugs:**
- CSS fix: adjust the specific property identified in diagnosis
- Layout fix: correct flexbox/grid alignment, z-index, overflow
- Missing element: check if component is rendered, condition is met
- Responsive: add/fix media query or container query

**Runtime errors:**
- Null/undefined: add proper null check at the identified crash point, or fix the upstream code that should have provided the value
- Type error: fix the type mismatch (not just `as any`)
- Import error: fix the import path or add the missing export

**Logic bugs:**
- Wrong condition: fix the boolean logic or comparison
- Off-by-one: fix the boundary condition
- State management: fix the state update that produces wrong values
- Data flow: fix the transformation step identified by assertions

**Performance:**
- N+1 query: batch the queries or add eager loading
- Missing index: add database index
- Unnecessary work: memoize, cache, or remove redundant computation
- Memory leak: close event listener, clear interval, remove reference

**Integration/API:**
- Auth: fix token/header handling
- Schema mismatch: update request/response handling to match actual API
- Timeout: adjust timeout value or add retry logic (with backoff)
- CORS: fix server-side CORS config, not client-side workarounds

**Flaky tests:**
- Timing: replace `waitForTimeout` with proper `waitFor`/assertion-based waits
- Shared state: isolate test state (fresh fixtures, unique IDs)
- Order dependency: remove shared state or enforce ordering

**Build failures:**
- Type error: fix the type (not suppress with `@ts-ignore`)
- Missing dep: add to package.json
- Config: fix the build config
- Lockfile: regenerate with `npm install`

### Step 3: Verify the Fix

Run verification appropriate to the issue type:

#### Verification by Type

**Visual (MANDATORY — full E2E suite, not just the fixed flow):**
```bash
# First: verify the specific fix
cd .kiln/qa && npx playwright test --config=playwright.config.ts --grep "[test-name]" 2>&1

# Then: run the FULL E2E suite to catch regressions (NON-NEGOTIABLE for UI fixes)
cd .kiln/qa && npx playwright test --config=playwright.config.ts 2>&1
```
PASS if: the specific test passes on desktop AND mobile viewports, AND the full E2E suite has no new failures compared to before the fix. A fix that breaks another flow is NOT a fix — revert and try a different approach.

**Runtime:**
```bash
# Re-run the failing test
npm test -- --grep "[test-name]" 2>&1
```
PASS if: test passes with exit code 0.

**Logic:**
```bash
# Re-run the failing test AND related tests
npm test -- --grep "[test-pattern]" 2>&1
```
PASS if: all assertions pass, output matches expected values.

**Performance:**
```bash
# Re-run the performance measurement
# Compare against the threshold from the diagnosis
```
PASS if: metric is below the acceptable threshold.

**Integration:**
```bash
# Re-run the API test or curl command
curl -v [endpoint] 2>&1
# OR re-run integration test
npm test -- --grep "[integration-test]" 2>&1
```
PASS if: correct status code and response shape.

**Flaky:**
```bash
# Run the test 10 times — ALL must pass
for i in $(seq 1 10); do
  npm test -- --grep "[test-name]" 2>&1 | tail -1
done
```
PASS if: 10/10 runs pass.

**Build:**
```bash
npm run build 2>&1
```
PASS if: build succeeds with exit code 0.

#### Regression Check

After the specific fix passes, run a broader check to make sure nothing else broke:

```bash
# Run the full unit/integration test suite
npm test 2>&1
```

**For UI fixes — E2E regression check is MANDATORY (in addition to unit tests):**
```bash
# Run the full Playwright E2E suite
cd .kiln/qa && npx playwright test --config=playwright.config.ts 2>&1
```
This catches visual regressions (layout shifts, broken navigation, CSS cascade issues) that unit tests cannot detect. UI fixes that pass unit tests but break other flows in the browser are NOT acceptable.

If the full suite has new failures that didn't exist before your fix, your fix introduced a regression. Revert and try a different approach.

### Step 4: Handle Results

#### On PASS:

1. **Log success** — append to `debug-log.md`:
```markdown
### Attempt N — [technique]: [approach]
**Action**: [what was changed, file:line]
**Result**: PASS
**Verification**: [test output summary]
**Regression check**: [full suite result]
**Commit**: [will be committed]
```

2. **Commit the fix**:
```bash
git add [changed files]
git commit -m "fix: [concise description of what was fixed and why]

Root cause: [one-line root cause]
Diagnosed via: [technique used]
Verified by: [test/command that confirms fix]"
```

3. **Report success** to the debugger agent (it will notify the reporter)

#### On FAIL:

1. **Revert immediately**:
```bash
git checkout -- [changed files]
# Or if files were added:
git clean -fd [new files]
```

2. **Log failure** — append to `debug-log.md`:
```markdown
### Attempt N — [technique]: [approach]
**Action**: [what was changed]
**Result**: FAIL
**Why it failed**: [specific reason — what the verification showed]
**Reverted**: yes
```

3. **Report failure** to the debugger agent with:
   - What was tried
   - Why it didn't work (specific verification output)
   - What this rules out for the root cause
   - Suggestion for next approach (if any)

### Step 5: Update Debug Log

Ensure `debug-log.md` captures everything for future reference. If the file doesn't exist, create it:

```markdown
# Debug Log

This file tracks all debugging attempts across the pipeline. It prevents repeating
failed approaches and creates an audit trail for the retrospective.

---
```

Every attempt (pass or fail) gets logged. This is the historical memory that the debugger agent reads before each attempt.

### Rules

- ALWAYS verify — never assume a fix works
- ALWAYS revert failed fixes — don't stack broken changes
- ALWAYS log every attempt — even successful ones
- NEVER try the same approach twice (check debug-log.md first)
- NEVER mask symptoms (try/catch, `|| null`, `@ts-ignore`, `as any`)
- NEVER refactor while debugging — smallest possible fix only
- NEVER change tests to match buggy behavior — fix the code, not the test
- NEVER skip the regression check — a fix that breaks something else is not a fix
- If the fix requires changing a contract (interfaces.md), STOP and flag to team lead
- If the fix is in a dependency (not your code), document as a blocker — don't fork/patch deps
- Time-box each fix attempt to 10 minutes — if you can't fix it in 10 minutes with a clear diagnosis, the diagnosis may be wrong
