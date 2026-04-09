# Feature PRD: Trim Penpot Layout & Auto-Flows

**Date**: 2026-04-09
**Status**: Draft
**Parent PRD**: docs/features/2026-04-09-trim/PRD.md

## Background

Trim can push components and generate designs in Penpot, but the output is unusable — everything overlaps on the canvas with no spacing, positioning, or organization. There's no dedicated component page, no layout strategy, and no automatic flow discovery. Users have to manually drag apart overlapping frames, organize components themselves, and define user flows by hand even though trim already has enough context to infer them.

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [Trim designs on Penpot overlap heavily](.kiln/issues/2026-04-09-trim-penpot-designs-overlap.md) | — | bug | high |
| 2 | [Trim should create a bento-style component page](.kiln/issues/2026-04-09-trim-component-page-bento-layout.md) | — | improvement | medium |
| 3 | [Trim should auto-build user flows during push](.kiln/issues/2026-04-09-trim-auto-build-userflows.md) | — | improvement | medium |

## Problem Statement

Trim's Penpot output is currently a pile of overlapping frames. Without proper layout, the design file is worse than useless — it requires more manual work to fix than it would to create from scratch. The component library has no organization, and user flows aren't discovered automatically, meaning `/trim-verify` and QA test generation have nothing to work with out of the box.

These are all first-use experience issues — a developer running `/trim-push` or `/trim-design` for the first time gets an unusable result and loses trust in the tool.

## Goals

- All trim Penpot output has proper spacing — no overlapping frames
- Page designs live on separate Penpot pages, not stacked on one canvas
- Components are organized on a dedicated "Components" page in a bento grid layout
- User flows are auto-discovered from code structure and Penpot page organization during push/pull/design
- Auto-discovered flows merge with manual entries, never overwrite them

## Non-Goals

- Pixel-perfect layout matching specific design systems (trim positions elements, designers refine)
- Custom layout templates per project (one good default layout is enough for v1)
- Flow visualization in Penpot (flows are tracked in `.trim/flows.json`, not drawn as arrows in Penpot)

## Requirements

### Functional Requirements

#### Canvas Layout — No Overlapping (from: trim-penpot-designs-overlap.md)

**FR-001**: When trim creates frames in Penpot via any command (push, pull, design, redesign, edit), it MUST calculate bounding boxes and position frames with minimum 40px padding between them.

**FR-002**: Page-level designs MUST be placed on separate Penpot pages — one Penpot page per application page/route. Do not stack multiple page designs on a single Penpot page.

**FR-003**: Within a single Penpot page, top-level frames MUST be arranged in a horizontal flow (left to right) with consistent gaps. If the page has multiple states or variants, arrange them vertically below the primary frame.

**FR-004**: All trim workflow agent instructions that create Penpot elements MUST include explicit positioning instructions: "Calculate the bounding box of the previous frame, then position this frame at x = previous.x + previous.width + 40."

#### Component Page — Bento Grid (from: trim-component-page-bento-layout.md)

**FR-005**: `/trim-push` and `/trim-design` MUST create (or update) a dedicated Penpot page named "Components" that contains all components in a bento grid layout.

**FR-006**: Components on the Components page MUST be grouped by category. Categories are inferred from: directory structure (e.g., `components/buttons/`, `components/inputs/`), component naming patterns, or Penpot component groups.

**FR-007**: Each component group MUST have a text header label (e.g., "Buttons", "Inputs", "Cards") positioned above the group.

**FR-008**: Components within a group MUST be arranged in a grid that fills the available width, wrapping to new rows. Each component is displayed at its natural size inside a labeled card frame.

**FR-009**: The bento grid MUST auto-arrange when new components are added — existing components keep their positions, new ones are appended to the appropriate category group.

#### Auto-Flow Discovery (from: trim-auto-build-userflows.md)

**FR-010**: During `/trim-push`, trim MUST scan the codebase for routes, page-level components, and navigation patterns (links, router calls) and auto-populate `.trim/flows.json` with discovered flows.

**FR-011**: During `/trim-pull`, trim MUST read the Penpot page/frame organization and infer flows from page ordering and any linked/connected frames.

**FR-012**: During `/trim-design`, trim MUST write user journeys from the PRD context to `.trim/flows.json` as part of design creation.

**FR-013**: Auto-discovered flow entries MUST include `"source": "auto-discovered"` to distinguish them from manually created flows (`"source": "manual"`).

**FR-014**: Auto-discovery MUST merge with existing flows — never overwrite or delete manual entries. If an auto-discovered flow matches an existing manual flow by name, skip it.

**FR-015**: Each auto-discovered flow MUST include: name, description, steps (with action, target component/route, and inferred Penpot frame reference where possible).

### Non-Functional Requirements

**NFR-001**: Layout calculations must not require additional MCP round-trips beyond what's needed for creation — read existing frame positions in the initial scan, calculate new positions locally, then create with correct coordinates.

**NFR-002**: The bento grid must look reasonable for 1-50 components. Beyond 50, it should still work but visual quality is best-effort.

**NFR-003**: Auto-flow discovery should complete in under 10 seconds for projects with up to 50 routes/pages.

## User Stories

**US-001**: As a developer running `/trim-push` for the first time, I want the Penpot file to be immediately usable — components organized, no overlap, each page on its own Penpot page.

**US-002**: As a developer browsing my component library in Penpot, I want a bento grid with category headers so I can find components visually without scrolling through a long list.

**US-003**: As a developer who just ran `/trim-push`, I want `.trim/flows.json` to already have my app's user flows so `/trim-verify` works without manual setup.

## Success Criteria

1. Zero overlapping frames after any trim command — all elements have clear spacing
2. Components page uses bento grid with category grouping
3. `/trim-push` on a Next.js/React app with 5+ routes auto-discovers at least the main navigation flow
4. Auto-discovered flows are usable by `/trim-verify` without manual editing

## Tech Stack

Inherited from parent trim PRD:
- Markdown (skill definitions) + Bash (inline shell commands)
- Wheel workflow engine
- Penpot MCP tools

No additions needed — this is about improving what the existing agent steps output, not adding new infrastructure.

## Risks & Open Questions

- **Penpot coordinate system**: Need to verify that Penpot MCP tools accept absolute x/y positioning when creating frames. If not, layout calculations won't work and we'd need a different approach.
- **Component categorization heuristic**: Inferring categories from directory structure works for well-organized projects but may fail for flat component directories. May need a fallback (alphabetical grouping).
- **Flow discovery accuracy**: Auto-discovering flows from code is heuristic. React Router, Next.js file-based routing, and Vue Router all have different patterns. May need framework-specific scanners.
