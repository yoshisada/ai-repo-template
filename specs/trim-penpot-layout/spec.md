# Feature Specification: Trim Penpot Layout & Auto-Flows

**Feature Branch**: `build/trim-penpot-layout-20260409`  
**Created**: 2026-04-09  
**Status**: Draft  
**Input**: User description: "Trim Penpot layout fixes — proper frame spacing (no overlap), separate Penpot pages per app page, Components page with bento grid layout by category, and auto-flow discovery during push/pull/design commands"

## User Scenarios & Testing

### User Story 1 - No Overlapping Frames After Push (Priority: P1)

A developer runs `/trim-push` to push their code components to Penpot. Currently, all frames pile on top of each other at the origin, making the Penpot file unusable. After this fix, every frame created by trim has proper spacing — no overlapping, clear visual separation.

**Why this priority**: Overlapping frames make the entire Penpot output unusable. This is the most critical fix because without it, no other layout improvements matter.

**Independent Test**: Run `/trim-push` on a project with 5+ components. Open the Penpot file and verify that every frame is visible without manually dragging anything apart.

**Acceptance Scenarios**:

1. **Given** a project with 5 code components and an empty Penpot file, **When** the developer runs `/trim-push`, **Then** all 5 component frames appear in Penpot with at least 40px spacing between each frame and no overlapping bounding boxes.
2. **Given** a Penpot file that already has 3 component frames, **When** the developer runs `/trim-push` adding 2 more components, **Then** the new frames are positioned after the existing ones without overlapping any existing content.
3. **Given** any trim command that creates Penpot elements (push, pull, design, redesign, edit), **When** the command completes, **Then** no two top-level frames overlap.

---

### User Story 2 - Separate Penpot Pages Per App Page (Priority: P1)

A developer with a multi-page app runs `/trim-push` or `/trim-design`. Instead of stacking all page designs on one Penpot page, each app page/route gets its own dedicated Penpot page. Within each Penpot page, frames are arranged horizontally with vertical variants below.

**Why this priority**: Equally critical as spacing — stacking multiple page designs on one canvas defeats the purpose of having a design file. Separate pages make designs navigable.

**Independent Test**: Run `/trim-design` on a PRD that describes 3 pages. Open Penpot and verify 3 separate Penpot pages exist, each containing only its respective page design.

**Acceptance Scenarios**:

1. **Given** a project with 3 application routes/pages, **When** the developer runs `/trim-push` or `/trim-design`, **Then** each route gets its own Penpot page named after the route.
2. **Given** a Penpot page with a primary page design, **When** the page has multiple states or variants (e.g., mobile/desktop, logged-in/logged-out), **Then** the primary frame is positioned at the top and variants are arranged vertically below it with consistent gaps.
3. **Given** a Penpot page with multiple top-level frames on the same page, **When** viewing the page, **Then** frames are arranged horizontally left-to-right with consistent gaps.

---

### User Story 3 - Components Page with Bento Grid (Priority: P2)

A developer wants to browse their component library visually in Penpot. After running `/trim-push` or `/trim-design`, a dedicated "Components" page exists in Penpot with all components organized in a bento-style grid, grouped by category with labeled headers.

**Why this priority**: Component organization is important for design usability but is secondary to basic layout correctness. The component library is a reference page, not a blocking issue for using the design file.

**Independent Test**: Run `/trim-push` on a project with components in multiple directories (buttons/, inputs/, cards/). Open Penpot and verify a "Components" page exists with grouped, labeled sections.

**Acceptance Scenarios**:

1. **Given** a project with components organized in directories (e.g., `components/buttons/`, `components/inputs/`), **When** the developer runs `/trim-push`, **Then** a Penpot page named "Components" is created with components grouped by their directory-inferred category.
2. **Given** a Components page exists, **When** components within a group are displayed, **Then** each group has a text header label (e.g., "Buttons", "Inputs") and components are arranged in a grid that wraps to new rows.
3. **Given** a Components page already exists with components, **When** the developer adds new components and runs `/trim-push` again, **Then** new components are appended to the appropriate category group without disrupting existing component positions.
4. **Given** a project with a flat component directory (no subdirectories), **When** the developer runs `/trim-push`, **Then** components are grouped alphabetically as a fallback.

---

### User Story 4 - Auto-Flow Discovery During Push/Pull/Design (Priority: P2)

A developer runs `/trim-push` on a project with multiple routes and navigation links. Without any manual setup, `.trim/flows.json` is auto-populated with discovered user flows based on routes, page components, and navigation patterns. These flows are immediately usable by `/trim-verify`.

**Why this priority**: Auto-flow discovery removes a manual setup step and enables `/trim-verify` to work out of the box. It's important but not blocking basic design usability.

**Independent Test**: Run `/trim-push` on a Next.js project with 5 routes that have navigation links between them. Check `.trim/flows.json` and verify it contains at least one auto-discovered flow.

**Acceptance Scenarios**:

1. **Given** a project with 5 routes and navigation links between them, **When** the developer runs `/trim-push`, **Then** `.trim/flows.json` contains at least one flow with `"source": "auto-discovered"` and steps that reference the routes.
2. **Given** an existing `.trim/flows.json` with 2 manually created flows, **When** the developer runs `/trim-push` and auto-discovery finds 3 flows, **Then** the 3 auto-discovered flows are appended with `"source": "auto-discovered"` and the 2 manual flows remain untouched.
3. **Given** an auto-discovered flow has the same name as an existing manual flow, **When** merging, **Then** the manual flow takes precedence and the auto-discovered duplicate is skipped.
4. **Given** a developer runs `/trim-pull`, **When** the Penpot file has multiple pages with linked frames, **Then** flows are inferred from Penpot page ordering and added to `.trim/flows.json` with `"source": "auto-discovered"`.
5. **Given** a developer runs `/trim-design` with PRD context, **When** the PRD describes user journeys, **Then** those journeys are written to `.trim/flows.json` as auto-discovered flows.

---

### Edge Cases

- What happens when a component has no directory (flat component structure)? Components are grouped alphabetically as a single "Components" category.
- What happens when Penpot MCP tools don't support absolute x/y positioning? The agent falls back to creating frames sequentially and logging a warning that manual arrangement may be needed.
- What happens when auto-flow discovery finds zero routes? `.trim/flows.json` is left unchanged (or created empty if it doesn't exist), with a log message noting no flows were discovered.
- What happens when two components have the same name in different directories? Both are included in their respective category groups; the Penpot component names include the category prefix to disambiguate.
- What happens when the Components page has more than 50 components? The bento grid still works but visual quality is best-effort beyond 50 components.

## Requirements

### Functional Requirements

- **FR-001**: When trim creates frames in Penpot via any command (push, pull, design, redesign, edit), it MUST calculate bounding boxes and position frames with minimum 40px padding between them.
- **FR-002**: Page-level designs MUST be placed on separate Penpot pages — one Penpot page per application page/route.
- **FR-003**: Within a single Penpot page, top-level frames MUST be arranged in a horizontal flow (left to right) with consistent gaps. Variants are arranged vertically below the primary frame.
- **FR-004**: All trim workflow agent instructions that create Penpot elements MUST include explicit positioning instructions referencing bounding box calculations.
- **FR-005**: `/trim-push` and `/trim-design` MUST create (or update) a dedicated Penpot page named "Components" containing all components in a bento grid layout.
- **FR-006**: Components on the Components page MUST be grouped by category, inferred from directory structure, naming patterns, or Penpot component groups.
- **FR-007**: Each component group MUST have a text header label positioned above the group.
- **FR-008**: Components within a group MUST be arranged in a grid that fills available width, wrapping to new rows, with each component displayed at natural size inside a labeled card frame.
- **FR-009**: The bento grid MUST auto-arrange when new components are added — existing components keep their positions, new ones are appended to the appropriate category group.
- **FR-010**: During `/trim-push`, trim MUST scan the codebase for routes, page-level components, and navigation patterns and auto-populate `.trim/flows.json` with discovered flows.
- **FR-011**: During `/trim-pull`, trim MUST infer flows from Penpot page ordering and linked frames, writing them to `.trim/flows.json`.
- **FR-012**: During `/trim-design`, trim MUST write user journeys from PRD context to `.trim/flows.json`.
- **FR-013**: Auto-discovered flow entries MUST include `"source": "auto-discovered"` to distinguish them from manual flows.
- **FR-014**: Auto-discovery MUST merge with existing flows — never overwrite or delete manual entries. Matching names cause the auto-discovered entry to be skipped.
- **FR-015**: Each auto-discovered flow MUST include: name, description, steps (with action, target component/route, and inferred Penpot frame reference where possible).

### Key Entities

- **Penpot Page**: A canvas within a Penpot file. Each app page/route maps to one Penpot page.
- **Component Group**: A category of components (e.g., "Buttons", "Inputs") derived from directory structure or naming.
- **Bento Grid**: A responsive grid layout on the Components page where component cards are arranged by category with headers.
- **Flow**: A user journey through the application, stored in `.trim/flows.json` with steps mapping to pages, components, and Penpot frames.
- **Flow Source**: Either "auto-discovered" (inferred from code/design) or "manual" (created by the developer via `/trim-flows add`).

## Success Criteria

### Measurable Outcomes

- **SC-001**: Zero overlapping frames after any trim command — all elements have clear visual spacing of at least 40px.
- **SC-002**: Each application page/route has its own dedicated Penpot page after `/trim-push` or `/trim-design`.
- **SC-003**: The Components page displays all components in a categorized bento grid with labeled group headers.
- **SC-004**: Running `/trim-push` on a project with 5+ routes auto-discovers at least one navigation flow in `.trim/flows.json`.
- **SC-005**: Auto-discovered flows are usable by `/trim-verify` without any manual editing.
- **SC-006**: Manual flows in `.trim/flows.json` are never overwritten or deleted by auto-discovery.

## Assumptions

- Penpot MCP tools support setting absolute x/y coordinates when creating frames. If not, positioning logic degrades gracefully with a warning.
- Projects using standard framework routing conventions (Next.js file-based routing, React Router, Vue Router) will yield the best auto-discovery results. Non-standard routing may produce fewer or no discovered flows.
- Component categorization from directory structure works well for projects with organized component directories. Flat directories fall back to alphabetical grouping.
- The deliverables are changes to existing workflow JSON agent instructions and skill SKILL.md files in plugin-trim/, not new infrastructure or runtime code.
- The bento grid layout uses a fixed column width approach with wrapping, suitable for 1-50 components. Beyond 50, visual quality is best-effort.
