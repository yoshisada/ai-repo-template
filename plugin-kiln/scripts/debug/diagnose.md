# Debug Diagnose (inline helper for `kiln:fix` Step 4)

Classify the reported issue, select the appropriate debugging technique, collect diagnostics, and produce a structured diagnosis. This helper does NOT apply fixes — it only investigates.

Inputs: the issue report, spec context, and reproduction output from earlier `kiln:fix` steps.

### Step 1: Classify the Issue Type

Read the issue report and classify it into exactly one primary type:

| Type | Signals |
|------|---------|
| **visual** | "looks wrong", screenshot shows UI issue, layout broken, element missing/misaligned, responsive failure |
| **runtime** | Stack trace present, "TypeError", "ReferenceError", "Cannot read property", process crashed, exit code != 0 |
| **logic** | "wrong output", "expected X got Y", test assertion failed but no crash, data incorrect |
| **performance** | "slow", "timeout", "OOM", "heap out of memory", high latency, long load time |
| **integration** | "401", "403", "500", "ECONNREFUSED", "ETIMEDOUT", API returned unexpected response, CORS error |
| **flaky** | "sometimes passes", "works locally fails on CI", "intermittent", inconsistent results across runs |
| **build** | "tsc error", "Module not found", "SyntaxError" during build, dependency resolution failed, "ERESOLVE" |

If multiple types apply, pick the one closest to the root cause (e.g., a visual bug caused by a runtime error is a **runtime** issue).

### Step 2: Check Debug History

Read `debug-log.md` (if it exists) to see if this issue or a similar one has been debugged before. If a previous approach failed, do NOT repeat it. If a previous approach succeeded for a similar issue, try that first.

### Step 3: Select Debugging Technique

Based on the issue type, select the primary technique. If this is a retry after a failed technique, select the next one in priority order.

#### Visual / UI Bugs

**Technique 1: QA Replay + Playwright Trace**
```bash
# Check if traces exist from QA checkpoints
ls .kiln/qa/traces/*.zip 2>/dev/null

# If traces exist, extract failure details
npx playwright show-trace --json .kiln/qa/traces/[relevant-trace].zip 2>/dev/null

# If no trace, run the specific failing test with trace enabled
cd .kiln/qa && npx playwright test --config=playwright.config.ts --grep "[failing-test]" --trace on
```
Collect: trace.zip, failure screenshot, console errors, network requests at time of failure.

**Technique 2: DOM Inspection + Screenshot Comparison**
```bash
# Start dev server, navigate to the broken page
# Capture current DOM structure
# Compare against expected structure from spec
# Check computed CSS for layout-critical properties
cd .kiln/qa && npx playwright test --config=playwright.config.ts --grep "[test]" --update-snapshots
```
Collect: DOM snapshot, computed styles for broken element, viewport dimensions.

**Technique 3: LLM Vision Analysis**
- Take a screenshot of the broken state
- Read the spec to understand expected behavior
- Compare visually: what's wrong, what CSS/HTML could cause it
- Cross-reference against the source files

#### Runtime Errors / Crashes

**Technique 1: Stack Trace Analysis**
```bash
# Get the full stack trace
# Read the file:line from the top frame in project code
# Read surrounding code context (20 lines each way)
# Check the error type and message
```
Collect: full stack trace, source code at crash point, recent git changes to that file.

**Technique 2: Git Bisect (for regressions)**
```bash
# Only use if the feature worked before and now doesn't
git log --oneline -20  # find a known-good commit

# Create a test script that exits 0 on pass, 1 on fail
cat > /tmp/bisect-test.sh << 'SCRIPT'
#!/bin/bash
npm test -- --grep "[failing test]" 2>/dev/null
SCRIPT
chmod +x /tmp/bisect-test.sh

git bisect start
git bisect bad HEAD
git bisect good [known-good-hash]
git bisect run /tmp/bisect-test.sh
# Record the first bad commit
git bisect reset
```
Collect: first bad commit hash, its diff, author, and message.

**Technique 3: Instrumented Logging**
```bash
# Add targeted console.log/console.error at key points
# around the crash site to trace variable values
# Run the failing scenario and capture output
```
Collect: variable values at each instrumentation point, control flow path taken.

#### Logic Bugs (Wrong Output)

**Technique 1: Assertion-Based Debugging**
- Add assertions at each stage of the data pipeline between input and wrong output
- Run the failing case
- The first failing assertion marks where the logic diverged
```bash
# Run the specific failing test with verbose output
npm test -- --grep "[failing test]" --reporter verbose 2>&1
```
Collect: expected vs actual at each assertion, the first divergence point.

**Technique 2: Differential Testing**
```bash
# If there's a previous working version:
git stash  # save current changes
# Run the test on the known-good code
npm test -- --grep "[failing test]" 2>&1 > /tmp/good-output.txt
git stash pop
# Run on current code
npm test -- --grep "[failing test]" 2>&1 > /tmp/bad-output.txt
# Compare
diff /tmp/good-output.txt /tmp/bad-output.txt
```
Collect: diff of outputs, git diff between versions.

**Technique 3: Execution Trace Comparison**
- Log function entry/exit and key variable values for both a passing and failing case
- Diff the traces to find the first divergence point
Collect: divergence point, the branching condition that differed.

#### Performance Issues

**Technique 1: Profiling**
```bash
# Node.js CPU profile
node --prof [script]
node --prof-process isolate-*.log > profile.txt

# Or use the built-in inspector
node --inspect [script]
# Connect Chrome DevTools, record CPU profile
```
Collect: flame graph or profile output, hot functions, call counts.

**Technique 2: Database Query Analysis**
```bash
# Enable query logging in the ORM
# Run the slow operation
# Capture all SQL queries with timing
# Look for N+1 patterns, missing indexes, full scans
```
Collect: query list with timing, EXPLAIN ANALYZE output for slow queries.

**Technique 3: Memory Profiling**
```bash
# Take heap snapshots at intervals
node --inspect [script]
# In Chrome DevTools: Memory tab → Take heap snapshot
# Compare snapshots for growing objects
```
Collect: heap snapshot comparison, objects growing between snapshots.

#### Integration / API Failures

**Technique 1: Request/Response Logging**
```bash
# Capture the exact request and response
curl -v [failing-endpoint] 2>&1

# For browser-based API calls, check network tab in Playwright trace
npx playwright show-trace .kiln/qa/traces/[trace].zip
```
Collect: full request (method, URL, headers, body), full response (status, headers, body), timing.

**Technique 2: Contract Testing**
- Compare the actual API response against the expected schema (from spec or OpenAPI)
- Check: status code, response shape, field types, required fields
Collect: schema violations, expected vs actual response shape.

**Technique 3: Mock Replay**
- Record the failing API interaction
- Replay it in isolation to determine if the bug is in your code or the external service
Collect: replay results, whether failure reproduces with recorded response.

#### Flaky Tests

**Technique 1: Repeat-Run Detection**
```bash
# Run the test 10 times to confirm flakiness
for i in $(seq 1 10); do
  npm test -- --grep "[test name]" 2>&1 | tail -1
done
# Count passes vs failures
```
Collect: pass/fail ratio across 10 runs, any patterns in failures.

**Technique 2: Root Cause Classification**
- Run test alone vs in full suite (shared state?)
- Check for timing-related keywords in failure logs ("timeout", "not yet")
- Check for environment differences (CI vs local)
Collect: isolation result, timing analysis, environment comparison.

**Technique 3: Order Dependency Analysis**
```bash
# Shuffle test order to check for ordering dependencies
npx vitest run --sequence.shuffle 2>&1
# Or run the suspected dependent pair in isolation
npx vitest run [test-a] [test-b] 2>&1
npx vitest run [test-b] [test-a] 2>&1
```
Collect: which test ordering causes failure, shared state identified.

#### Build Failures

**Technique 1: Error Message Parsing**
```bash
# Run the build and capture structured output
npm run build 2>&1 | tee /tmp/build-output.txt

# For TypeScript:
npx tsc --noEmit 2>&1 | head -50

# Parse error codes, file paths, line numbers
```
Collect: error codes, file:line references, error messages.

**Technique 2: Dependency Resolution**
```bash
# Check dependency tree
npm ls --depth=3 2>&1 | grep "ERR\|WARN\|deduped\|invalid"

# Check for peer dependency issues
npm explain [problematic-package]

# Clean install to match CI
rm -rf node_modules && npm ci 2>&1
```
Collect: dependency tree issues, peer dep conflicts, lockfile drift.

**Technique 3: Cache Invalidation + Environment**
```bash
# Clear all caches
rm -rf node_modules/.cache .next dist build
# Rebuild
npm run build 2>&1

# Compare environment
node -v && npm -v
cat .nvmrc 2>/dev/null
```
Collect: whether clean build succeeds, environment version comparison.

### Step 4: Produce Diagnosis

Write the diagnosis in this format (the fix helper consumes it):

```markdown
## Diagnosis

**Issue**: [one-line summary]
**Type**: [visual/runtime/logic/performance/integration/flaky/build]
**Technique Used**: [which technique from Step 3]
**Reproducible**: [always/sometimes/once]

### Root Cause Hypothesis
[1-3 sentences explaining what you believe is wrong and why]

### Evidence
- [evidence 1 — specific data point, not just "I looked at the code"]
- [evidence 2]
- [evidence 3]

### Affected Files
- `[file:line]` — [what's wrong here]

### Suggested Fix
[Specific, actionable fix description — not "look into this" but "change X to Y in file Z"]

### Confidence
[high/medium/low] — [why this confidence level]

### Alternative Hypotheses
1. [alternative] — confidence: [level] — would need: [what evidence to confirm]
```

### Rules

- Do NOT apply fixes — only diagnose
- Do NOT modify source code during diagnosis (instrumented logging should be done in a temp copy or reverted)
- Collect concrete evidence — stack traces, screenshots, log output, not just "I think"
- Check `debug-log.md` before selecting a technique — don't repeat failed approaches
- If the issue report is too vague to diagnose, ask the reporter for more details instead of guessing
- Prefer techniques that produce binary (yes/no) evidence over subjective analysis
- Git bisect is only for regressions — don't use it on new features
- Time-box each technique to 5 minutes of active work — if you haven't found evidence by then, move to the next technique
