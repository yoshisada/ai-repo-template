# Implementation Plan: Kiln & Wheel Polish

**Branch**: `build/kiln-wheel-polish-20260404` | **Date**: 2026-04-04 | **Spec**: specs/kiln-wheel-polish/spec.md
**Input**: Feature specification from `specs/kiln-wheel-polish/spec.md`

## Summary

Polish pass across the wheel workflow engine and kiln plugin: add `next` field support for step-level control flow (FR-001–FR-007), automatic terminal step cleanup (FR-008–FR-012), a lightweight `/todo` skill (FR-013–FR-018), and a path fix for the UX evaluator agent (FR-019–FR-021). All changes are backwards compatible — no schema migrations, no new dependencies.

## Technical Context

**Language/Version**: Bash 5.x (wheel engine), Markdown (skill/agent definitions)
**Primary Dependencies**: jq (JSON parsing), existing wheel/kiln plugin infrastructure
**Storage**: File-based — `.wheel/state.json`, `.kiln/todos.md`, workflow JSON files
**Testing**: Manual workflow execution, existing hook infrastructure
**Target Platform**: macOS/Linux (Claude Code plugin environment)
**Project Type**: Plugin (Claude Code plugin system)
**Constraints**: No new npm dependencies (NFR-003), backwards compatible (NFR-001)

## Constitution Check

| Gate | Status | Notes |
|------|--------|-------|
| Spec-first | PASS | spec.md written before plan |
| Interface contracts | PASS | contracts/interfaces.md produced below |
| Incremental tasks | PASS | tasks.md will be produced by /tasks |
| 80% coverage | N/A | Bash scripts + markdown — no test framework applicable |
| E2E testing | N/A | Plugin tested by running workflows on consumer projects |

## Project Structure

### Documentation (this feature)

```text
specs/kiln-wheel-polish/
├── spec.md              # Feature specification
├── plan.md              # This file
├── contracts/
│   └── interfaces.md    # Function signatures
├── tasks.md             # Task breakdown (produced by /tasks)
└── agent-notes/         # Agent friction notes
```

### Source Code (files to modify)

```text
plugin-wheel/
├── lib/
│   ├── dispatch.sh      # FR-001–FR-005: Add next field resolution to dispatch_agent, dispatch_command
│   └── workflow.sh      # FR-006–FR-007: Add next field validation to workflow_validate_references
├── hooks/
│   ├── stop.sh          # FR-011: Downgrade missing state.json to silent no-op (already done)
│   └── post-tool-use.sh # FR-011: Same no-op guard
└── (no new files)

plugin-kiln/
├── skills/
│   └── todo/
│       └── prompt.md    # FR-013–FR-018: New /todo skill (NEW FILE)
├── agents/
│   └── ux-evaluator.md  # FR-019–FR-020: Fix screenshot path to use absolute paths
└── skills/
    └── kiln-cleanup/
        └── SKILL.md     # FR-021: Add nested .kiln/ tree detection and removal
```

**Structure Decision**: No new directories except `plugin-kiln/skills/todo/`. All wheel changes are modifications to existing files. The `/todo` skill is a single `prompt.md` file following kiln's skill convention.

## Design Decisions

### D1: `next` field resolution approach

The `next` field is resolved at cursor-advance time inside `dispatch_command` and `dispatch_agent`. When a step completes and has a `next` field, the engine calls `workflow_get_step_index` to resolve the step ID to an index, then sets the cursor to that index instead of `step_index + 1`. This reuses the existing `workflow_get_step_index` function — no new lookup infrastructure needed.

The `advance_past_skipped` function is called after `next` resolution, so if the target step is already skipped, the engine advances past it. This handles edge cases where a branch routes to a step that was already processed.

### D2: Terminal step implementation location

Terminal cleanup runs inside `dispatch_command` and `dispatch_agent` after marking the step as done. Rather than adding a separate hook phase, we check for `terminal: true` after the step status update. If terminal, we archive state.json and set cursor to total_steps (workflow complete). This keeps the logic co-located with step completion rather than spread across multiple hook entry points.

### D3: `/todo` skill as pure markdown

The `/todo` skill is a single `prompt.md` that instructs Claude to manipulate `.kiln/todos.md` directly. No bash scripts, no wrapper functions. Claude reads the file, applies the operation, and writes it back. This matches the kiln convention where skills are instructions, not code.

### D4: UX evaluator path fix

The fix is in the agent markdown — changing the screenshot directory instruction from a relative path to an absolute path using `$(git rev-parse --show-toplevel)/.kiln/qa/screenshots/`. This is a one-line conceptual change in the agent definition.

## Complexity Tracking

No constitution violations. All changes are small, focused modifications to existing files plus one new skill file.
