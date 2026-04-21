---
name: "kiln-ux-evaluate"
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

## Step 0: Pre-Flight — Version Verification

Before starting evaluation:

1. Read the `VERSION` file from the project root
2. If a dev server is running, check the app for a version indicator (page footer, meta tags, CLI output)
3. If versions mismatch: run the project's build command, wait, and re-check
4. If still mismatched after rebuild: warn the user and add a disclaimer to the UX report
5. If no VERSION file exists: skip this check with a warning

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
   UX_DIR=".kiln/qa/$TIMESTAMP"
   mkdir -p "$UX_DIR/screenshots/desktop" "$UX_DIR/screenshots/tablet" "$UX_DIR/screenshots/mobile" "$UX_DIR/screenshots/reference" "$UX_DIR/snapshots"
   mkdir -p .kiln/qa/baselines
   ln -sfn "$TIMESTAMP" .kiln/qa/latest
   ```

## Step 2: Navigate and Capture

### Desktop Pass (default viewport)

For every route/page in the app:

1. `navigate_page` → the route
2. `wait_for` → page fully loaded
3. `take_screenshot` → `.kiln/qa/latest/screenshots/desktop/[page-name].png`
4. `take_snapshot` → save text output to `.kiln/qa/latest/snapshots/[page-name].txt`
5. `list_console_messages` → note any errors

For pages with interactive states, also capture:
- Hover states on primary buttons/links
- Open state of dropdowns/modals
- Empty states (if achievable)
- Error states (if achievable)
- Loading states (if catchable)

### Tablet Pass (768x1024)

Resize the browser viewport, then re-navigate to each main page:
1. `take_screenshot` → `.kiln/qa/latest/screenshots/tablet/[page-name].png`

### Mobile Pass (375x667)

Same as tablet:
1. `take_screenshot` → `.kiln/qa/latest/screenshots/mobile/[page-name].png`
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

### Lens 2: Visual Design Quality (10-Dimension Rubric)

Use the rubric defined in `plugin/templates/ux-rubric.md`. Follow the full Layer 3 procedure from the `ux-evaluator` agent:

1. **Step 3a**: Check constitution/spec for a design reference URL. If found, navigate to reference pages and capture screenshots to `.kiln/qa/latest/screenshots/reference/`.
2. **Step 3b**: Load previous baseline from `.kiln/qa/baselines/ux-rubric-latest.json` if it exists.
3. **Step 3c**: Score each desktop screenshot against all 10 dimensions (D1-D10) using the rubric anchors. Use pairwise comparison against reference if available.
4. **Step 3d**: Record findings — rubric scorecards for every page, detailed findings for scores <= 4, regression alerts for baseline drops >= 2 points.

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

## Step 3.5: Save Rubric Baseline

After all pages are scored, save the rubric results as a baseline for future runs:

```bash
# Save current rubric scores as JSON
cat > .kiln/qa/baselines/ux-rubric-latest.json << 'SCORES_EOF'
{
  "timestamp": "[ISO timestamp]",
  "reference_url": "[URL or null]",
  "pages": {
    "[page-name]": {
      "screenshot": "[path]",
      "overall": [weighted-score],
      "grade": "[letter-grade]",
      "dimensions": {
        "D1_spacing": { "score": [N], "justification": "[text]" },
        "D2_typography": { "score": [N], "justification": "[text]" },
        "D3_color": { "score": [N], "justification": "[text]" },
        "D4_alignment": { "score": [N], "justification": "[text]" },
        "D5_responsive": { "score": [N], "justification": "[text]" },
        "D6_hierarchy": { "score": [N], "justification": "[text]" },
        "D7_consistency": { "score": [N], "justification": "[text]" },
        "D8_density": { "score": [N], "justification": "[text]" },
        "D9_polish": { "score": [N], "justification": "[text]" },
        "D10_feedback": { "score": [N], "justification": "[text]" }
      }
    }
  }
}
SCORES_EOF

# Archive with timestamp (keep history)
cp .kiln/qa/baselines/ux-rubric-latest.json \
   ".kiln/qa/baselines/ux-rubric-$(date +%Y%m%d-%H%M%S).json"
```

## Step 4: Generate Report

Write `.kiln/qa/latest/UX-REPORT.md` following the format defined in the `ux-evaluator` agent definition.

Include:
- Summary scores (1-10) for each category
- **Visual Design Rubric table** — all 10 dimensions per page with overall weighted score and grade
- **Baseline Comparison table** (if baseline existed) — dimension, previous score, current score, delta, status (IMPROVED/REGRESSED/STABLE)
- **Reference Comparison summary** (if reference used) — URL, pages compared, average gap from reference
- All findings sorted by severity (Critical → Major → Minor → Suggestion)
- Page-by-page breakdown
- Accessibility compliance summary table
- Screenshot references for every finding

## Step 5: Report to User

Present a concise summary:

```
## UX Evaluation Complete

**Overall Score**: N/10
**Visual Design Grade**: [A+/A/B/C/D/F]
**Pages Evaluated**: N
**Viewports**: Desktop, Tablet, Mobile
**Reference**: [URL or "none"]
**Baseline**: [improved/regressed/stable/first run]

| Category | Score | Issues |
|----------|-------|--------|
| Heuristics | N/10 | N critical, M major |
| Visual Design | N/10 | N critical, M major |
| Accessibility | N/10 | N critical, M major |
| Interaction | N/10 | N critical, M major |

### Visual Design Rubric (per page)

| Page | D1 | D2 | D3 | D4 | D5 | D6 | D7 | D8 | D9 | D10 | Overall | Grade |
|------|----|----|----|----|----|----|----|----|----|----|---------|-------|
| [page] | [score] | ... | ... | ... | ... | ... | ... | ... | ... | ... | [weighted] | [grade] |

**Top Issues**:
1. [most impactful finding]
2. [second most impactful]
3. [third most impactful]

Full report: .kiln/qa/latest/UX-REPORT.md
Screenshots: .kiln/qa/latest/screenshots/
Baseline: .kiln/qa/baselines/ux-rubric-latest.json
```

## Rules

- This is UX evaluation ONLY — do not test functionality (that's `/kiln:kiln-qa-pass` or `/kiln:kiln-qa-final`)
- Check EVERY page, not just the "important" ones. Design issues hide on secondary pages.
- Be specific in findings — include exact values (contrast ratios, pixel sizes, colors)
- Provide actionable fix recommendations, not just problem descriptions
- Score fairly for the project's stage (prototype vs production)
- Reference screenshots by path in every finding
- If you can't verify something from screenshots (e.g., keyboard nav), mark it "NEEDS MANUAL CHECK"
- Evaluate at ALL THREE viewports — desktop, tablet, mobile
- Use `evaluate_script` for checks that need computed styles (contrast, sizes)
- Use `take_snapshot` for accessibility checks — it gives the DOM/ARIA tree
