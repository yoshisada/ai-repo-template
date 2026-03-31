---
name: "debug"
description: "Fix a bug without creating a new PRD or spec. Describe the issue (or pass a GitHub issue number) and the debugger will diagnose, fix, and verify it using the existing spec as context."
---

# Debug

Fix a bug in an already-implemented feature. No new PRD, no new spec, no speckit ceremony — just find the bug and fix it.

```text
$ARGUMENTS
```

## Usage

```
/debug The login button doesn't redirect to the dashboard after successful auth
/debug #42
/debug https://github.com/owner/repo/issues/42
/debug Tests are failing with "Cannot read property 'map' of undefined" in UserList component
/debug The app is slow when loading the settings page — takes 8+ seconds
/debug Build fails with TS2322 in src/components/Header.tsx
```

## Step 1: Parse the Issue

### If a GitHub issue number or URL was provided:
```bash
# Fetch the issue details
gh issue view [number] --json title,body,labels,comments
```
Extract: title, description, reproduction steps, labels (bug/enhancement), and any discussion.

### If a text description was provided:
Use it directly as the issue description.

### If no arguments:
Ask the user: "What's the bug? Include the error message, what you expected, and what actually happened."

## Step 2: Find the Spec Context

The bug is in something that was already built. Find the spec that covers it:

```bash
# Search specs for related FRs or user stories
grep -r "[keyword from issue]" specs/ 2>/dev/null
# Check which feature spec covers this area
ls specs/*/spec.md
```

Read the relevant `spec.md`, `plan.md`, and `contracts/interfaces.md` to understand what the code SHOULD do. This is your oracle — the gap between spec and reality is the bug.

**If no spec exists**: That's fine. Work from the user's description and the code itself. Not everything goes through speckit.

## Step 3: Reproduce the Issue

Before diagnosing, confirm the bug is real and reproducible:

### For test failures:
```bash
npm test -- --grep "[relevant test]" 2>&1
```

### For runtime errors:
```bash
# Run the app and trigger the bug
npm run dev &
# Then reproduce the steps from the issue
```

### For visual/UI bugs:
```bash
# Check if QA infrastructure exists
ls qa-results/playwright.config.ts 2>/dev/null
# If not, set it up
# Then run a targeted Playwright test to reproduce
```

### For build failures:
```bash
npm run build 2>&1
```

If the bug does NOT reproduce, tell the user: "I can't reproduce this. Here's what I tried: [steps]. Can you provide more details?"

## Step 4: Run the Debug Loop

Run `/debug-diagnose` with:
- The issue description
- The spec context (what SHOULD work)
- The reproduction result (how it actually fails)

Then run `/debug-fix` with the diagnosis.

The debug loop runs: diagnose → fix → verify → (repeat if needed, max 9 attempts).

See the `debugger` agent definition for full loop details.

## Step 5: Verify and Commit

Once the fix passes verification:

1. **Run the full test suite** to check for regressions:
```bash
npm test 2>&1
```

2. **For visual bugs**: Run the relevant QA test to confirm:
```bash
cd qa-results && npx playwright test --config=playwright.config.ts --grep "[test]" 2>&1
```

3. **Commit the fix**:
```bash
git add [changed files]
git commit -m "fix: [concise description]

Root cause: [one-line explanation]
Resolves: [issue number if provided]
Verified by: [test/command that confirms]"
```

4. **Report to the user**:
```
## Bug Fixed

**Issue**: [description]
**Root cause**: [what was wrong]
**Fix**: [what was changed, with file:line references]
**Verified by**: [test output or visual confirmation]
**Commit**: [hash]

### Debug summary
- Technique used: [technique name]
- Attempts: [N]
- Files changed: [list]
```

## Step 6: Handle Escalation

If the debug loop exhausts all strategies (9 attempts), present the user with everything collected:

```
## Debug Report — Could Not Fix Automatically

**Issue**: [description]
**Spec**: [which spec covers this, or "none"]

### What I Found
[Root cause hypothesis with evidence]

### What I Tried
1. [approach 1] — failed because [reason]
2. [approach 2] — failed because [reason]
3. [approach 3] — failed because [reason]

### Diagnostics
- [artifact paths]

### My Recommendation
[What the user should try manually, or whether this needs a spec update]
```

## Visual Bug Shortcut

If the issue is clearly visual/UI (mentions layout, styling, "looks wrong", responsive, etc.), and Playwright is set up:

1. Skip straight to running `/qa-checkpoint` on the affected flow
2. Use the Playwright trace and screenshots as diagnostic input
3. Fix the CSS/HTML/component issue
4. Re-run the QA test to verify

This is faster than the general debug loop for visual issues.

## Rules

- Do NOT require a new PRD or spec — the whole point is to fix bugs without ceremony
- DO read existing specs for context — they tell you what the code should do
- The speckit hooks may block src/ edits — existing specs should satisfy the gates. If not, check that spec artifacts exist for the feature.
- Log everything in `debug-log.md` — it helps the retrospective and future debugging
- If the bug reveals a gap in the original spec (the feature was never supposed to handle this case), tell the user. They may want to update the spec before fixing.
- If the fix is trivial (typo, obvious one-line fix), just fix it directly without the full diagnose→fix loop. Use judgment.
- Always run the full test suite after fixing to catch regressions
