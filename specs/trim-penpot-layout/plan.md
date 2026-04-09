# Implementation Plan: Trim Penpot Layout & Auto-Flows

**Branch**: `build/trim-penpot-layout-20260409` | **Date**: 2026-04-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/trim-penpot-layout/spec.md`

## Summary

Update existing trim plugin workflow JSON agent instructions and skill SKILL.md files to: (1) add explicit frame positioning/spacing logic to all Penpot-creating agent steps, (2) create separate Penpot pages per app route, (3) add a Components page with bento grid layout, and (4) add auto-flow discovery steps to push/pull/design workflows. No new files or infrastructure — all changes are text updates to existing workflow definitions and skill instructions.

## Technical Context

**Language/Version**: Markdown (skill definitions), Bash (inline shell in workflows), JSON (workflow definitions)
**Primary Dependencies**: Wheel workflow engine, Penpot MCP tools, `jq` for JSON manipulation
**Storage**: File-based — `.trim/flows.json`, `.trim/components.json`, workflow JSON files
**Testing**: Manual testing via running trim commands on consumer projects
**Target Platform**: Claude Code plugin system (any OS)
**Project Type**: Plugin (Claude Code plugin with wheel workflows)
**Performance Goals**: N/A — agent instruction text changes, no runtime performance impact
**Constraints**: All changes are to agent instruction text within existing JSON/Markdown files. No new files except where a new workflow step is needed.
**Scale/Scope**: 6 workflow JSON files + 3-4 skill SKILL.md files to update

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| Spec-first | PASS | spec.md exists at specs/trim-penpot-layout/spec.md |
| Interface contracts | PASS | contracts/interfaces.md will define the workflow step changes |
| No implementation before plan | PASS | This is the plan phase |
| Incremental task completion | WILL COMPLY | Tasks will be marked [X] individually |
| 80% test coverage | N/A | No runtime code — these are agent instruction text changes |
| E2E testing | N/A | Plugin instructions tested by running commands on consumer projects |

## Project Structure

### Documentation (this feature)

```text
specs/trim-penpot-layout/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── interfaces.md    # Workflow step change contracts
└── tasks.md             # Phase 2 output (created by /tasks)
```

### Source Code (files to modify)

```text
plugin-trim/
├── workflows/
│   ├── trim-push.json        # Add positioning + Components page + flow discovery steps
│   ├── trim-pull.json        # Add positioning + flow discovery step
│   ├── trim-design.json      # Add positioning + Components page + flow discovery steps
│   ├── trim-redesign.json    # Add positioning to generate-redesign instruction
│   ├── trim-edit.json        # Add positioning to apply-edit instruction
│   └── trim-library-sync.json # Add positioning to sync-components instruction
└── skills/
    ├── trim-push/SKILL.md    # Update report to mention Components page + flows
    ├── trim-pull/SKILL.md    # Update report to mention flow discovery
    ├── trim-design/SKILL.md  # Update report to mention Components page + flows
    └── trim-flows/SKILL.md   # No structural changes needed
```

**Structure Decision**: All changes are to existing files in plugin-trim/workflows/ and plugin-trim/skills/. No new files are created except for the new workflow steps added as entries within existing JSON arrays.

## Phases

### Phase 1: Frame Positioning & Page Separation (FR-001, FR-002, FR-003, FR-004)

Update all workflow agent instructions that create Penpot elements to include:
- Bounding box calculation before creating each frame
- 40px minimum padding between frames
- Horizontal left-to-right arrangement for top-level frames
- Vertical arrangement for variants below primary frame
- One Penpot page per app route (for push and design workflows)

**Files**: All 6 workflow JSON files (agent step `instruction` fields)

### Phase 2: Components Page with Bento Grid (FR-005, FR-006, FR-007, FR-008, FR-009)

Add a new agent step (or extend existing push-to-penpot / generate-design steps) to:
- Create/update a "Components" page in Penpot
- Group components by category (directory-inferred)
- Add text header labels per group
- Arrange components in a wrapping grid layout

**Files**: trim-push.json, trim-design.json, corresponding SKILL.md files

### Phase 3: Auto-Flow Discovery (FR-010, FR-011, FR-012, FR-013, FR-014, FR-015)

Add new workflow steps to push, pull, and design workflows:
- push: scan codebase for routes/navigation, write to .trim/flows.json
- pull: infer flows from Penpot page organization
- design: extract user journeys from PRD context
- All: merge with existing flows, never overwrite manual entries

**Files**: trim-push.json, trim-pull.json, trim-design.json, corresponding SKILL.md files
