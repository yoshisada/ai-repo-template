---
name: qa-audit
description: "Audit test files for duplicate scenarios and redundant assertions. Outputs a prioritized report to .kiln/qa/test-audit-report.md."
---

# QA Test Audit — Detect Duplicate & Redundant Tests

Analyze all test files in the project for overlapping scenarios and redundant assertions. Produces a prioritized report with consolidation suggestions.

## User Input

```text
$ARGUMENTS
```

If arguments include `--pipeline`, run in pipeline integration mode (Step 5). Otherwise, run standalone.

### Step 1: Discover Test Files — FR-006

Find all test files in the project using common naming conventions. Exclude `node_modules/`, `.kiln/`, and other non-project directories.

```bash
echo "=== QA TEST AUDIT — Discovery ==="

# Find test files matching common patterns
TEST_FILES=()
while IFS= read -r file; do
  [ -n "$file" ] && TEST_FILES+=("$file")
done < <(find . \
  -type f \
  \( -name "*.test.*" -o -name "*.spec.*" \) \
  -not -path "*/node_modules/*" \
  -not -path "*/.kiln/*" \
  -not -path "*/.git/*" \
  -not -path "*/dist/*" \
  -not -path "*/build/*" \
  2>/dev/null | sort)

# Also find files inside tests/, __tests__/, e2e/ directories
while IFS= read -r file; do
  [ -n "$file" ] && TEST_FILES+=("$file")
done < <(find . \
  -type f \
  \( -path "*/tests/*" -o -path "*/__tests__/*" -o -path "*/e2e/*" \) \
  \( -name "*.ts" -o -name "*.js" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.py" \) \
  -not -name "*.test.*" -not -name "*.spec.*" \
  -not -path "*/node_modules/*" \
  -not -path "*/.kiln/*" \
  -not -path "*/.git/*" \
  -not -path "*/dist/*" \
  -not -path "*/build/*" \
  2>/dev/null | sort)

# Deduplicate
mapfile -t TEST_FILES < <(printf '%s\n' "${TEST_FILES[@]}" | sort -u)

echo "Found ${#TEST_FILES[@]} test files"
printf '%s\n' "${TEST_FILES[@]}"
```

If no test files are found, display:

```
No test files found in this project.

Looked for: *.test.*, *.spec.*, tests/**, __tests__/**, e2e/**
Excluded: node_modules/, .kiln/, .git/, dist/, build/

If your tests use a different naming convention, check that they follow standard patterns.
```

Then stop — do not proceed to Step 2.

### Step 2: Extract Test Metadata — FR-007, FR-008

Read each test file and extract structured metadata:

1. **Test names/descriptions** — from `test()`, `it()`, `describe()`, `test.describe()` blocks
2. **Selector patterns** — CSS selectors, `getByRole()`, `getByText()`, `getByTestId()`, `locator()` calls
3. **URL patterns** — `page.goto()`, `navigate()`, route patterns, `fetch()` / `request()` URLs
4. **Assertion targets** — `expect()` targets, `toBeVisible()`, `toHaveText()`, `toBe()`, etc.
5. **User flow steps** — sequences of actions (click, fill, navigate) that form a user journey

For each test file, build a metadata record:

```
File: path/to/file.test.ts
Tests:
  - describe: "Login page"
    - it: "should handle user login"
      selectors: ['.login-form', 'getByRole("button", {name: "Sign in"})']
      urls: ['/login', '/dashboard']
      assertions: ['toBeVisible()', 'toHaveURL("/dashboard")']
      actions: ['fill username', 'fill password', 'click sign in']
    - it: "should show error on invalid credentials"
      selectors: ['.login-form', '.error-message']
      urls: ['/login']
      assertions: ['toBeVisible()', 'toHaveText("Invalid")']
      actions: ['fill username', 'fill password', 'click sign in']
```

Read every test file — do not sample. Accuracy depends on completeness.

### Step 3: Analyze for Overlaps — FR-007, FR-008

Compare extracted metadata across all test files to detect:

#### Duplicate Scenarios (FR-007)

Two tests are duplicate scenarios when they:
- Have highly similar descriptions (e.g., "should handle user login" vs "should log in user")
- Follow the same sequence of user actions (navigate → fill → click → assert)
- Target the same URLs and selectors in the same order
- Exist in different files (cross-file duplication is the primary concern)

Score each pair on a 0-100 overlap scale:
- **80-100**: Near-duplicate — likely the same test written twice
- **60-79**: High overlap — significant shared steps, may be consolidatable
- **40-59**: Moderate overlap — shared setup but different assertions
- **Below 40**: Low overlap — ignore

#### Redundant Assertions (FR-008)

Assertions are redundant when:
- Multiple tests assert the exact same DOM state (same selector + same assertion)
- Multiple tests verify the same API response (same endpoint + same status/body check)
- The same visibility/text check appears in 3+ tests without being part of a shared setup

Group redundant assertions by what they check, listing all test files that contain them.

### Step 4: Generate Report — FR-009, FR-010

Create the `.kiln/qa/` directory if it does not exist:

```bash
mkdir -p .kiln/qa
```

Write the audit report to `.kiln/qa/test-audit-report.md` using this format:

```markdown
# QA Test Audit Report

**Date**: YYYY-MM-DD
**Files scanned**: N
**Total tests**: N
**Findings**: N overlaps, N redundant assertions

## Summary

- X duplicate scenario pairs found
- Y redundant assertion groups found
- Estimated redundancy: Z%

## Duplicate Scenarios (Priority: High)

### Finding 1
- **Test A**: `path/to/file.test.ts` — "should handle user login"
- **Test B**: `path/to/other.test.ts` — "should log in user"
- **Overlap**: Both test the same login flow with identical steps
- **Overlap Score**: 85/100
- **Suggestion**: Consolidate into a single test in `path/to/file.test.ts`

### Finding 2
...

## Redundant Assertions (Priority: Medium)

### Finding 1
- **Files**: `file1.test.ts:42`, `file2.test.ts:87`, `file3.test.ts:12`
- **Assertion**: All check `page.locator('.nav').isVisible()`
- **Suggestion**: Extract to shared helper or remove from individual tests

### Finding 2
...

## Recommendations

1. [Highest-impact consolidation first]
2. [Next consolidation]
3. ...

## Files Analyzed

| File | Tests | Involved in Findings |
|------|-------|---------------------|
| path/to/file.test.ts | 5 | 2 findings |
| path/to/other.test.ts | 3 | 1 finding |
| ... | ... | ... |
```

Prioritization rules for the report:
- **High priority**: Near-duplicate scenarios (overlap >= 80) — these waste the most CI time
- **Medium priority**: Redundant assertions across 3+ files — maintenance burden
- **Low priority**: Moderate overlaps (60-79) — note but don't urgently recommend consolidation

After writing the report, display a summary to the user:

```
## QA Test Audit Complete

Report written to: .kiln/qa/test-audit-report.md

### Quick Summary
- Files scanned: N
- Total tests: N
- Duplicate scenarios: X (High priority: Y)
- Redundant assertions: Z groups
- Estimated redundancy: W%

### Top Recommendations
1. [Most impactful suggestion]
2. [Second suggestion]
3. [Third suggestion]
```

### Step 5: Pipeline Integration (Optional) — FR-011

When invoked with `--pipeline` or when `$ARGUMENTS` contains "pipeline":

Instead of just writing the report, also route critical findings (overlap >= 80) to the implementer agent via `SendMessage`. This allows the implementer to address duplicates before test execution begins.

Message format for each critical finding:

```
QA Audit Finding — Duplicate Test Scenario (Score: 85/100)

Test A: path/to/file.test.ts — "should handle user login"
Test B: path/to/other.test.ts — "should log in user"

These tests overlap significantly. Consider consolidating before the test run.
Recommendation: Keep the test in file.test.ts, remove or merge the one in other.test.ts.
```

In pipeline mode, also append a pipeline summary section to the report:

```markdown
## Pipeline Integration

**Mode**: Pipeline
**Critical findings routed**: N
**Routed to**: implementer agent(s)
**Action required**: Review flagged duplicates before test execution
```

If no critical findings exist (no overlaps >= 80), skip routing and note:

```
QA Audit: No critical duplicates found. Test suite looks clean for this build.
```

## Rules

- Read ALL test files — do not sample or skip files based on size
- Never modify test files — this is a read-only audit
- Always create `.kiln/qa/` directory if it does not exist before writing the report
- Handle mixed frameworks gracefully — Playwright, Vitest, Jest, Mocha, pytest patterns
- Ignore `node_modules/`, `.kiln/`, `.git/`, `dist/`, `build/` directories
- If a test file cannot be parsed (binary, corrupted), skip it and note in the report
- The report MUST be valid Markdown
- Overlap scoring should be conservative — flag fewer false positives over catching every edge case
- In pipeline mode, only route findings with overlap >= 80 to implementers
