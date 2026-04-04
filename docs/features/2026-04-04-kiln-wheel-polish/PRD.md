# Feature PRD: Kiln & Wheel Polish

**Date**: 2026-04-04
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)

## Background

The kiln and wheel plugins have accumulated several rough edges from rapid development. The wheel workflow engine lacks proper control flow for branch steps — mutually exclusive paths both execute because the cursor advances linearly. Workflow cleanup requires manual steps that should be automatic. Meanwhile, the kiln plugin's UX evaluator agent has a path bug creating nested directories, and users lack a lightweight TODO skill for quick ad-hoc tracking outside the formal spec pipeline.

This PRD bundles four open backlog items into one coherent polish pass.

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [Wheel engine needs step-level `next` field for branch subroutines](.kiln/issues/2026-04-04-wheel-branch-subroutine-support.md) | — | improvement | high |
| 2 | [Wheel: Move workflow cleanup into hook — detect terminal step IDs](.kiln/issues/2026-04-04-wheel-cleanup-in-hook.md) | — | improvement | medium |
| 3 | [Add /todo skill to kiln](.kiln/issues/2026-04-04-add-todo-skill.md) | — | feature-request | medium |
| 4 | [UX evaluator creates nested .kiln/qa/.kiln/qa/screenshots/](.kiln/issues/2026-04-02-ux-evaluator-nested-screenshot-dir.md) | — | bug | medium |

## Problem Statement

The wheel engine's linear cursor model means branch steps that route to mutually exclusive paths (e.g., success vs failure cleanup) execute both paths sequentially. This blocks realistic conditional logic in workflows and produces confusing results. Additionally, workflow cleanup (archiving state, removing state.json) is delegated to workflow steps instead of being handled automatically by the hook, leading to "no state file" errors and boilerplate in every workflow.

Separately, the UX evaluator agent creates screenshots in a nested `.kiln/qa/.kiln/qa/screenshots/` directory because it uses relative paths after `cd`-ing into `.kiln/qa/`. And kiln lacks a lightweight `/todo` command for tracking quick items outside the formal spec pipeline.

## Goals

- Wheel branch steps support mutually exclusive paths that don't bleed into each other
- Workflow cleanup happens automatically at terminal steps — no manual cleanup steps needed
- UX evaluator screenshots land in the correct directory regardless of working directory
- Users can track ad-hoc TODOs with a simple `/todo` command

## Non-Goals

- Full subroutine/function support in wheel (call/return semantics) — only linear `next` chaining
- Replacing `.kiln/issues/` with `/todo` — they serve different purposes
- Rearchitecting the wheel state machine beyond `next` field support
- Adding new QA agent capabilities beyond the path fix

## Requirements

### Functional Requirements

**Wheel: Branch Subroutine Support (from: 2026-04-04-wheel-branch-subroutine-support.md)**

- FR-001: Steps MAY include a `next` field containing a step ID. After the step completes, the engine jumps to that step instead of advancing cursor+1.
- FR-002: If a step has no `next` field and is not the last step, the engine advances to cursor+1 (backwards compatible).
- FR-003: If a step has no `next` field and is the last step in a branch path, the workflow ends (cursor set to total steps).
- FR-004: `dispatch_command` in `plugin-wheel/lib/dispatch.sh` must check for `next` field before defaulting to cursor+1.
- FR-005: `dispatch_agent` in `plugin-wheel/lib/dispatch.sh` must check for `next` field before defaulting to cursor+1.
- FR-006: `workflow_get_step_index` (or equivalent) must resolve a step ID to its array index for `next` field targeting.
- FR-007: Validation must reject workflows where a `next` field references a nonexistent step ID.

**Wheel: Automatic Cleanup at Terminal Steps (from: 2026-04-04-wheel-cleanup-in-hook.md)**

- FR-008: Steps MAY include a `terminal: true` field indicating the workflow should end after this step.
- FR-009: When a terminal step completes, the hook archives `state.json` to `.wheel/history/success/` or `.wheel/history/failure/` based on the step ID containing "success" or "failure" (default: success).
- FR-010: After archiving, the hook removes `.wheel/state.json`.
- FR-011: The "no state file" error in the hook should be downgraded to a silent no-op (workflow not active, nothing to do).
- FR-012: Existing workflows that use explicit cleanup steps must continue to work (terminal field is optional).

**Kiln: /todo Skill (from: 2026-04-04-add-todo-skill.md)**

- FR-013: Create a `/todo` skill at `plugin-kiln/skills/todo/` with a `prompt.md`.
- FR-014: `/todo` without arguments lists all open TODOs from `.kiln/todos.md`.
- FR-015: `/todo <text>` appends a new `- [ ] <text>` item with a date stamp to `.kiln/todos.md`.
- FR-016: `/todo done <N>` marks the Nth item as `- [x]` with a completion date.
- FR-017: `/todo clear` removes all completed items from the file.
- FR-018: The file format is plain markdown — one checkbox item per line, compatible with any markdown viewer.

**UX Evaluator Path Fix (from: 2026-04-02-ux-evaluator-nested-screenshot-dir.md)**

- FR-019: The UX evaluator agent must use absolute paths (relative to repo root) when creating the screenshot output directory.
- FR-020: The screenshot directory must always resolve to `${REPO_ROOT}/.kiln/qa/screenshots/` regardless of the agent's current working directory.
- FR-021: `/kiln-cleanup` should detect and remove nested `.kiln/` trees inside `.kiln/qa/` as a safety net.

### Non-Functional Requirements

- NFR-001: All wheel engine changes must be backwards compatible — existing workflows without `next` or `terminal` fields must work identically.
- NFR-002: The `/todo` skill must work without any prior setup — create `.kiln/todos.md` on first use if it doesn't exist.
- NFR-003: No new npm dependencies for any of these changes.

## User Stories

- As a workflow author, I want branch steps to only execute the matched path so that my success/failure cleanup logic doesn't collide.
- As a workflow author, I want cleanup to happen automatically when a workflow reaches a terminal step so that I don't need boilerplate cleanup steps in every workflow.
- As a developer using kiln, I want a quick `/todo` command to jot down tasks without going through the full spec pipeline.
- As a QA engineer, I want screenshots saved to the correct directory so that other tools can find and clean them up.

## Success Criteria

- A workflow with a branch step and two mutually exclusive paths only executes the matched path
- Workflows with `terminal: true` steps auto-archive state and remove state.json without manual intervention
- `/todo buy milk` creates an entry, `/todo` lists it, `/todo done 1` marks it complete
- UX evaluator screenshots appear in `.kiln/qa/screenshots/` (not nested) after a QA run
- All existing workflows and hooks continue to work without modification

## Tech Stack

- Bash 5.x (wheel hook scripts, dispatch.sh)
- Markdown (skill definitions, todo file format)
- jq (JSON parsing in hooks)
- Existing kiln/wheel plugin infrastructure — no new dependencies

## Risks & Open Questions

- **Branch termination semantics**: Should a branch path without `next` always end the workflow, or should it optionally merge back to the main flow? Starting with "ends the workflow" is simplest.
- **Terminal step naming convention vs explicit field**: Using `terminal: true` is more explicit than relying on step IDs containing "success"/"failure". PRD uses both — the field is authoritative, the ID is a fallback for categorizing the archive directory.
- **Todo scope creep**: The `/todo` skill should stay minimal — it's not a project management tool. If users need more structure, they should use `/report-issue` or the full spec pipeline.
