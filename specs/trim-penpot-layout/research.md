# Research: Trim Penpot Layout & Auto-Flows

**Date**: 2026-04-09

## R1: Penpot MCP Positioning Support

**Decision**: Penpot MCP tools accept absolute x/y coordinates when creating frames. Agent instructions will include explicit coordinate calculations.

**Rationale**: The Penpot MCP create_component and create_rectangle tools accept x, y, width, height parameters. This means agents can calculate positions locally and set them directly.

**Alternatives considered**:
- Relative positioning (offset from previous) — rejected because Penpot MCP uses absolute coordinates
- Post-creation rearrangement — rejected because it requires extra MCP round-trips (violates NFR-001)

## R2: Component Category Inference Strategy

**Decision**: Infer categories from directory structure first (e.g., `components/buttons/` → "Buttons"), fall back to alphabetical grouping for flat directories.

**Rationale**: Directory structure is the most reliable signal in well-organized projects. Alphabetical grouping is a safe fallback that always works.

**Alternatives considered**:
- Component name prefix parsing (e.g., `BtnPrimary` → "Btn") — brittle, naming conventions vary widely
- Manual category mapping file — adds user setup friction, against the "works out of the box" goal
- AI-based classification — overkill for a layout task, adds unpredictability

## R3: Auto-Flow Discovery Approach

**Decision**: Framework-aware route scanning for push, Penpot page analysis for pull, PRD parsing for design.

**Rationale**: Each command has different available context:
- Push has access to code → scan for route definitions and navigation links
- Pull has access to Penpot → infer flows from page ordering and frame connections
- Design has access to PRD → extract user journeys from requirements

**Alternatives considered**:
- Single unified flow discovery — rejected because different commands have different context available
- Only discover on push — rejected because pull and design also have useful flow signals

## R4: Flow Merge Strategy

**Decision**: Name-based deduplication. Auto-discovered flows with the same name as existing manual flows are skipped. Auto-discovered flows include `"source": "auto-discovered"`.

**Rationale**: Simple, predictable, and safe. Manual flows always win because the developer intentionally created them.

**Alternatives considered**:
- Merge by step similarity — complex, error-prone, hard to predict behavior
- Always overwrite — violates FR-014, would destroy manual work
- Append all (allow duplicates) — creates clutter, confuses verification

## R5: Deliverable Format

**Decision**: All changes are text modifications to existing JSON workflow files (agent `instruction` fields) and Markdown skill files. No new runtime code or infrastructure.

**Rationale**: The trim plugin uses wheel workflows where agent behavior is defined by instruction text. Changing what agents do means changing their instructions, not writing new code.

**Alternatives considered**:
- Adding shell script steps for positioning calculations — rejected because Penpot operations happen inside agent steps via MCP, not in shell commands
- Creating a shared positioning library — overkill, each agent step can include the positioning logic in its instructions
