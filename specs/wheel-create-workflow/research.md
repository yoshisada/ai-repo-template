# Research: Wheel Create Workflow

**Date**: 2026-04-06
**Feature**: wheel-create-workflow

## Research Tasks

### 1. Workflow JSON Schema

**Finding**: The canonical workflow JSON schema is defined by `workflow_load` in `plugin-wheel/lib/workflow.sh`. Required fields:
- Top-level: `name` (string), `steps` (non-empty array)
- Per step: `id` (string), `type` (string)
- Step IDs must be unique
- Branch steps: `if_zero` and `if_nonzero` must reference valid step IDs
- `next` fields must reference valid step IDs
- `context_from` entries must reference valid step IDs

Step type schemas (from existing workflows):
- **command**: `id`, `type`, `command`, `output`. Optional: `context_from`, `next`
- **agent**: `id`, `type`, `instruction`, `output`. Optional: `context_from`, `terminal`, `next`
- **branch**: `id`, `type`, `condition`, `if_zero`, `if_nonzero`. Optional: `context_from`
- **loop**: `id`, `type`, `condition`, `max_iterations`. Has `substep` object. Optional: `output`, `on_exhaustion`

### 2. Existing Skill Patterns

**Finding**: All wheel skills follow the same pattern:
- SKILL.md with YAML frontmatter (`name`, `description`)
- Markdown body with numbered steps
- Inline bash code blocks for validation and output
- `$ARGUMENTS` placeholder for user input
- `$SKILL_BASE_DIR` for resolving plugin paths

### 3. Name Collision Handling

**Finding**: Simple bash loop checking `workflows/<name>.json`, `workflows/<name>-2.json`, etc. until an unused name is found. Consistent with FR-005.

### 4. Loop Step Schema (Updated)

**Finding**: Loop steps in the actual codebase use a `substep` field (object with `type` and `command`), not a top-level `command` field directly. The `condition` is a shell command that exits 0 when the loop should STOP (not continue). The PRD says "exits 0 to continue" but the actual implementation checks for the exit condition to terminate. We follow the actual implementation.

**Decision**: Use the actual schema from existing workflows, which includes `substep` for loops.
