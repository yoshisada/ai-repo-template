# Feature PRD: Trim-Push v2 — Agent Team Design Sync Pipeline

**Date**: 2026-04-09
**Status**: Draft
**Parent PRD**: [Trim — Bidirectional Design-Code Sync Plugin](../2026-04-09-trim/PRD.md)

## Overview

Replace the monolithic trim-push workflow with a multi-agent pipeline that discovers app routes, extracts design language, builds a verified component library in Penpot, then fans out parallel page-builder agents to compose every screen — each verified against the live running app via `/chrome` screenshots. Every phase includes a compare-and-fix loop (max 3 attempts) that checks Penpot output against the live app. Failures produce detailed reports of what's still wrong and why.

## Motivation

The current trim-push is a single agent doing everything sequentially: scan files, classify as component or page, push to Penpot. This produces shallow results — isolated component frames without real design fidelity, no verification against the actual running app, and no parallelism. The Penpot file ends up as a parts catalog, not a usable design system.

A team of specialized agents can produce verified, accurate Penpot designs because:
- Route discovery maps the full app structure before anything is built
- Design extraction focuses on understanding the visual language first
- Verification loops catch mismatches before they compound
- Parallel page builders scale with app size
- Live app screenshots are the ground truth, not code analysis guesses

## Problem Statement

Solo developers who push code to Penpot via `/trim-push` get a component library that doesn't match the real app. Components are approximations built from code analysis alone — colors, spacing, and layout don't match what the user actually sees in the browser. Pages aren't composed at all. There's no verification step, so mismatches are invisible until the developer opens Penpot and notices things look wrong.

## Goals

- Discover every route/page in the app automatically from the entrypoint
- Extract a complete design language (tokens, typography, colors, spacing) from the codebase
- Build a Penpot component library that visually matches the live running app
- Compose full-screen Penpot pages for every route at 3 viewport sizes (desktop, tablet, mobile)
- Verify every component and page against live app screenshots via `/chrome`
- Fix mismatches automatically (up to 3 attempts per item)
- Produce detailed failure reports for items that can't be matched after max attempts
- Parallelize page composition across multiple agents

## Non-Goals

- Trim-pull (Penpot-to-code direction) — this PRD covers push only
- Exporting design tokens to CSS/Tailwind config files
- CI/CD integration (auto-push on commit)
- Pixel-perfect matching — agents evaluate structural and visual similarity, not pixel diffing
- Multi-user collaboration or real-time sync

## User Stories

### US-1: Full App Discovery
As a developer, I want trim-push to automatically find every page in my app by following the router config from the entrypoint, so I don't have to manually list routes or components.

### US-2: Design Language Extraction
As a developer, I want trim-push to understand my app's design language (colors, fonts, spacing, component patterns) before building anything in Penpot, so the output looks like my actual app — not a generic approximation.

### US-3: Verified Component Library
As a developer, I want every component in the Penpot library to be visually compared against the live running app, so I know the library is accurate before pages are built from it.

### US-4: Parallel Page Composition
As a developer, I want multiple agents building Penpot pages simultaneously, so a large app (20+ pages) doesn't take hours to push.

### US-5: Responsive Viewport Coverage
As a developer, I want each page to include desktop (1440x900), tablet (768x1024), and mobile (375x812) viewport variants, so I can review responsive behavior in Penpot.

### US-6: Verify-and-Fix Loop
As a developer, I want each component and page to be compared against the live app and automatically fixed if they don't match (up to 3 attempts), so the output is as accurate as possible without manual intervention.

### US-7: Failure Reports
As a developer, when a component or page can't be matched after 3 attempts, I want a detailed report explaining what was tried, what's still wrong (with side-by-side screenshots), and the agent's best guess at why — so I know exactly what needs manual attention.

### US-8: Dev Server Management
As a developer, I want the pipeline to start my dev server automatically if it's not already running, or use a URL I provide, so I don't have to set up anything before running `/trim-push`.

## Functional Requirements

### Pipeline Structure

**FR-001** — The trim-push v2 pipeline MUST use Claude Code agent teams to orchestrate 5 phases: route discovery, design extraction, component verification, parallel page composition, and final reporting.

**FR-002** — The pipeline MUST be invocable via `/trim-push` (replacing the current v1 behavior). The existing v1 workflow is superseded.

### Phase 1: Route Discovery

**FR-003** — A `route-mapper` agent MUST start at the app entrypoint (e.g., `main.tsx`, `App.tsx`, `index.html`) and follow the router configuration to discover every route in the app.

**FR-004** — The route-mapper MUST produce a page inventory containing: route path, page component file, layout wrapper (if any), imported components, and navigation links to other routes.

**FR-005** — The route-mapper MUST detect the routing framework automatically: React Router, Next.js App Router, Next.js Pages Router, Vue Router, SvelteKit, or static HTML links.

**FR-006** — The page inventory MUST be written to `.trim/page-inventory.json` for use by downstream agents.

### Phase 2: Design Language Extraction

**FR-007** — A `design-extractor` agent MUST analyze the codebase to extract design tokens: color palette, typography scale (font families, sizes, weights, line heights), spacing system, border radii, shadows, and breakpoints.

**FR-008** — The design-extractor MUST extract tokens from: CSS/SCSS variables, Tailwind config, styled-components themes, CSS-in-JS theme objects, or inline styles — based on the detected CSS approach.

**FR-009** — The design-extractor MUST build a Penpot "Components" page containing all reusable components arranged in a categorized bento grid (grouped by directory/type).

**FR-010** — The design-extractor MUST write extracted tokens to `.trim/design-tokens.json` for use by page-builder agents.

### Phase 3: Component Verification

**FR-011** — A `component-verifier` agent MUST compare each Penpot component against the live running app by:
  a. Navigating to a page where the component appears (via `/chrome`)
  b. Screenshotting the component in the live app
  c. Screenshotting the corresponding Penpot component
  d. Comparing the two for structural and visual similarity

**FR-012** — The comparison MUST evaluate: layout structure, colors (against design tokens), typography, spacing/sizing, and presence of expected child elements. It is NOT pixel-perfect — it is semantic visual comparison.

**FR-013** — If a component does not match, the component-verifier MUST send feedback to the design-extractor with what's wrong. The design-extractor fixes it and the verifier re-checks. This loop runs up to 3 attempts per component.

**FR-014** — After 3 failed attempts, the component-verifier MUST log a failure report containing: component name, what was tried each attempt, what's still wrong, side-by-side screenshot paths, and the agent's assessment of why it can't match (e.g., "uses custom SVG icon not recreatable in Penpot", "dynamic content renders differently based on state").

### Phase 4: Page Composition

**FR-015** — The team lead MUST spawn N parallel `page-builder` agents based on the page inventory. Sizing: 1 agent per 2-3 pages, capped at 5 agents. Pages sharing the same layout SHOULD be grouped to the same agent.

**FR-016** — Each page-builder agent MUST:
  a. Navigate to its assigned page route in the live app via `/chrome`
  b. Screenshot the page at 3 viewport sizes: desktop (1440x900), tablet (768x1024), mobile (375x812)
  c. Create a dedicated Penpot page named after the route
  d. Build full-screen frames at all 3 viewport sizes, composing from the verified component library
  e. Use the live screenshots as ground truth for layout, spacing, and content placement

**FR-017** — Each page-builder MUST reference Penpot components from the component library page — not recreate component internals. If a component doesn't exist in the library, flag it to the team lead.

**FR-018** — Each page-builder MUST run a verify-and-fix loop after composing each page:
  a. Screenshot the Penpot page
  b. Compare against the live app screenshot
  c. If mismatch: identify what's wrong (missing element, wrong spacing, wrong component), fix it, re-screenshot
  d. Max 3 attempts per page per viewport

**FR-019** — After 3 failed attempts on a page, the page-builder MUST produce a failure report containing: page name/route, viewport size, what was tried each attempt, what's still wrong, side-by-side screenshot paths (Penpot vs live), and the agent's assessment of why it can't match.

### Phase 5: Reporting

**FR-020** — After all page-builders complete, the team lead MUST produce a final summary report containing:
  - Total pages discovered vs pages composed
  - Component library: total components, verified count, failed count
  - Per-page: verified (all 3 viewports match), partial (some viewports match), failed (no viewports match)
  - Overall accuracy percentage
  - Links to all failure reports
  - List of components/pages that need manual attention

**FR-021** — The final report MUST be written to `.trim/push-report.md`.

### Dev Server Management

**FR-022** — Before any verification step, the pipeline MUST ensure a running app is available:
  a. If the user provided a `dev_url` in `.trim/config`, use that URL
  b. Otherwise, check if the dev server is already running (attempt to fetch localhost on common ports)
  c. If not running, start it: detect the start command from `package.json` scripts (`dev`, `start`, `serve`) and run it in the background
  d. Wait for the server to respond before proceeding

**FR-023** — The pipeline MUST shut down any dev server it started after the pipeline completes.

### Component Mapping

**FR-024** — The pipeline MUST update `.trim/components.json` with all component and page mappings after completion, including `classification` (component or page), Penpot IDs, verification status, and last sync timestamp.

## Non-Functional Requirements

**NFR-001** — The pipeline MUST complete within 30 minutes for an app with up to 20 pages and 50 components. Parallelism is the primary mechanism.

**NFR-002** — Agent team size MUST NOT exceed 8 agents total (1 route-mapper + 1 design-extractor + 1 component-verifier + up to 5 page-builders).

**NFR-003** — All Penpot interactions MUST go through Penpot MCP tools. No direct API calls.

**NFR-004** — All live app interactions MUST go through `/chrome` MCP tools. No headless browser scripts.

**NFR-005** — Screenshot artifacts from verification loops MUST be written to `.trim/verify/` (gitignored) and NOT committed.

## Tech Stack

Inherited from parent PRD:
- Markdown (skill/agent definitions), Bash 5.x (inline shell in skills/workflows)
- Claude Code agent teams (TeamCreate, TaskCreate, SendMessage)
- Penpot MCP tools for all design operations
- `/chrome` MCP tools for live app interaction and screenshots
- Wheel workflow engine (for any deterministic command steps)

Additions:
- Agent team orchestration (replaces single-agent wheel workflow for the pipeline)
- Dev server lifecycle management (detect, start, health-check, stop)

## Success Criteria

- Every page discovered by route-mapper has a corresponding Penpot page after a single `/trim-push` run
- Component library accuracy >= 90% match against live app (visual comparison by component-verifier)
- Page composition accuracy >= 80% match against live app screenshots (across all viewports)
- Detailed failure reports produced for every component/page that doesn't match after 3 attempts
- Pipeline completes for a 15-page app in under 20 minutes

## Risks & Open Questions

- **Component isolation for screenshots**: Not all components appear in isolation — some only exist within pages. The component-verifier may need to screenshot components in-context and crop, rather than finding isolated views.
- **Dev server startup variability**: Different frameworks have different startup times and port conventions. The server detection logic needs to handle Next.js, Vite, CRA, and custom setups.
- **Penpot MCP limitations**: Creating complex composed layouts in Penpot via MCP may hit API limits or produce layouts that don't match the intended design. The fix loop helps, but some layouts may be fundamentally difficult to express via MCP.
- **Dynamic content**: Pages with auth gates, loading states, or data-dependent content may screenshot differently each time. Agents need to handle or skip these gracefully.
- **Screenshot comparison quality**: The "does this match?" judgment is made by the agent looking at two images. This is subjective — may need to calibrate what "match" means across different component types.
