---
name: "qa-setup"
description: "Install Playwright, scaffold QA test infrastructure, and generate a test matrix from the spec. Run this before any QA testing."
---

## QA Setup

Install Playwright and scaffold the test infrastructure for visual QA testing.

```text
$ARGUMENTS
```

### Step 1: Install Playwright

```bash
# Check if Playwright is already installed
if npx playwright --version 2>/dev/null; then
  echo "Playwright already installed: $(npx playwright --version)"
else
  echo "Installing Playwright..."
  npm install -D @playwright/test
  npx playwright install chromium
fi
```

If installation fails, report the error and STOP.

### Step 2: Scaffold QA Directory

Create the QA test infrastructure in the project:

```bash
mkdir -p .kiln/qa/tests .kiln/qa/videos .kiln/qa/screenshots .kiln/qa/traces
```

### Step 3: Generate Playwright Config

Write `.kiln/qa/playwright.config.ts`:

```typescript
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  outputDir: './test-results',
  timeout: 30000,
  retries: 1,
  reporter: [
    ['html', { outputFolder: './reports' }],
    ['json', { outputFile: './reports/results.json' }],
    ['list']
  ],
  use: {
    baseURL: process.env.DEV_URL || 'http://localhost:5173',
    video: 'on',
    trace: 'on',
    screenshot: 'on',
    headless: true,
    viewport: { width: 1280, height: 720 },
  },
  projects: [
    {
      name: 'desktop-chrome',
      use: { browserName: 'chromium' },
    },
    {
      name: 'mobile-chrome',
      use: {
        browserName: 'chromium',
        viewport: { width: 375, height: 667 },
        isMobile: true,
      },
    },
  ],
});
```

Detect the correct dev server port from `vite.config`, `next.config`, `package.json`, or framework defaults and update `baseURL` accordingly. Common ports: 5173 (Vite), 3000 (Next.js/CRA), 8080 (Vue CLI), 4200 (Angular).

### Step 4: Generate Test Matrix

Read these files (do NOT read source code):

1. `specs/*/spec.md` — Extract every user story and acceptance scenario
2. `specs/*/plan.md` — Identify routes/pages and UI components
3. `docs/PRD.md` or `docs/features/*/PRD.md` — Product requirements

Write a test matrix to `.kiln/qa/test-matrix.md`:

```markdown
# QA Test Matrix

Generated from: specs/<feature>/spec.md
Date: [timestamp]

| # | User Flow | Source | Steps | Expected Result | Priority | Status |
|---|-----------|--------|-------|-----------------|----------|--------|
| 1 | [flow name] | US-NNN / FR-NNN | [high-level steps] | [expected outcome] | P0/P1/P2 | untested |
```

Priority levels:
- **P0**: Core happy paths — must pass for any release
- **P1**: Important edge cases and error handling
- **P2**: Responsive/viewport and polish

**Comprehensive coverage is required.** The test matrix must include EVERY user-facing flow in the spec — not just happy paths. Every route, every form, every interactive element, every error state. If the spec mentions it, it goes in the matrix. Flows that can't be tested (credentials, external deps) are still listed as `blocked:reason`.

### Step 5: Generate Test Stubs

For **every flow** in the test matrix (P0, P1, AND P2), generate a Playwright test stub in `.kiln/qa/tests/`:

```typescript
// .kiln/qa/tests/flow-01-[slug].spec.ts
import { test, expect } from '@playwright/test';

test.use({
  video: 'on',
  trace: 'on',
  screenshot: 'on',
});

test('US-001: [flow name]', async ({ page }) => {
  // TODO: QA engineer will flesh out these steps during checkpoint
  await page.goto('/');
  // Step 1: ...
  // Step 2: ...
  // Verify: ...
});
```

### Step 6: Detect Credential Requirements

Scan the test matrix for flows that require authentication, API keys, or test accounts. Common signals:
- Login/signup/logout flows
- OAuth, SSO, or third-party auth
- API keys for external services (Stripe, SendGrid, etc.)
- Admin-only or role-gated pages
- Payment/checkout flows

If ANY flow requires credentials:

1. Generate a template at `.kiln/qa/.env.test.example`:

```env
# QA Test Credentials
# Copy this file to .kiln/qa/.env.test and fill in values.
# .env.test is gitignored — NEVER commit real credentials.

# Example entries (customize based on what flows need):
# QA_TEST_USER_EMAIL=
# QA_TEST_USER_PASSWORD=
# QA_STRIPE_TEST_KEY=
# QA_ADMIN_EMAIL=
# QA_ADMIN_PASSWORD=
```

2. Add `.kiln/qa/.env.test` to `.gitignore` if not already present.

3. Check if `.kiln/qa/.env.test` already exists (user may have pre-filled it).

4. If credentials are needed but `.kiln/qa/.env.test` doesn't exist or is incomplete, send a message to the team lead via `SendMessage`:

```
QA CREDENTIALS NEEDED

The following flows require credentials I don't have:

| Flow | What's Needed | Why |
|------|--------------|-----|
| [flow] | [credential] | [reason] |

Please ask the user to fill in `.kiln/qa/.env.test` (template at `.kiln/qa/.env.test.example`).

I'll mark these flows as BLOCKED until credentials are provided. Non-auth flows will proceed normally.
```

5. In the test matrix, mark credential-dependent flows:

```markdown
| 3 | User login | US-002 | ... | ... | P0 | **blocked:credentials** |
```

### Output

Report:
- Playwright version installed
- Number of user flows in test matrix (by priority)
- Number of test stubs generated
- Credential-dependent flows: N (blocked until `.kiln/qa/.env.test` is provided)
- Path to test matrix: `.kiln/qa/test-matrix.md`
- Path to Playwright config: `.kiln/qa/playwright.config.ts`
- Path to test stubs: `.kiln/qa/tests/`
- Path to credential template: `.kiln/qa/.env.test.example` (if needed)

### Rules

- Do NOT read source code — build the test matrix from spec/PRD only
- Do NOT run any tests — this is setup only
- Always detect the correct dev server port
- Test stubs should use accessible selectors (getByRole, getByLabel, getByText, getByTestId)
- Every test name MUST reference its user story or FR
- NEVER hardcode or guess credentials — always request from user via team lead
- NEVER commit `.kiln/qa/.env.test` — only the `.env.test.example` template
