# Specifier Friction Notes: Wheel Workflow Composition

## What went well

1. The PRD was exceptionally detailed with 18 FRs that mapped directly to spec requirements. No clarification markers were needed.
2. The existing codebase was well-structured — reading dispatch.sh, workflow.sh, engine.sh, state.sh, and the hooks gave a clear picture of how to extend the system.
3. The pattern for adding a new step type is well-established (agent, command, parallel, approval, branch, loop all follow the same dispatch pattern).

## What was confusing

1. **Fan-in ownership routing**: When both parent and child state files exist with the same `owner_session_id`/`owner_agent_id`, `resolve_state_file()` returns the first match. It was initially unclear which file would be matched and whether this would break routing. After studying guard.sh, I realized the child file would typically be matched (since the child is the "active" workflow), which is correct behavior.

2. **Where to put fan-in logic**: The PRD mentions fan-in in the hook (FR-012/FR-013), but after studying the code, `handle_terminal_step()` in dispatch.sh is the natural convergence point. I chose to put fan-in there rather than in the hook script directly, which deviates slightly from the PRD's phrasing but is architecturally cleaner.

3. **Kickstart vs hook activation**: The PRD says workflow steps are "not kickstartable" (FR-014) but the child's kickstart should work normally (FR-015). This dual behavior required understanding the difference between the parent's kickstart (which should skip workflow steps) and the child's kickstart (which should work as normal for command/loop/branch steps inside the child).

## What could be improved

1. **Spec directory naming**: The team lead specified `specs/wheel-workflow-composition/` as the directory. The `.specify` scripts tried to use a different naming convention. Having the team lead's naming requirement documented in the task description was essential.

2. **Constitution test coverage gate**: The constitution requires 80% test coverage, but this shell-based plugin has no test framework. This should probably be noted as an explicit exception in the constitution for shell script plugins.

3. **The `/specify` script's branch creation**: Since the branch already existed and was checked out, the spec creation flow needed to skip branch creation entirely. The `check-prerequisites.sh --json --paths-only` script correctly resolved the paths without trying to create a branch.
