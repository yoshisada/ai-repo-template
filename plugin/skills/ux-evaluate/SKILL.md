---
name: "ux-evaluate"
description: "Standalone UI/UX evaluation using /chrome. Navigates every page, takes screenshots at each viewport, and evaluates heuristics, visual design, accessibility, and interaction quality. No functional testing — just design review."
---

# UX Evaluate — Standalone Design & Usability Review

Evaluate the UI/UX of a running application without doing functional testing. Navigates every page using `/chrome`, takes screenshots, captures accessibility snapshots, and produces a structured UX evaluation report.

Use this when you want design feedback without running a full QA pass.

```text
$ARGUMENTS
```

If arguments provide a URL, use that. Otherwise detect the dev server.

**Requires**: Chrome browser + Claude-in-Chrome extension.

## Step 1: Setup

1. **Verify /chrome is available**. If not, guide the user to enable it.

2. **Determine the target URL**:
   - If user provided a URL in arguments, use that
   - Otherwise, detect the running dev server (check common ports: 5173, 3000, 8080, 4200)
   - If no server running, start one:
     ```bash
     npm run dev &
     DEV_PID=$!
     ```

3. **Read spec context** (if available): `specs/*/spec.md`, `specs/*/plan.md` for understanding intended behavior and pages.

4. **Prepare artifacts**:
   ```bash
   TIMESTAMP=$(date +%Y%m%d-%H%M%S)
   UX_DIR="qa-results/$TIMESTAMP"
   mkdir -p "$UX_DIR/screenshots/desktop" "$UX_DIR/screenshots/tablet" "$UX_DIR/screenshots/mobile" "$UX_DIR/snapshots"
   ln -sfn "$TIMESTAMP" qa-results/latest
   ```

## Step 2: Navigate and Capture

### Desktop Pass (default viewport)

For every route/page in the app:

1. `navigate_page` → the route
2. `wait_for` → page fully loaded
3. `take_screenshot` → `qa-results/latest/screenshots/desktop/[page-name].png`
4. `take_snapshot` → save text output to `qa-results/latest/snapshots/[page-name].txt`
5. `list_console_messages` → note any errors

For pages with interactive states, also capture:
- Hover states on primary buttons/links
- Open state of dropdowns/modals
- Empty states (if achievable)
- Error states (if achievable)
- Loading states (if catchable)

### Tablet Pass (768x1024)

Resize the browser viewport, then re-navigate to each main page:
1. `take_screenshot` → `qa-results/latest/screenshots/tablet/[page-name].png`

### Mobile Pass (375x667)

Same as tablet:
1. `take_screenshot` → `qa-results/latest/screenshots/mobile/[page-name].png`
2. Additionally check: hamburger menu opens, no horizontal scroll, text readable

## Step 3: Evaluate

Run the four evaluation lenses against all collected artifacts:

### Lens 1: Heuristic Evaluation (Nielsen's 10)

For each page, evaluate against all 10 heuristics:
- H1: Visibility of system status
- H2: Match between system and real world
- H3: User control and freedom
- H4: Consistency and standards
- H5: Error prevention
- H6: Recognition rather than recall
- H7: Flexibility and efficiency of use
- H8: Aesthetic and minimalist design
- H9: Help users recognize/diagnose/recover from errors
- H10: Help and documentation

### Lens 2: Visual Design Quality

Review desktop screenshots for:
- Spacing consistency (padding, margins, rhythm)
- Typography hierarchy (heading levels, body text size, font consistency)
- Color palette consistency and meaningful use
- Alignment to grid
- Visual hierarchy (eye flow)
- Polish (border radii, shadows, icon consistency)

### Lens 3: Accessibility (WCAG 2.1 AA)

Using snapshots (DOM/accessibility tree):
- Color contrast ratios (4.5:1 text, 3:1 large text) — use `evaluate_script` to compute if needed:
  ```javascript
  // Example: check contrast of an element
  const el = document.querySelector('[data-testid="submit-btn"]');
  const style = getComputedStyle(el);
  return { color: style.color, background: style.backgroundColor };
  ```
- ARIA labels on all interactive elements
- Heading hierarchy (h1 → h2 → h3, no skips)
- Alt text on images
- Form label associations
- `<html lang="...">` attribute
- Focus indicators (check for `:focus` styles in CSS)
- Touch targets on mobile viewport (>= 44x44px)

### Lens 4: Interaction Quality

Review screenshots and snapshots for:
- Button/link hover and disabled states
- Loading indicators
- Error message placement and clarity
- Empty states
- Form validation patterns
- Toast/notification presence
- Responsive layout adaptation

## Step 4: Generate Report

Write `qa-results/latest/UX-REPORT.md` following the format defined in the `ux-evaluator` agent definition.

Include:
- Summary scores (1-10) for each category
- All findings sorted by severity (Critical → Major → Minor → Suggestion)
- Page-by-page breakdown
- Accessibility compliance summary table
- Screenshot references for every finding

## Step 5: Report to User

Present a concise summary:

```
## UX Evaluation Complete

**Overall Score**: N/10
**Pages Evaluated**: N
**Viewports**: Desktop, Tablet, Mobile

| Category | Score | Issues |
|----------|-------|--------|
| Heuristics | N/10 | N critical, M major |
| Visual Design | N/10 | N critical, M major |
| Accessibility | N/10 | N critical, M major |
| Interaction | N/10 | N critical, M major |

**Top Issues**:
1. [most impactful finding]
2. [second most impactful]
3. [third most impactful]

Full report: qa-results/latest/UX-REPORT.md
Screenshots: qa-results/latest/screenshots/
```

## Rules

- This is UX evaluation ONLY — do not test functionality (that's `/qa-pass` or `/qa-final`)
- Check EVERY page, not just the "important" ones. Design issues hide on secondary pages.
- Be specific in findings — include exact values (contrast ratios, pixel sizes, colors)
- Provide actionable fix recommendations, not just problem descriptions
- Score fairly for the project's stage (prototype vs production)
- Reference screenshots by path in every finding
- If you can't verify something from screenshots (e.g., keyboard nav), mark it "NEEDS MANUAL CHECK"
- Evaluate at ALL THREE viewports — desktop, tablet, mobile
- Use `evaluate_script` for checks that need computed styles (contrast, sizes)
- Use `take_snapshot` for accessibility checks — it gives the DOM/ARIA tree
