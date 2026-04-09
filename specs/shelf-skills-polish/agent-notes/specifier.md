# Specifier Friction Notes: Shelf Skills Polish

**Date**: 2026-04-08
**Agent**: specifier

## What Went Well

- The PRD was exceptionally detailed with clear FR numbering that mapped directly to backlog issues. This made writing the spec straightforward — I could trace every requirement back to its source.
- The existing `shelf-full-sync.json` workflow served as a perfect reference for the new workflow JSON formats. Having a working example made the contracts/interfaces.md much more concrete.
- The existing shelf skills all follow the same structure (project identity resolution, MCP operations, reporting), which made it easy to define consistent updates.

## Friction Points

1. **US2 (holistic progress detection) overlaps entirely with US1 (shelf-create workflow)**. The progress detection is just two steps within the shelf-create workflow — there's no independent work for US2. I handled this by noting "embedded in Phase 3 tasks" in the tasks.md, but it feels like US2 should have been merged with US1 in the PRD.

2. **The `check-duplicate` step has a gap**: the PRD says the workflow should abort if a project exists, but wheel workflows don't have conditional step execution (branch steps exist, but the abort semantics aren't clear). The implementer may need to handle this by having the `create-project` agent check the `check-duplicate` output and skip creation if it says "DUPLICATE".

3. **Status label validation in skills is instruction-only** — there's no enforcement mechanism beyond the agent reading the `status-labels.md` file and following instructions. This means a non-compliant agent could still set non-canonical values. Consider whether a hook-based enforcement would be more reliable (but that may be over-engineering for this scope).

## Suggestions

- Consider adding a `branch` step type to shelf-create.json that checks the `check-duplicate` output and skips to a "report-duplicate" terminal step. This would be cleaner than relying on the agent to read prior output.
- The `write-shelf-config` step is a command step but it probably needs the output from `read-shelf-config` — add `context_from` if the wheel engine supports command steps reading prior outputs via context. Currently the contracts assume command steps can reference `.wheel/outputs/` files directly via bash.
