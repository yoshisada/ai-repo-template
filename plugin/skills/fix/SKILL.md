---
name: "fix"
description: "Fix a bug without creating a new PRD or spec. Describe the issue (or pass a GitHub issue number) and the debugger will diagnose, fix, and verify it using the existing spec as context."
---

# Fix

Fix a bug in an already-implemented feature. No new PRD, no new spec, no speckit ceremony — just find the bug and fix it.

```text
$ARGUMENTS
```

## Usage

```
/fix The login button doesn't redirect to the dashboard after successful auth
/fix #42
/fix https://github.com/owner/repo/issues/42
/fix Tests are failing with "Cannot read property 'map' of undefined" in UserList component
/fix The app is slow when loading the settings page — takes 8+ seconds
/fix Build fails with TS2322 in src/components/Header.tsx
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

## Step 2b: Check for Credentials / Real Account Data

Before attempting to reproduce, check if the issue involves authenticated flows, real user data, or external services that require credentials.

### Detection — ask the user if ANY of these are true:
- The bug is behind a login wall or requires authentication
- The issue involves a specific user account, role, or permission level
- The bug only happens with real/production data (not mock data)
- An external API, database, or third-party service is involved
- The issue mentions OAuth, SSO, tokens, API keys, or sessions
- The bug is in an admin panel, dashboard, or gated feature

### If credentials are needed:

Ask the user directly — do NOT guess or skip this:

```
This issue appears to involve [authenticated flows / real account data / external service].

To debug this, I'll need credentials. Please provide them in `qa-results/.env.test`:

```env
# Debug Credentials — DO NOT COMMIT (gitignored)
#
# Fill in whatever applies to this issue:
#
# Account credentials
QA_TEST_USER_EMAIL=
QA_TEST_USER_PASSWORD=
#
# If the bug is role-specific:
QA_ADMIN_EMAIL=
QA_ADMIN_PASSWORD=
#
# If external services are involved:
QA_API_KEY=
QA_DATABASE_URL=
#
# If the bug needs a specific account/data:
QA_TARGET_USER_ID=
QA_TARGET_RESOURCE_ID=
```

Specifically, I need:
- [ ] [credential 1 — what and why]
- [ ] [credential 2 — what and why]

I'll wait for you to fill in `qa-results/.env.test` before proceeding with reproduction.
If you'd prefer to provide them another way, let me know.
```

### While waiting for credentials:
- Continue with Steps 2 (spec context) — you can read specs without credentials
- Run `/fix-diagnose` on what you CAN inspect (code analysis, stack traces, config)
- Do NOT attempt to reproduce auth-dependent flows without credentials — you'll get false negatives
- Do NOT hardcode, guess, or fabricate credentials

### Once credentials are provided:
1. Verify `qa-results/.env.test` exists and has the needed values
2. Verify `.gitignore` includes `qa-results/.env.test`
3. Load credentials in reproduction scripts via `dotenv` or `process.env`
4. NEVER log, screenshot, or record credentials in video output
5. Proceed to Step 3 (Reproduce)

### For future debugging sessions:
If `qa-results/.env.test` already exists from a previous session, check if the credentials are still valid and sufficient for the current issue. If the new issue requires additional credentials (different role, different service), ask the user to add them.

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

Run `/fix-diagnose` with:
- The issue description
- The spec context (what SHOULD work)
- The reproduction result (how it actually fails)

Then run `/fix-fix` with the diagnosis.

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

## UI Issues — QA Engineer is MANDATORY (NON-NEGOTIABLE)

If the issue involves the UI in ANY way — layout, styling, visual regression, component behavior, responsiveness, "looks wrong", button doesn't work, page doesn't render — the QA engineer MUST run as part of verification. This is not optional.

### Detection

An issue is a UI issue if ANY of these are true:
- The user mentions anything visual (layout, CSS, styling, responsive, looks wrong, misaligned, overlapping)
- The issue references a UI component, page, or route
- The error occurs in a `.tsx`, `.jsx`, `.vue`, `.svelte`, or template file
- The issue mentions user interaction (click, hover, scroll, navigate, form submit)
- Screenshots or videos are attached showing the problem
- The affected file is in a `components/`, `pages/`, `views/`, `layouts/`, or `app/` directory

### Required Flow for UI Issues

1. **Setup** (if not already done): Run `/qa-setup` to install Playwright and scaffold test infra
2. **Reproduce**: Write a Playwright test that reproduces the bug (captures the failure on video)
3. **Diagnose + Fix**: Run the normal debug loop (`/fix-diagnose` → `/fix-fix`)
4. **Verify via QA (MANDATORY)**: After the fix, run `/qa-final` to:
   - Re-run the specific failing test (must now pass)
   - Run ALL existing E2E flows to check for regressions
   - Record video of every flow (pass and fail)
   - Produce the QA report at `qa-results/latest/QA-REPORT.md`
5. **The fix is NOT verified until QA passes.** A unit test passing is insufficient for UI bugs — you must see it working in a real browser.

Do NOT skip QA for UI issues. Do NOT treat a passing unit test as sufficient verification. The QA engineer runs E2E across the full application to catch regressions your fix may have introduced in other flows.

## Rules

- Do NOT require a new PRD or spec — the whole point is to fix bugs without ceremony
- DO read existing specs for context — they tell you what the code should do
- **UI issues ALWAYS require QA verification** — no exceptions, no shortcuts
- The speckit hooks may block src/ edits — existing specs should satisfy the gates. If not, check that spec artifacts exist for the feature.
- Log everything in `debug-log.md` — it helps the retrospective and future debugging
- If the bug reveals a gap in the original spec (the feature was never supposed to handle this case), tell the user. They may want to update the spec before fixing.
- If the fix is trivial (typo, obvious one-line fix), just fix it directly without the full diagnose→fix loop. Use judgment. But if it's a UI fix, still run QA.
- Always run the full test suite after fixing to catch regressions
