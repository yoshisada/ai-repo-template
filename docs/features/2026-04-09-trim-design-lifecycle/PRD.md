# Feature PRD: Trim Design Lifecycle — Edit, Verify, Redesign, Flows

**Date**: 2026-04-09
**Status**: Draft
**Parent PRD**: docs/features/2026-04-09-trim/PRD.md

## Overview

Extends the trim plugin with design lifecycle management: prompted design edits with change logging, visual verification against Penpot designs, full UI redesign capability, and user flow tracking. Trim becomes the single owner of UI design truth — components, flows, visual verification, and change history.

This effectively replaces kiln's `/ux-evaluate` and the qa-engineer's visual testing role with a Penpot-grounded design system. Instead of evaluating after the fact, trim owns the full lifecycle: create → edit → verify → redesign.

## Target User

Same as parent: solo developer who designs and codes. They want to iterate on designs conversationally, verify their code matches, track what changed and why, and occasionally do a full redesign.

## Problem Statement

The current trim plugin can sync between Penpot and code, but it has no way to:
- Make targeted design changes via natural language without manually opening Penpot
- Verify that rendered code actually looks like the Penpot design (structural diff ≠ visual match)
- Track design changes over time (no changelog, no decision trail)
- Do a full redesign informed by product context
- Know which user flows exist and need visual testing

Without these, trim is a sync tool but not a design system. The developer still needs to manually verify visuals, track design decisions elsewhere, and maintain user flow lists independently.

## Goals

- Edit Penpot designs via natural language without auto-syncing to code — log changes, let the developer decide when to pull
- Visually verify that rendered code matches Penpot designs using Playwright or /chrome screenshots
- Full UI redesign capability that rethinks the design from product context up
- Track all user flows with their steps, components, and pages — feeds both visual verification and QA test generation
- Maintain a design changelog as a decision trail

## Non-Goals

- Auto-sync edits to code (edits stay in Penpot until explicitly pulled)
- Auto-fix visual mismatches (verify reports, doesn't fix)
- Continuous/watch-mode verification (manual command, not CI)
- Cross-browser visual testing (single browser)
- Replacing Playwright E2E test logic (trim tracks flows, QA generates tests from them)

## Use Cases

### UC-1: Prompted Design Edit
Developer runs `/trim-edit "make the sidebar narrower and change the accent color to blue"`. Trim modifies the Penpot design via MCP. The change is logged to `.trim-changes.md` with what changed, why, and a before/after reference. Code is NOT modified — the developer reviews the Penpot change and runs `/trim-pull` when ready.

### UC-2: Visual Verification
Developer runs `/trim-verify` after pulling design changes to code. Trim renders each tracked user flow in a browser (Playwright headless or /chrome), screenshots every step, fetches the corresponding Penpot frames, and compares. Reports mismatches: layout shifts, color differences, missing elements, wrong typography. Output goes to `.trim-verify-report.md`.

### UC-3: Full Redesign
Developer runs `/trim-redesign` with optional context ("modernize the dashboard" or "switch to a dark theme"). Trim reads the PRD, existing component library, current Penpot design, and user flows. Generates a complete new Penpot design that reimagines the UI while preserving the information architecture and user flows. All changes logged with rationale.

### UC-4: User Flow Management
Developer runs `/trim-flows` to list all tracked user flows. `/trim-flows add "checkout"` defines a new flow with steps. Each flow has: name, steps (ordered list of page/component interactions), involved components, and a link to the Penpot page/frame that visualizes it. Flows are stored in `.trim-flows.json`.

### UC-5: Flow-Driven Verification
`/trim-verify` walks each flow in `.trim-flows.json` step by step — navigating routes, clicking buttons, filling forms — and screenshots each step. Compares each screenshot against the corresponding Penpot frame. This ensures not just that pages look right statically, but that the user journey renders correctly.

### UC-6: QA Integration
Kiln's QA engineer reads `.trim-flows.json` to generate Playwright E2E test stubs. Each flow becomes a test case with steps already defined. The QA engineer doesn't need to discover user flows — trim already has them.

## Requirements

### Functional Requirements

#### Design Editing (UC-1)

**FR-001**: `/trim-edit <description>` skill that modifies Penpot designs via natural language. Delegates to a `trim-edit` wheel workflow.

**FR-002**: The trim-edit workflow MUST have command steps that read the current Penpot design state and `.trim-components.json` before making changes, so edits are context-aware.

**FR-003**: Agent steps MUST interpret the natural language description and apply targeted changes to the Penpot design via MCP — not regenerate the entire design.

**FR-004**: After editing, the workflow MUST NOT sync changes to code. Changes stay in Penpot only.

**FR-005**: After editing, the workflow MUST append an entry to `.trim-changes.md` with: timestamp, description of what was requested, what was actually changed (components/properties modified), and which Penpot frames were affected.

**FR-006**: `.trim-changes.md` serves as the design decision changelog. Each entry MUST include enough context to understand why the change was made without looking at the diff.

#### Visual Verification (UC-2, UC-5)

**FR-007**: `/trim-verify` skill that visually compares rendered code against Penpot designs. Delegates to a `trim-verify` wheel workflow.

**FR-008**: The trim-verify workflow MUST render code in a browser using Playwright (headless) or /chrome MCP (if available). Playwright is the default; /chrome is used when specified or when Playwright is unavailable.

**FR-009**: For each tracked user flow in `.trim-flows.json`, the workflow MUST navigate through the flow steps, screenshot each step, and fetch the corresponding Penpot frame.

**FR-010**: The workflow MUST compare each screenshot against its Penpot counterpart and report mismatches. Comparison should identify: layout shifts, color differences, missing/extra elements, typography mismatches, spacing issues.

**FR-011**: Visual comparison MUST use screenshot analysis (Claude vision) — not pixel-diffing. The agent analyzes both images and reports semantic visual differences.

**FR-012**: Output a verification report to `.trim-verify-report.md` with: flow name, step, pass/fail, description of mismatch, screenshot paths, and Penpot frame reference.

**FR-013**: Screenshots and artifacts MUST be stored in `.trim-verify/` (gitignored), not committed.

#### Full Redesign (UC-3)

**FR-014**: `/trim-redesign [context]` skill that generates a complete new Penpot design. Delegates to a `trim-redesign` wheel workflow.

**FR-015**: The redesign workflow MUST read: PRD (product context), existing `.trim-components.json` (current component library), current Penpot design (what exists now), `.trim-flows.json` (user flows to preserve), and any optional context from the user (e.g., "dark theme", "modernize").

**FR-016**: The redesign MUST preserve the information architecture (pages, navigation structure, user flows) while reimagining the visual design (layout, colors, typography, component styling).

**FR-017**: All redesign changes MUST be logged to `.trim-changes.md` with a summary of what was redesigned and the rationale.

**FR-018**: After redesign, the workflow MUST NOT auto-sync to code. The developer reviews in Penpot and pulls when ready.

#### User Flow Management (UC-4)

**FR-019**: `/trim-flows` skill that manages user flows in `.trim-flows.json`.

**FR-020**: `.trim-flows.json` schema: array of flows, each with `name`, `description`, `steps` (ordered array of `{ action, target, page, component, penpot_frame_id }`), and `last_verified` timestamp.

**FR-021**: `/trim-flows add <name>` adds a new flow interactively — asks the developer to describe the steps, then maps each step to a page/component and Penpot frame.

**FR-022**: `/trim-flows list` displays all flows with their step count and last verification date.

**FR-023**: `/trim-flows sync` maps flow steps to Penpot frames (for flows that don't have frame IDs yet) and to code routes/components.

#### QA Integration (UC-6)

**FR-024**: `.trim-flows.json` MUST be readable by kiln's QA engineer to generate Playwright E2E test stubs. The schema must include enough detail (action, target selector or component name, expected page/route) for test generation.

**FR-025**: Provide a `/trim-flows export-tests` command that generates Playwright test stubs from `.trim-flows.json` — one test per flow, one step per assertion.

#### Wheel Workflow Pattern

**FR-026**: All new multi-step operations (edit, verify, redesign) MUST be wheel workflows following the command-first/agent-second pattern.

**FR-027**: All workflows MUST resolve the trim plugin install path at runtime (same pattern as shelf: scan `installed_plugins.json`, fall back to `plugin-trim/`).

**FR-028**: Workflows MUST write step outputs to `.wheel/outputs/` for observability.

### Non-Functional Requirements

**NFR-001**: Visual verification via Playwright MUST work headless (no display required). /chrome is optional.

**NFR-002**: `.trim-changes.md` MUST be human-readable and serve as a standalone design decision log.

**NFR-003**: `.trim-flows.json` MUST be human-readable and editable — developers should be able to manually add/modify flows.

**NFR-004**: Screenshots from verification MUST NOT be committed to git. Store in `.trim-verify/` which should be gitignored.

**NFR-005**: Redesign MUST NOT destroy existing Penpot components — it creates new versions alongside or replaces in-place with the change logged.

## Success Criteria

1. **Edit round-trip**: Can say "make the header blue" → see change in Penpot → change logged in `.trim-changes.md` → pull when ready → code reflects change
2. **Visual verification accuracy**: Catches >80% of rendering mismatches between Penpot design and live code
3. **Edit-verify cycle**: Under 3 minutes for a single component (edit → verify)
4. **Flow coverage**: All defined user flows can be walked and verified automatically
5. **QA integration**: QA engineer can generate test stubs from `.trim-flows.json` without manual flow discovery

## Tech Stack

Inherited from parent trim PRD:
- Markdown (skill definitions) + Bash (inline shell commands)
- Wheel workflow engine
- Penpot MCP tools

Additions:
- Playwright (headless browser for screenshot capture and flow walking)
- /chrome MCP (optional alternative to Playwright for visual verification)
- Claude vision (screenshot comparison via multimodal analysis)

## Risks & Open Questions

- **Penpot frame mapping**: How reliably can we map user flow steps to specific Penpot frames? May need a manual mapping step on first setup.
- **Screenshot comparison quality**: Claude vision comparing screenshots to Penpot designs is heuristic. Need to calibrate what counts as a "mismatch" vs acceptable rendering difference (e.g., font rendering, anti-aliasing).
- **Redesign scope control**: A full redesign could be overwhelming. May need to support scoped redesign ("redesign just the dashboard page") in addition to full redesign.
- **Flow step granularity**: What level of detail for flow steps? "Click login button" vs "Navigate to /login, fill email, fill password, click submit". Need to find the right level for both verification and test generation.
- **Kiln integration**: Should `/ux-evaluate` be deprecated in favor of `/trim-verify`? Or keep both — trim for Penpot-grounded verification, ux-evaluate for standalone heuristic review?
