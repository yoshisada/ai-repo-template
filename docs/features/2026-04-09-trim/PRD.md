# Feature PRD: Trim — Bidirectional Design-Code Sync Plugin

**Date**: 2026-04-09
**Status**: Draft

## Overview

Trim is a Claude Code plugin that bridges Penpot designs and code via MCP. It enables solo developers to work design-first (Penpot → code), code-first (code → Penpot), or both — with bidirectional sync and drift detection. It uses wheel workflows for deterministic multi-step operations and the Penpot MCP for all design tool interactions.

## Target User

Solo developer who both designs and codes. They use Penpot for visual design and Claude Code for implementation. They want to move fluidly between design and code without manual translation.

## Problem Statement

Solo devs who design in Penpot and code in their editor face a constant translation gap. Turning a Penpot design into code is manual and error-prone. When code evolves, the Penpot design falls behind. There's no way to push code changes back to Penpot or detect when the two have diverged. The result: designs rot, code drifts, and the dev either maintains both manually or abandons one.

## Goals

- Scaffold working UI code from Penpot designs (design-first flow)
- Push existing code components into Penpot for visual editing (code-first flow)
- Sync edited Penpot designs back to code (round-trip)
- Detect drift between Penpot designs and live code
- Manage a component library that stays in sync between Penpot and code
- Generate initial designs guided by product context (PRD, existing components)

## Non-Goals

- Multi-user real-time collaboration between designer and developer
- Version history or design diffing over time
- Support for design tools other than Penpot (Figma, Sketch, etc.)
- Pixel-perfect visual regression testing (trim detects structural drift, not pixel differences)

## Use Cases

### UC-1: Design-First — Penpot → Code
Developer creates a page/component in Penpot, then runs `/trim-pull` to generate code that matches the design. Trim reads the Penpot design via MCP, extracts layout, components, styles, and generates framework-appropriate code (React, Vue, HTML, etc. based on the project's stack).

### UC-2: Code-First — Code → Penpot
Developer has existing UI code and wants to visualize/edit it in Penpot. Runs `/trim-push` to analyze code components, extract structure/styles, and create or update matching Penpot components via MCP.

### UC-3: Round-Trip Sync — Edit in Penpot, Sync Back
After pushing code to Penpot (UC-2), the developer edits the design visually in Penpot — tweaks spacing, colors, layout. Then runs `/trim-pull` to sync changes back to code. The diff is applied surgically, preserving logic and only updating visual properties.

### UC-4: Drift Detection
Developer runs `/trim-diff` to compare the current Penpot design against the current code. Trim reports mismatches: components that exist in one but not the other, style divergences, layout differences. Outputs a drift report.

### UC-5: Component Library Management
Developer runs `/trim-library` to sync a component library between Penpot and code. Components are registered with a mapping file (`.trim-components.json` or similar) that tracks which code component maps to which Penpot component. New components in either side are flagged for sync.

### UC-6: Design Generation from Product Context
Developer has a PRD or product idea but no design. Runs `/trim-design` with the product context, and trim generates an initial Penpot design informed by the PRD's requirements, existing component library, and project conventions. This is guided generation, not pure text-to-design — it uses the product context to make informed layout and component choices.

## Requirements

### Functional Requirements

#### Core Infrastructure

**FR-001**: Create `plugin-trim/` following the same structure as other plugins: `.claude-plugin/plugin.json`, `skills/`, `workflows/`, `templates/`, `package.json`.

**FR-002**: Create a `.trim-config` file (or section in an existing config) that maps the project to a Penpot project/file. Stores: Penpot project ID, file ID, default page, component mapping file path.

**FR-003**: Create a component mapping file (`.trim-components.json`) that tracks bidirectional links between code components and Penpot components. Each entry: `{ "code_path": "src/components/Button.tsx", "penpot_component_id": "...", "last_synced": "ISO-8601" }`.

#### Design-First: Penpot → Code (UC-1)

**FR-004**: `/trim-pull` skill that delegates to a `trim-pull` wheel workflow. Reads the Penpot design via MCP, extracts component tree, layout, and styles.

**FR-005**: The trim-pull workflow MUST have command steps that detect the project's UI framework (React, Vue, Svelte, plain HTML) and code conventions (CSS modules, Tailwind, styled-components, etc.) before generating code.

**FR-006**: Agent steps in the trim-pull workflow MUST generate framework-appropriate code that matches the Penpot design's layout, spacing, colors, typography, and component hierarchy.

**FR-007**: Generated code MUST use the project's existing component library when a matching component exists (lookup via `.trim-components.json`), not recreate from scratch.

**FR-008**: After generation, update `.trim-components.json` with new mappings for any newly created components.

#### Code-First: Code → Penpot (UC-2)

**FR-009**: `/trim-push` skill that delegates to a `trim-push` wheel workflow. Analyzes code components, extracts structure and styles, and creates/updates Penpot components via MCP.

**FR-010**: The trim-push workflow MUST have command steps that scan the codebase for UI components (by framework convention: `src/components/`, `app/`, etc.) and extract their visual properties.

**FR-011**: Agent steps MUST create Penpot components that visually represent the code components — correct layout, colors, typography, spacing. Not a screenshot, but a structured Penpot component that can be edited.

**FR-012**: After pushing, update `.trim-components.json` with mappings between code and newly created Penpot components.

#### Drift Detection (UC-4)

**FR-013**: `/trim-diff` skill that delegates to a `trim-diff` wheel workflow. Compares Penpot design state against code state.

**FR-014**: The drift report MUST categorize mismatches: components present in code but not Penpot, components in Penpot but not code, style divergences (color, spacing, typography), and layout differences.

**FR-015**: The drift report MUST be actionable — for each mismatch, suggest whether to pull (update code from Penpot), push (update Penpot from code), or flag for manual review.

#### Component Library (UC-5)

**FR-016**: `/trim-library` skill that lists all tracked components, their sync status, and last sync timestamp. Shows which are in sync, which have drifted, and which are unlinked.

**FR-017**: `/trim-library sync` syncs all drifted components — direction determined by which side was modified more recently (based on git history for code, Penpot modification timestamp for design).

#### Design Generation (UC-6)

**FR-018**: `/trim-design` skill that reads product context (PRD, existing components, project conventions) and generates an initial Penpot design via MCP.

**FR-019**: Design generation MUST reuse existing component library components where appropriate, not create everything from scratch.

**FR-020**: Generated designs MUST follow the project's established visual conventions (colors, typography, spacing) if detectable from existing code or Penpot components.

#### Wheel Workflow Pattern

**FR-021**: All multi-step operations (pull, push, diff, design) MUST be wheel workflows following the command-first/agent-second pattern. Command steps gather data (scan code, read config), agent steps interact with Penpot MCP.

**FR-022**: All workflows MUST resolve the trim plugin install path at runtime (same pattern as shelf: scan `installed_plugins.json`, fall back to `plugin-trim/`).

**FR-023**: Workflows MUST write step outputs to `.wheel/outputs/` for observability and context passing between steps.

### Non-Functional Requirements

**NFR-001**: Trim MUST NOT require any runtime dependencies beyond what Claude Code and the Penpot MCP provide. No npm install, no build step.

**NFR-002**: Component mapping (`.trim-components.json`) MUST be human-readable and editable — developers should be able to manually fix mappings.

**NFR-003**: All Penpot interactions MUST go through the Penpot MCP tools — no direct API calls.

**NFR-004**: Trim MUST work with any UI framework by detecting the project's stack, not hardcoding React or any single framework.

## Success Criteria

1. **Round-trip works**: Can take a component from Penpot → code → edit code → push to Penpot → verify Penpot reflects changes
2. **Drift detection accuracy**: Catches >90% of structural visual mismatches between Penpot and code
3. **Speed**: Time from Penpot design to running code under 5 minutes for a single component

## Tech Stack

- Markdown (skill definitions) + Bash (inline shell commands in skills)
- Wheel workflow engine (`plugin-wheel/`) for multi-step operations
- Penpot MCP tools for all design tool interactions
- No additional runtime dependencies

## Risks & Open Questions

- **Penpot MCP capabilities**: What operations does the Penpot MCP actually support? Need to verify: read components, create components, update styles, read/write layout properties. If MCP coverage is limited, some flows may need to be descoped.
- **Framework detection reliability**: Detecting React vs Vue vs Svelte vs plain HTML from code is heuristic. May need user confirmation on first run.
- **Style extraction fidelity**: Extracting visual properties from code (especially Tailwind classes or CSS-in-JS) into Penpot-compatible formats is non-trivial. May need framework-specific adapters.
- **Conflict resolution**: When both code and Penpot have changed since last sync, how to resolve? Start with "last-modified wins" and flag conflicts for manual review.
- **Component granularity**: What counts as a "component" for mapping purposes? A file? An export? Need a clear convention per framework.
