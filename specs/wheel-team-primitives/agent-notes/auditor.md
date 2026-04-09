# Auditor Agent Notes: Wheel Team Primitives

**Date**: 2026-04-09
**Agent**: auditor (Task #5)

## What Went Well

- All 31 FRs are fully implemented across 5 files (dispatch.sh, state.sh, engine.sh, context.sh, workflow.sh, post-tool-use.sh).
- Clean file ownership split between impl-step-types (dispatch.sh) and impl-engine (state.sh, engine.sh, context.sh, workflow.sh, post-tool-use.sh) — no merge conflicts.
- The dispatch pattern is consistent: every team handler follows the same read-state → check-status → act → mark-done → advance pattern.
- Edge cases are handled: empty loop_from arrays, invalid JSON, max_agents <= 0, deleted teams, 0 teammates.
- Cascade stop logic in post-tool-use.sh correctly targets teammate sub-workflow state files.

## What Could Be Better

- **Instruction-based execution model**: The team-create, teammate, and team-delete steps inject natural language instructions for the orchestrator rather than calling tools directly. This means the engine trusts the LLM to follow instructions correctly. If the orchestrator misinterprets (e.g., creates wrong team name), the engine will not catch it until PostToolUse detection.
- **task_id tracking**: The teammate state records task_id but it's initially empty ("") and only populated if the PostToolUse hook detects a matching TaskCreate call. If the orchestrator names the task differently than the teammate name, the match may fail silently.
- **FR-017 poll interval**: Cannot be enforced at the hook level. Depends on orchestrator behavior.

## Friction Points

- Had to wait for both implementer tasks to complete before starting. No work could be parallelized with audit preparation because the spec directory wasn't created until Task #1 finished.
- Tasks.md shows T024/T025 unchecked (Phase 6 polish). The underlying functionality exists but formal validation wasn't run as a separate step by implementers.

## Recommendations

- Consider adding a `--dry-run` validation mode to team workflows that checks all fields and references without actually spawning agents.
- The instruction-injection pattern could benefit from structured tool calls (a "WheelTeamCreate" wrapper) rather than natural language prompts, to reduce LLM interpretation variance.
