# Implementation Plan: Wheel Workflow Composition

**Branch**: `build/wheel-workflow-composition-20260407` | **Date**: 2026-04-07 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/wheel-workflow-composition/spec.md`

## Summary

Add a `workflow` step type to the wheel engine that invokes another workflow inline as a child. When the engine cursor reaches a workflow step, it activates the referenced workflow with its own state file. When the child completes, the parent advances. Validation detects circular references and caps nesting at 5 levels. The fan-in from child to parent happens in the PostToolUse hook.

## Technical Context

**Language/Version**: Bash 5.x
**Primary Dependencies**: jq (JSON parsing), existing wheel engine libs (state.sh, workflow.sh, dispatch.sh, engine.sh, context.sh, lock.sh, guard.sh)
**Storage**: File-based JSON state in `.wheel/state_*.json`
**Testing**: Manual integration testing via workflow execution (no test framework for shell scripts)
**Target Platform**: macOS/Linux (Claude Code plugin environment)
**Project Type**: CLI plugin (shell scripts)
**Performance Goals**: N/A (workflow steps execute sequentially, bounded by nesting depth of 5)
**Constraints**: No new dependencies. All changes must be backwards-compatible with existing step types.
**Scale/Scope**: 6 existing workflows, adding 1 new step type to the engine

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-First | PASS | spec.md committed with 18 FRs, acceptance scenarios, success criteria |
| II. 80% Test Coverage | N/A | No test framework for shell scripts in this plugin repo |
| III. PRD as Source of Truth | PASS | PRD at docs/features/2026-04-07-wheel-workflow-composition/PRD.md is authoritative |
| IV. Hooks Enforce Rules | PASS | Existing kiln hooks enforce spec-first workflow |
| V. E2E Testing Required | PASS | Will validate via manual e2e: create parent+child workflows, run, verify completion |
| VI. Small, Focused Changes | PASS | Changes touch 5 files, each modification is bounded |
| VII. Interface Contracts | PASS | contracts/interfaces.md will define all new/modified function signatures |
| VIII. Incremental Tasks | PASS | Tasks will be marked [X] after each completion |

## Project Structure

### Documentation (this feature)

```text
specs/wheel-workflow-composition/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── interfaces.md    # Function signatures
└── tasks.md             # Phase 2 output (/tasks command)
```

### Source Code (repository root)

```text
plugin-wheel/
├── lib/
│   ├── dispatch.sh      # MODIFY: add dispatch_workflow(), update dispatch_step() case
│   ├── workflow.sh      # MODIFY: add circular detection, nesting depth, workflow ref validation
│   ├── engine.sh        # MODIFY: update engine_kickstart() to skip workflow steps
│   └── state.sh         # MODIFY: add parent_workflow field support in state_init()
├── hooks/
│   └── post-tool-use.sh # MODIFY: add fan-in logic for child→parent advancement
└── bin/
    └── activate.sh      # NO CHANGE (intercepted by hook)
```

**Structure Decision**: This is a modification to existing files only. No new files are created. The `workflow` step type is added to the existing dispatch/validation/state infrastructure.

## Phases

### Phase 1: Validation (workflow.sh)

Extend `workflow_load` with three new validation checks for `workflow` steps:
1. Reference validation: every `workflow` step's `workflow` field resolves to an existing file
2. Circular detection: DFS with visited set across transitive workflow references
3. Nesting depth cap: track depth during recursive validation, fail at >5

**Files**: `plugin-wheel/lib/workflow.sh`
**FR coverage**: FR-003, FR-004, FR-005, FR-006

### Phase 2: State Management (state.sh)

Add `parent_workflow` field to `state_init()` as an optional parameter. When a child workflow is activated, the parent state file path is stored in the child's state JSON.

**Files**: `plugin-wheel/lib/state.sh`
**FR coverage**: FR-016, FR-017

### Phase 3: Dispatch (dispatch.sh)

Add `dispatch_workflow()` function and integrate into `dispatch_step()` case statement. The workflow dispatch:
- On `stop` hook: marks parent step as `working`, activates child workflow (creates child state file via `state_init`), runs child kickstart
- On `post_tool_use` hook: checks if child completed, performs fan-in (marks parent step done, advances parent cursor)
- Does NOT support `teammate_idle` or `subagent_stop` (workflow steps don't involve agents directly)

**Files**: `plugin-wheel/lib/dispatch.sh`
**FR coverage**: FR-001, FR-002, FR-007, FR-008, FR-009, FR-010, FR-012, FR-013

### Phase 4: Engine Integration (engine.sh)

Update `engine_kickstart()` to handle `workflow` step type — leave it in `pending` and don't dispatch (workflow steps need hook interception to manage the child lifecycle).

**Files**: `plugin-wheel/lib/engine.sh`
**FR coverage**: FR-014, FR-015

### Phase 5: Hook Integration (post-tool-use.sh)

Update the PostToolUse hook to:
1. After child workflow terminal step completes (before archiving), check for parent state file
2. If parent found: mark parent's workflow step as `done`, advance parent cursor
3. Update deactivate.sh interception to cascade stop to child workflows (FR-018)

**Files**: `plugin-wheel/hooks/post-tool-use.sh`
**FR coverage**: FR-011, FR-012, FR-013, FR-016, FR-017, FR-018

### Phase 6: E2E Validation

Create test workflows and verify the full lifecycle:
1. Parent workflow with a `workflow` step referencing a child
2. Circular reference detection
3. Nesting depth enforcement
4. Child completion triggers parent advancement
5. Parent stop cascades to child

**Files**: Test workflow JSON files (temporary)
**FR coverage**: All FRs validated end-to-end

## Complexity Tracking

No constitution violations to justify. All changes are bounded, focused modifications to existing files.
