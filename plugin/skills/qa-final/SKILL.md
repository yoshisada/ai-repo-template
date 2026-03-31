---
name: "qa-final"
description: "Quick E2E gate — run the Playwright test suite and report green/red. No evaluation, no issue filing, just confirm tests pass."
---

# QA Final — Quick E2E Gate

Run the Playwright test suite and confirm it passes. This is a fast green/red gate, not a thorough evaluation. For the full QA pass with UX evaluation and issue filing, use `/qa-pass` or `/qa-pipeline`.

```text
$ARGUMENTS
```

## Run

```bash
# Ensure Playwright is set up
npx playwright --version 2>/dev/null || { npm install -D @playwright/test && npx playwright install chromium; }

# Run the full suite
cd qa-results 2>/dev/null && npx playwright test --config=playwright.config.ts 2>&1
EXIT_CODE=$?
```

## Report

If exit code 0:
```
QA Final: PASS — all E2E tests green
```

If exit code != 0:
```
QA Final: FAIL — [N] test failures

[List failing test names and error messages from output]

Run /qa-pass for a full evaluation with issue filing.
```

## Rules

- This is a GATE, not an evaluation. Just run tests and report pass/fail.
- No screenshots, no video, no UX evaluation, no issue filing.
- If Playwright isn't set up or no tests exist, report that and suggest `/qa-setup`.
- If tests fail, suggest `/qa-pass` for the full workup.
